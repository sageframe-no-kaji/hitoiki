import Darwin
import Foundation
import Testing

@testable import IssokuCore

/// A command run to Done: every byte it sent, how it ended, the offer, and its pid and group.
internal struct Outcome {
    let output: [UInt8]
    let exit: Exit
    let retry: String?
    let pid: pid_t

    var text: String { String(bytes: output, encoding: .utf8) ?? "" }
}

/// A state other than the one the test waited for.
internal struct UnexpectedState: Error {
    let state: RunState?
}

/// An environment the test owns.
///
/// HOME is the test's own empty directory, so the login shell reads no startup file of the user's;
/// HOME and LOGNAME are given because zsh exports them when absent.
internal func ownedEnvironment(home: String, path: String = "/usr/bin:/bin:/usr/sbin:/sbin") -> [String: String] {
    ["HOME": home, "LOGNAME": NSUserName(), "PATH": path, "TERM": "xterm-256color"]
}

/// Runs `line` to Done on a fresh Run started in `environment["HOME"]`.
///
/// With a `marker`, waits until the output holds it, then calls `act`. Run is released before the
/// rest of the bytes are read: its streams end with it, so every byte sent before Done is collected.
internal func drive(
    _ line: String,
    environment: [String: String],
    size: WindowSize = WindowSize(columns: 80, rows: 24),
    after marker: String? = nil,
    act: (Run, pid_t) async throws -> Void = { _, _ in }
) async throws -> Outcome {
    var output: [UInt8] = []
    var bytes: AsyncStream<[UInt8]>.Iterator
    let pid: pid_t
    let ended: RunState?
    do {
        let run = Run(environment: environment)
        bytes = run.bytes.makeAsyncIterator()
        var states = run.states.makeAsyncIterator()
        try await run.start(line: line, cwd: environment["HOME"] ?? "/", size: size)
        let started = await states.next()
        guard case .running(let running) = started else { throw UnexpectedState(state: started) }
        pid = running
        if let marker {
            while !output.contains(Array(marker.utf8)), let chunk = await bytes.next() {
                output += chunk
            }
        }
        try await act(run, pid)
        ended = await states.next()
        withExtendedLifetime(run) {}
    }
    while let chunk = await bytes.next() {
        output += chunk
    }
    guard case .done(let exit, let retry) = ended else { throw UnexpectedState(state: ended) }
    return Outcome(output: output, exit: exit, retry: retry, pid: pid)
}

