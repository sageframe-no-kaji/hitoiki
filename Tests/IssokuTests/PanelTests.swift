import AppKit
import Darwin
import Foundation
import IssokuCore
import Testing

@testable import Issoku

/// A directory the test owns, removed by the test.
private func makeDirectory() throws -> String {
    let path = NSTemporaryDirectory() + "issoku-panel-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

/// An environment the test owns: HOME is the test's empty directory, so the login shell reads no
/// startup file of the user's.
private func ownedEnvironment(home: String, path: String = "/usr/bin:/bin:/usr/sbin:/sbin") -> [String: String] {
    ["HOME": home, "LOGNAME": NSUserName(), "PATH": path, "TERM": "xterm-256color"]
}

/// What `/bin/ps` prints for `arguments`, trimmed: the process table is the witness, not Run.
private func ps(_ arguments: [String]) throws -> String {
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
private func survivors(ofGroup group: pid_t) async throws -> String {
    let deadline = ContinuousClock.now + .seconds(2)
    while true {
        let listed = try ps(["-o", "pid=", "-g", "\(group)"])
        if listed.isEmpty || ContinuousClock.now >= deadline {
            return listed
        }
        try await Task.sleep(for: .milliseconds(50))
    }
}

/// Same components in the current appearance.
@MainActor
private func same(_ color: NSColor?, _ token: Palette) -> Bool {
    color?.usingColorSpace(.sRGB) == token.nsColor.usingColorSpace(.sRGB)
}

/// A condition the test waited ten seconds for.
private struct TimedOut: Error {}

/// A Panel over a real Run and a real window, in a directory the test owns.
@MainActor
private struct Fixture {
    let home: String
    let panel: Panel
    let window: PanelWindow

    /// `homeOnPath` makes the test's directory the whole `PATH`, for a fake `ssh`.
    init(
        homeOnPath: Bool = false,
        launch: Task<Void, any Error> = Task {},
        directory: ((String) -> String)? = nil
    ) throws {
        home = try makeDirectory()
        window = PanelWindow()
        let environment = homeOnPath ? ownedEnvironment(home: home, path: home) : ownedEnvironment(home: home)
        panel = Panel(
            run: Run(environment: environment),
            launch: launch,
            window: window,
            directory: directory?(home) ?? home)
    }

    /// Waits, between main-actor jobs, until `condition` holds.
    func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Every distinct value `state` takes, sampled after each main-actor job, until a run is `.done`.
    func trace() async throws -> [RunState?] {
        let deadline = ContinuousClock.now + .seconds(10)
        var seen: [RunState?] = [panel.state]
        while true {
            await Task.yield()
            if panel.state != seen.last { seen.append(panel.state) }
            if case .done = panel.state, seen.count > 1 { return seen }
            guard ContinuousClock.now < deadline else { throw TimedOut() }
        }
    }

    /// The pid of the running command, once Panel shows it running.
    func running() async throws -> pid_t {
        try await until {
            if case .running = panel.state { return true }
            return false
        }
        guard case .running(let pid) = panel.state else { throw TimedOut() }
        return pid
    }

    func done() async throws -> RunState? {
        try await until {
            if case .done = panel.state { return true }
            return false
        }
        return panel.state
    }

    func transcriptContains(_ text: String) async throws {
        try await until { window.transcript.string.contains(text) }
    }

    func tearDown() {
        window.orderOut(nil)
        try? FileManager.default.removeItem(atPath: home)
    }
}

// Serialized and on the main actor: Panel is main-actor bound, and two Runs spawning at once
// intermittently fail forkpty (ho-02 Reflect).
@Suite("Panel", .serialized)
@MainActor
internal struct PanelTests {
    @Test("Composing: dismissable; show focuses the input; dismiss hides; the hotkey toggles")
    internal func composing() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        #expect(fixture.panel.state == nil)
        #expect(fixture.panel.canDismiss)
        fixture.panel.show()
        #expect(fixture.window.isVisible)
        #expect(fixture.window.input.currentEditor() != nil)
        fixture.panel.dismissIfAllowed()
        #expect(!fixture.window.isVisible)
        fixture.panel.toggle()
        #expect(fixture.window.isVisible)
        fixture.panel.toggle()
        #expect(!fixture.window.isVisible)
    }

    @Test("A command goes Running then Done; a failing status is shown in the alarm colour")
    internal func submit() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("exit 3")
        let states = try await fixture.trace()
        #expect(states.count == 3)
        #expect(states.first == .some(nil))
        guard case .running = states.dropFirst().first else {
            Issue.record("no Running state between Composing and Done: \(states)")
            return
        }
        #expect(states.last == .done(.status(3), retry: nil))
        #expect(fixture.window.status.stringValue == "exit 3")
        #expect(same(fixture.window.status.textColor, Theme.Token.alarm))
    }

    @Test("An empty or blank line starts nothing", arguments: ["", "   "])
    internal func blankLine(line: String) async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit(line)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.panel.state == nil)
    }

    @Test("Running cannot be dismissed; keys go to the transcript; Stop ends it and its group")
    internal func runningIsUndismissable() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("sleep 30")
        let pid = try await fixture.running()
        #expect(!fixture.panel.canDismiss)
        fixture.panel.dismissIfAllowed()
        #expect(fixture.window.isVisible)
        fixture.panel.toggle()
        #expect(fixture.window.isVisible)
        #expect(fixture.window.isKeyWindow)
        #expect(fixture.window.input.currentEditor() == nil)
        #expect(fixture.window.firstResponder === fixture.window.transcript)
        #expect(!fixture.window.stopButton.isHidden)

        fixture.panel.stop()
        let ended = try await fixture.done()
        #expect(ended != .done(.status(0), retry: nil))
        #expect(try await survivors(ofGroup: pid).isEmpty)
        #expect(fixture.panel.canDismiss)
        #expect(fixture.window.stopButton.isHidden)
        fixture.panel.dismissIfAllowed()
        #expect(!fixture.window.isVisible)
    }

    @Test("Stop interrupts, a second Stop kills; the count starts again at Done")
    internal func stopTwice() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        // `echo ready` follows the trap, so the first Stop cannot arrive before it is set.
        fixture.panel.submit("sh -c 'trap \"\" INT; echo ready; sleep 300'")
        let pid = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.stop()
        try await Task.sleep(for: .milliseconds(500))
        #expect(try !ps(["-o", "pid=", "-g", "\(pid)"]).isEmpty)
        fixture.panel.stop()
        #expect(try await fixture.done() == .done(.signal(SIGKILL), retry: nil))
        #expect(try await survivors(ofGroup: pid).isEmpty)

        fixture.panel.submit("sleep 30")
        let next = try await fixture.running()
        fixture.panel.stop()
        let ended = try await fixture.done()
        #expect(ended != .done(.signal(SIGKILL), retry: nil))
        #expect(try await survivors(ofGroup: next).isEmpty)
    }

    @Test("Keystrokes reach the command and nothing typed is drawn")
    internal func keystrokes() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("stty -echo; echo ready; read -r secret; echo \"length ${#secret}\"")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.keystroke(.write(Array("hunter2".utf8)))
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        try await fixture.transcriptContains("length 7")
        #expect(!fixture.window.transcript.string.contains("hunter2"))
    }

    @Test("Paste writes the general pasteboard's string to the command")
    internal func paste() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(
                saved.map { entries in
                    let item = NSPasteboardItem()
                    for (type, data) in entries {
                        item.setData(data, forType: type)
                    }
                    return item
                })
        }
        pasteboard.clearContents()
        pasteboard.setString("thirteen-long", forType: .string)

        fixture.panel.submit("echo ready; read -r line; echo \"length ${#line}\"")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.keystroke(.paste)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        try await fixture.transcriptContains("length 13")
    }

    @Test("The -tt offer: Retry is shown, an empty line takes it, and it clears at the next run")
    internal func offer() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        let ssh = fixture.home + "/ssh"
        let script = """
            #!/bin/sh
            if [ "$1" = "-tt" ]; then echo ok; exit 0; fi
            printf 'sudo: a terminal is required to read the password; either use the -S option to \
            read from standard input or configure an askpass helper\\nsudo: a password is required\\n' >&2
            exit 1

            """
        try script.write(toFile: ssh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ssh)

        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        #expect(!fixture.window.retryButton.isHidden)
        #expect(fixture.window.status.stringValue.contains("ssh -tt host 'sudo true'"))

        fixture.panel.submit("")
        let states = try await fixture.trace()
        #expect(states.count == 3)
        #expect(states.last == .done(.status(0), retry: nil))
        #expect(fixture.window.retryButton.isHidden)
        try await fixture.transcriptContains("ok")
    }

    @Test("The first command waits for the launch task")
    internal func launchTaskAwaited() async throws {
        let clock = ContinuousClock()
        let created = clock.now
        let fixture = try Fixture(launch: Task { try await Task.sleep(for: .milliseconds(300)) })
        defer { fixture.tearDown() }
        fixture.panel.submit("echo ready")
        try await fixture.until {
            if case .running = fixture.panel.state { return true }
            if case .done = fixture.panel.state { return true }
            return false
        }
        #expect(clock.now - created >= .milliseconds(300))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
    }

    @Test(
        "A failed capture is a notice in plain words; the command still runs",
        arguments: [
            (LoginEnvironment.CaptureError.noLoginShell, "no login shell"),
            (.shellFailed(status: 2), "shell exited 2"),
            (.timedOut, "timed out after five seconds"),
        ])
    internal func launchTaskFailed(error: LoginEnvironment.CaptureError, reason: String) async throws {
        let fixture = try Fixture(launch: Task { throw error })
        defer { fixture.tearDown() }
        fixture.panel.submit("true")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        try await fixture.until { fixture.window.notice.stringValue.contains("not captured") }
        #expect(fixture.window.notice.stringValue.contains(reason))
    }

    // ho-02 Reflect: a directory that cannot be entered ends the child with 127, silently. The
    // directory setting and its validation are ho-05's; this records what Panel shows today.
    @Test("A working directory that does not exist still reaches Done, non-zero")
    internal func missingDirectory() async throws {
        let fixture = try Fixture { $0 + "/missing" }
        defer { fixture.tearDown() }
        fixture.panel.submit("pwd")
        let ended = try await fixture.done()
        #expect(ended == .done(.status(127), retry: nil))
        #expect(same(fixture.window.status.textColor, Theme.Token.alarm))
    }

    @Test("Quit kills a running command within about a second and leaves its group empty")
    internal func killForQuit() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("sleep 300")
        let pid = try await fixture.running()
        let clock = ContinuousClock()
        let asked = clock.now
        await fixture.panel.killForQuit()
        #expect(clock.now - asked < .milliseconds(1_500))
        #expect(fixture.panel.state == .done(.signal(SIGKILL), retry: nil))
        #expect(try await survivors(ofGroup: pid).isEmpty)
    }

    @Test("Open in Terminal resolves Terminal.app")
    internal func terminalResolves() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Panel.terminal)
        #expect(url?.lastPathComponent == "Terminal.app")
    }
}
