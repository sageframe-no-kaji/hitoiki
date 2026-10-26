import Darwin
import Dispatch
import Foundation

// issoku-spike [--plain] [--capture <path>] -- <command line>
//
// The ho-01 harness. Spawns `<login shell> -c <command line>` under a PTY in a new process
// group with the login shell's captured environment, streams the child's bytes, and prints
// one status line to stderr:
//
//   spike: exit <n> | signal <n> · spawn→first-byte <ms> ms · spawn→exit <ms> ms
//
// SIGINT to the harness → killpg(group, SIGINT). SIGTERM to the harness → killpg(group, SIGKILL).
//
// Under --plain, stdout shows the line in progress as it grows, not only committed lines, so a
// prompt that ends without LF (sudo's) is visible while the child waits for the answer.

private struct Options {
    var plain = false
    var capturePath: String?
    var line = ""
}

private func parseOptions(_ arguments: ArraySlice<String>) -> Options? {
    var options = Options()
    var remaining = arguments
    while let argument = remaining.popFirst() {
        switch argument {
        case "--plain":
            options.plain = true
        case "--capture":
            guard let path = remaining.popFirst() else { return nil }
            options.capturePath = path
        case "--":
            guard remaining.count == 1, let line = remaining.first else { return nil }
            options.line = line
            return options
        default:
            return nil
        }
    }
    return nil
}

private func writeAll(_ descriptor: Int32, _ bytes: some Collection<UInt8>) {
    var pending = Array(bytes)[...]
    while !pending.isEmpty {
        let written = pending.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        if written > 0 {
            pending = pending.dropFirst(written)
        } else if written < 0 && (errno == EINTR || errno == EAGAIN) {
            continue
        } else {
            return
        }
    }
}

private func writeError(_ text: String) {
    writeAll(2, Array(text.utf8))
}

private func milliseconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    return String(format: "%.1f", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
}

// What --plain has already written of the line in progress. Each update writes only what is
// new; a line that no longer starts with what was written (a CR rewound it, or the cap cut its
// front) is rewritten from column zero, and ESC [ K clears what the earlier rendering left past
// its end.
private struct LineEcho {
    private var shown: [UInt8] = []

    private mutating func update(to line: [UInt8]) -> [UInt8] {
        let bytes: [UInt8]
        if line.starts(with: shown) {
            bytes = Array(line[shown.count...])
        } else {
            bytes = [0x0D] + line + [0x1B, UInt8(ascii: "["), UInt8(ascii: "K")]
        }
        shown = line
        return bytes
    }

    mutating func show(_ line: [UInt8]) {
        writeAll(1, update(to: line))
    }

    mutating func commit(_ line: [UInt8]) {
        writeAll(1, update(to: line) + [0x0A])
        shown.removeAll(keepingCapacity: true)
    }
}

// Forwards the harness's stdin to the master, byte for byte, when stdin is a terminal.
// Each read lands in a buffer local to one handler call, is written to the master, and
// goes nowhere else.
private func forwardStdin(to master: Int32, on queue: DispatchQueue) -> DispatchSourceRead {
    let source = DispatchSource.makeReadSource(fileDescriptor: 0, queue: queue)
    source.setEventHandler {
        var buffer = [UInt8](repeating: 0, count: 1_024)
        let count = buffer.withUnsafeMutableBytes { read(0, $0.baseAddress, $0.count) }
        if count > 0 {
            writeAll(master, buffer[0..<count])
        } else {
            source.cancel()
        }
    }
    source.resume()
    return source
}

private func run(_ arguments: [String]) -> Int32 {
    guard let options = parseOptions(arguments.dropFirst()) else {
        writeError("usage: issoku-spike [--plain] [--capture <path>] -- <command line>\n")
        return 2
    }

    let environment: LoginEnvironment
    do {
        environment = try captureLoginEnvironment()
    } catch {
        writeError("spike: environment capture failed: \(error)\n")
        return 1
    }

    var capture: Int32 = -1
    if let path = options.capturePath {
        capture = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard capture >= 0 else {
            writeError("spike: cannot open capture \(path): \(String(cString: strerror(errno)))\n")
            return 1
        }
    }

    let terminal = TerminalMode()
    let clock = ContinuousClock()
    let spawnInstant = clock.now
    let child: PTYChild
    do {
        child = try spawnUnderPTY(shell: environment.shell, line: options.line, environment: environment.variables)
    } catch {
        writeError("spike: spawn failed: \(error)\n")
        return 1
    }

    // Signals arrive as dispatch events; the default dispositions are set aside only after
    // the fork, so the child never inherits them.
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let signalQueue = DispatchQueue(label: "issoku-spike.signals")
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
    interrupt.setEventHandler { _ = killpg(child.pid, SIGINT) }
    interrupt.resume()
    let force = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
    force.setEventHandler { _ = killpg(child.pid, SIGKILL) }
    force.resume()

    terminal.enterRaw()
    let input =
        terminal.isTerminal ? forwardStdin(to: child.master, on: DispatchQueue(label: "issoku-spike.stdin")) : nil

    var readBuffer = [UInt8](repeating: 0, count: 65_536)
    // Decision 6: 10,000 lines; amended, at most 1 MiB in the line in progress.
    let lineByteLimit = 1_048_576
    var ring = LineRing(capacity: 10_000, lineByteLimit: lineByteLimit)
    var model = options.plain ? PlainModel(lineByteLimit: lineByteLimit) : nil
    var echo = LineEcho()
    var firstByteInstant: ContinuousClock.Instant?

    while true {
        let count = readBuffer.withUnsafeMutableBytes { read(child.master, $0.baseAddress, $0.count) }
        if count > 0 {
            if firstByteInstant == nil { firstByteInstant = clock.now }
            let chunk = readBuffer[0..<count]
            if capture >= 0 { writeAll(capture, chunk) }
            if model != nil {
                // The ring takes committed lines whole; stdout has already shown most of each.
                model?.feed(chunk) { line in
                    echo.commit(line)
                    ring.append(line: line)
                }
                if let line = model?.lineInProgress { echo.show(line) }
            } else {
                writeAll(1, chunk)
                ring.append(bytes: chunk)
            }
        } else if count < 0 && errno == EINTR {
            continue
        } else {
            // 0, or EIO once every holder of the slave has closed it.
            break
        }
    }
    if let partial = model?.finish() {
        echo.show(partial)
        ring.append(line: partial)
    }

    var status: Int32 = 0
    while waitpid(child.pid, &status, 0) < 0 && errno == EINTR {}
    let exitInstant = clock.now
    input?.cancel()
    terminal.restore()
    if capture >= 0 { close(capture) }
    close(child.master)

    let firstByte = firstByteInstant.map { milliseconds($0 - spawnInstant) + " ms" } ?? "none"
    let total = milliseconds(exitInstant - spawnInstant) + " ms"
    let termination = status & 0x7F
    let outcome: String
    let code: Int32
    if termination == 0 {
        code = (status >> 8) & 0xFF
        outcome = "exit \(code)"
    } else {
        code = 128 + termination
        outcome = "signal \(termination)"
    }
    writeError("spike: \(outcome) · spawn→first-byte \(firstByte) · spawn→exit \(total)\n")
    return code
}

exit(run(CommandLine.arguments))