/// What `/bin/ps` prints for `arguments`, trimmed.
///
/// The process table is the witness, not Run.
internal func ps(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The pids left in process group `group`, read until none remain or two seconds pass.
internal func survivors(ofGroup group: pid_t) async throws -> String {
    let deadline = ContinuousClock.now + .seconds(2)
    while true {
        let listed = try ps(["-o", "pid=", "-g", "\(group)"])
        if listed.isEmpty || ContinuousClock.now >= deadline {
            return listed
        }
        try await Task.sleep(for: .milliseconds(50))
    }
}

// Serialized: Run runs one command at a time by design, and the app never opens two pseudoterminals
// at once. Run tests in parallel with each other intermittently fail forkpty with errno -6.
@Suite("Run", .serialized)
internal struct RunTests {
    @Test("The pseudoterminal is the controlling terminal and the child leads a new group")
    internal func controllingTerminal() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive("tty; ps -o pid=,pgid=,tty= -p $$", environment: ownedEnvironment(home: home))
        let lines = outcome.text.split(whereSeparator: \.isNewline)
        try #require(lines.count == 2)
        let fields = lines[1].split(separator: " ")
        #expect(lines[0].hasPrefix("/dev/ttys"))
        #expect(fields == ["\(outcome.pid)", "\(outcome.pid)", lines[0].dropFirst("/dev/".count)])
        #expect(outcome.exit == .status(0))
    }

    @Test("The child sees exactly the environment Run was given, plus only what the shell sets")
    internal func exactEnvironment() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        var given = ownedEnvironment(home: home)
        given["ISSOKU_PROBE"] = "a b=c"
        #expect(try await printedEnvironment(given) == given)

        given["TERM"] = nil
        let supplied = try await printedEnvironment(given)
        #expect(supplied["TERM"] == "xterm-256color")
        #expect(supplied.filter { $0.key != "TERM" } == given)
    }

    /// What `/usr/bin/env` prints under Run, without the names the shell sets itself.
    private func printedEnvironment(_ environment: [String: String]) async throws -> [String: String] {
        let outcome = try await drive("/usr/bin/env", environment: environment)
        var printed: [String: String] = [:]
        for line in outcome.text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            printed[String(parts[0])] = String(parts[1])
        }
        return printed.filter { !LoginEnvironment.dropped.contains($0.key) }
    }

    @Test("The working directory comes from cwd; one that cannot be entered ends with 127")
    internal func workingDirectory() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive("pwd", environment: ownedEnvironment(home: home))
        #expect(outcome.text.hasSuffix(URL(fileURLWithPath: home).lastPathComponent + "\r\n"))
        let missing = try await drive("pwd", environment: ownedEnvironment(home: home + "/missing"))
        #expect(missing.exit == .status(127))
        #expect(missing.output.isEmpty)
    }

    @Test("The child inherits no descriptor above 2 from the parent")
    internal func noInheritedDescriptors() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let pipe = Pipe()
        #expect(pipe.fileHandleForWriting.fileDescriptor > 2)
        let outcome = try await drive("/bin/ls -1 /dev/fd", environment: ownedEnvironment(home: home))
        // 3 and 4 are the two descriptors ls opens itself (its working directory and /dev/fd), the
        // lowest free ones; without the close in the child, the parent's descriptors appear as well.
        #expect(outcome.text.split(whereSeparator: \.isNewline).compactMap { Int($0) }.sorted() == [0, 1, 2, 3, 4])
        withExtendedLifetime(pipe) {}
    }

    @Test("sudo's refusal through ssh ends with status 1 and the -tt offer; the offer then succeeds")
    internal func refusalAndRetry() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        _ = try writeScript(
            "ssh",
            in: home,
            body: """
                if [ "$1" = "-tt" ]; then echo ok; exit 0; fi
                /bin/cat '\(try sudoFixtureURL().path)' >&2
                exit 1
                """)
        let environment = ownedEnvironment(home: home, path: home)
        let refused = try await drive("ssh host 'sudo true'", environment: environment)
        let crlf = try sudoFixture().split(separator: 0x0A).map { Array($0) + [0x0D, 0x0A] }.joined()
        #expect(refused.output == Array(crlf))
        #expect(refused.exit == .status(1))
        #expect(refused.retry == "ssh -tt host 'sudo true'")

        let retried = try await drive(try #require(refused.retry), environment: environment)
        #expect(retried.text == "ok\r\n")
        #expect(retried.exit == .status(0))
        #expect(retried.retry == nil)
    }

    @Test("Keystrokes reach the child and nothing typed comes back")
    internal func keystrokes() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive(
            "stty -echo; echo ready; read -r secret; echo \"length ${#secret}\"",
            environment: ownedEnvironment(home: home),
            after: "ready"
        ) { run, _ in
            await run.write(Array("hunter2\n".utf8))
        }
        #expect(outcome.text.contains("length 7"))
        #expect(!outcome.output.contains(Array("hunter2".utf8)))
        #expect(outcome.exit == .status(0))
    }

    @Test("The window size reaches the child at spawn and on resize")
    internal func windowSize() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive(
            "stty size; echo ready; read -r line; stty size",
            environment: ownedEnvironment(home: home),
            size: WindowSize(columns: 100, rows: 30),
            after: "ready"
        ) { run, _ in
            await run.resize(WindowSize(columns: 132, rows: 50))
            await run.write([0x0A])
        }
        #expect(outcome.text.hasPrefix("30 100\r\n"))
        #expect(outcome.text.hasSuffix("50 132\r\n"))
    }

    @Test("exit 3 arrives as status 3")
    internal func exitStatus() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive("exit 3", environment: ownedEnvironment(home: home))
        #expect(outcome.exit == .status(3))
        #expect(outcome.retry == nil)
    }

    @Test("kill() ends the child with signal 9 and leaves no process in its group")
    internal func killed() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive(
            "echo ready; sleep 300",
            environment: ownedEnvironment(home: home),
            after: "ready"
        ) { run, _ in
            await run.kill()
        }
        #expect(outcome.exit == .signal(SIGKILL))
        #expect(try await survivors(ofGroup: outcome.pid).isEmpty)
    }

    @Test("Interrupt ends a shell and its two background sleeps; the process table is empty")
    internal func interruptGroup() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive(
            "sh -c 'sleep 300 & sleep 300 & echo ready; wait'",
            environment: ownedEnvironment(home: home),
            after: "ready"
        ) { run, pid in
            let members = try ps(["-o", "pid=", "-g", "\(pid)"])
            #expect(members.split(whereSeparator: \.isNewline).count >= 3)
            await run.interrupt()
        }
        // The status is the login shell's report of its interrupted child, not asserted here.
        #expect(outcome.exit != .status(0))
        #expect(try await survivors(ofGroup: outcome.pid).isEmpty)
    }

    @Test("A child that ignores the interrupt survives it and yields to kill; no orphan remains")
    internal func interruptIgnored() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive(
            "sh -c 'trap \"\" INT; echo ready; sleep 300'",
            environment: ownedEnvironment(home: home),
            after: "ready"
        ) { run, pid in
            await run.interrupt()
            try await Task.sleep(for: .milliseconds(300))
            let members = try ps(["-o", "pid=", "-g", "\(pid)"])
            #expect(!members.isEmpty)
            await run.kill()
        }
        #expect(outcome.exit == .signal(SIGKILL))
        #expect(try await survivors(ofGroup: outcome.pid).isEmpty)
    }

    // ho-02 Discovery, recorded: when the child exits normally, the session leader is gone and the
    // kernel hangs up the terminal; the backgrounded sleep (same group) receives SIGHUP and is gone
    // by Done. Run does nothing for this. A grandchild that ignores SIGHUP survives, detached.
    @Test("A backgrounded grandchild is gone after a normal exit (the kernel's hang-up)")
    internal func grandchildAfterNormalExit() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive("sh -c 'sleep 300 & echo $!; exit 0'", environment: ownedEnvironment(home: home))
        let sleeper = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(Int32(sleeper) != nil)
        let left = try await survivors(ofGroup: outcome.pid)
        if !left.isEmpty {
            killpg(outcome.pid, SIGKILL)
        }
        #expect(outcome.exit == .status(0))
        #expect(left.isEmpty)
    }

    @Test("One command at a time: a second start throws until Done")
    internal func oneAtATime() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let run = Run(environment: ownedEnvironment(home: home))
        var states = run.states.makeAsyncIterator()
        try await run.start(line: "sleep 300", cwd: home)
        _ = await states.next()
        await #expect(throws: RunError.alreadyRunning) {
            try await run.start(line: "true", cwd: home)
        }
        await run.kill()
        #expect(await states.next() == .done(.signal(SIGKILL), retry: nil))
        try await run.start(line: "true", cwd: home)
        _ = await states.next()
        #expect(await states.next() == .done(.status(0), retry: nil))
    }

    @Test("With no command alive, interrupt, kill, write and resize do nothing")
    internal func idle() async throws {
        let run = Run(environment: [:])
        await run.interrupt()
        await run.kill()
        await run.write([0x0A])
        await run.resize(WindowSize(columns: 10, rows: 10))
        try await run.start(line: "exit 0", cwd: "/")
    }

    @Test("Refresh requested while a command runs completes only after Done")
    internal func refreshWaits() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let run = Run(environment: ownedEnvironment(home: home))
        var states = run.states.makeAsyncIterator()
        try await run.start(line: "sleep 1", cwd: home)
        _ = await states.next()
        let order = Order()
        let refresh = Task {
            try await run.refreshEnvironment()
            await order.append("refreshed")
        }
        #expect(await states.next() == .done(.status(0), retry: nil))
        await order.append("done")
        try await refresh.value
        #expect(await order.events == ["done", "refreshed"])
        try await run.start(line: "exit 0", cwd: home)
        _ = await states.next()
        #expect(await states.next() == .done(.status(0), retry: nil))
    }

    @Test("ssh's own failure is status 255 with no offer (a closed local port; no host is touched)")
    internal func sshOwnStatus() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let outcome = try await drive(
            "ssh -p 1 -o ConnectTimeout=2 -o BatchMode=yes 127.0.0.1 true",
            environment: ownedEnvironment(home: home)
        )
        #expect(outcome.exit == .status(255))
        #expect(outcome.retry == nil)
    }

    @Test("forkpty from a detached task in the multithreaded test process reaches exec")
    internal func multithreadedParent() async throws {
        let home = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let environment = ownedEnvironment(home: home)
        let outcome = try await Task.detached {
            try await drive("echo detached", environment: environment)
        }.value
        #expect(outcome.text == "detached\r\n")
        #expect(outcome.exit == .status(0))
    }
}

/// The order events were observed in.
internal actor Order {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}
