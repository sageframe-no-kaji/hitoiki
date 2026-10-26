import Darwin
import Dispatch
import Foundation
import IssokuCore

// issoku-run [--env] -- <command line>
//
// The ho-02 run-sheet driver: the production Run over a real terminal, for the practitioner's
// runs against real hosts until the panel exists. ho-03's first commit deletes it.
//
// Control-C once calls interrupt(); again calls kill(). On Done, one line to stderr,
// `issoku-run: exit <n>` or `issoku-run: signal <n>`, then `retry: <line>` when there is an offer.

private func writeAll(_ descriptor: Int32, _ bytes: [UInt8]) {
    var offset = 0
    while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        if written > 0 {
            offset += written
        } else if errno != EINTR {
            return
        }
    }
}

private func writeError(_ text: String) {
    writeAll(2, Array(text.utf8))
}

/// fd 0 while Running: raw with echo off.
///
/// ISIG is kept so Control-C arrives as SIGINT, and output processing so the driver's own LF
/// returns the carriage. Restored on every exit path.
private struct TerminalMode {
    private let saved: termios?

    init() {
        var state = termios()
        saved = isatty(0) == 1 && tcgetattr(0, &state) == 0 ? state : nil
    }

    var isTerminal: Bool { saved != nil }

    /// The terminal's own window size, or 80 by 24 when stdout is not a terminal.
    var size: WindowSize {
        var window = winsize()
        guard ioctl(1, TIOCGWINSZ, &window) == 0, window.ws_col > 0 else { return WindowSize(columns: 80, rows: 24) }
        return WindowSize(columns: window.ws_col, rows: window.ws_row)
    }

    func enterRaw() {
        guard var raw = saved else { return }
        cfmakeraw(&raw)
        raw.c_lflag |= tcflag_t(ISIG)
        raw.c_oflag |= tcflag_t(OPOST | ONLCR)
        tcsetattr(0, TCSAFLUSH, &raw)
    }

    func restore() {
        guard var state = saved else { return }
        tcsetattr(0, TCSAFLUSH, &state)
    }
}

/// Each delivery of `number`, which is ignored as a disposition so it reaches only this stream.
private func deliveries(of number: Int32) -> AsyncStream<Void> {
    signal(number, SIG_IGN)
    return AsyncStream { continuation in
        let source = DispatchSource.makeSignalSource(signal: number, queue: DispatchQueue(label: "issoku-run.signal"))
        source.setEventHandler { continuation.yield() }
        continuation.onTermination = { _ in source.cancel() }
        source.resume()
    }
}

/// The bytes typed on fd 0, each read handed on and kept nowhere.
private func keystrokes() -> AsyncStream<[UInt8]> {
    AsyncStream { continuation in
        let source = DispatchSource.makeReadSource(fileDescriptor: 0, queue: DispatchQueue(label: "issoku-run.stdin"))
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 1_024)
            let count = buffer.withUnsafeMutableBytes { read(0, $0.baseAddress, $0.count) }
            if count > 0 {
                continuation.yield(Array(buffer[..<count]))
            } else {
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in source.cancel() }
        source.resume()
    }
}

private func drive(line: String, environment: [String: String]) async -> Int32 {
    let terminal = TerminalMode()
    let printer: Task<Void, Never>
    let ended: RunState?
    do {
        let run = Run(environment: environment)
        let bytes = run.bytes
        printer = Task {
            for await chunk in bytes {
                writeAll(1, chunk)
            }
        }
        var states = run.states.makeAsyncIterator()
        do {
            try await run.start(line: line, cwd: FileManager.default.currentDirectoryPath, size: terminal.size)
        } catch {
            writeError("issoku-run: start failed: \(error)\n")
            return 1
        }
        let interrupts = deliveries(of: SIGINT)
        let stops = Task {
            var count = 0
            for await _ in interrupts {
                count += 1
                if count == 1 {
                    await run.interrupt()
                } else {
                    await run.kill()
                }
            }
        }
        terminal.enterRaw()
        let typing =
            terminal.isTerminal
            ? Task {
                for await chunk in keystrokes() {
                    await run.write(chunk)
                }
            } : nil
        _ = await states.next()
        ended = await states.next()
        terminal.restore()
        stops.cancel()
        typing?.cancel()
        withExtendedLifetime(run) {}
    }
    // Run's byte stream ends once Run is released, after every byte sent before Done.
    await printer.value

    guard case .done(let exit, let retry) = ended else { return 1 }
    let code: Int32
    switch exit {
    case .status(let status):
        writeError("issoku-run: exit \(status)\n")
        code = status
    case .signal(let number):
        writeError("issoku-run: signal \(number)\n")
        code = 128 + number
    }
    if let retry {
        writeError("retry: \(retry)\n")
    }
    return code
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["--env"] || (arguments.count == 2 && arguments[0] == "--") else {
    writeError("usage: issoku-run [--env] -- <command line>\n")
    exit(2)
}
let environment: [String: String]
do {
    environment = try LoginEnvironment.capture()
} catch {
    writeError("issoku-run: environment capture failed: \(error)\n")
    exit(1)
}
if arguments == ["--env"] {
    let names = environment.keys.sorted()
    print(names.joined(separator: "\n"))
    print("\(names.count) variables")
    exit(0)
}
exit(await drive(line: arguments[1], environment: environment))
