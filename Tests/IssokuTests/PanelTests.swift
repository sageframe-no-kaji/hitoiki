// One suite, serialized, in the one test file ho-04's Decision 8 lists for the panel: the suite
// cannot move to a second file this ho does not name, so the file runs past the length rule.
// swiftlint:disable file_length

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

/// The test process's living children, less the `ps` that lists them, read until none remain or two
/// seconds pass.
private func children() async throws -> [String] {
    let deadline = ContinuousClock.now + .seconds(2)
    while true {
        let rows = try ps(["-o", "pid=,ppid=,comm=", "-A"]).split(separator: "\n").filter { row in
            let fields = row.split(separator: " ")
            return fields.count > 2 && fields[1] == "\(getpid())" && fields[2] != "/bin/ps"
        }
        if rows.isEmpty || ContinuousClock.now >= deadline {
            return rows.map(String.init)
        }
        try await Task.sleep(for: .milliseconds(50))
    }
}

/// Same components in the current appearance.
@MainActor
private func same(_ color: NSColor?, _ token: Palette) -> Bool {
    color?.usingColorSpace(.sRGB) == token.nsColor.usingColorSpace(.sRGB)
}

/// The transcript's attribute `key` at the first character of `text`.
@MainActor
private func attribute(_ key: NSAttributedString.Key, of text: String, in transcript: TranscriptView) -> Any? {
    let location = (transcript.string as NSString).range(of: text).location
    guard location != NSNotFound else { return nil }
    return transcript.textStorage?.attribute(key, at: location, effectiveRange: nil)
}

/// The general pasteboard's items, to put back after a test that writes it.
@MainActor
private func savePasteboard() -> [[(NSPasteboard.PasteboardType, Data)]] {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
    }
}

@MainActor
private func restorePasteboard(_ saved: [[(NSPasteboard.PasteboardType, Data)]]) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(
        saved.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        })
}

/// A key-down event for `window`, as AppKit would deliver it.
@MainActor
private func key(
    _ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow
) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code))
}

/// A condition the test waited ten seconds for.
private struct TimedOut: Error {}

/// A launch task that returns only once the test calls `open`.
@MainActor
private func gate() -> (launch: Task<Void, any Error>, open: () -> Void) {
    let (opened, opener) = AsyncStream<Void>.makeStream()
    return (Task { for await _ in opened {} }, { opener.finish() })
}

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

    /// An `ssh` in the test's directory, as ho-02's RunTests build it: sudo's refusal on stderr and
    /// status 1, unless its first argument is `-tt`, then `ok`, and status 0 once it reads a line.
    func writeFakeSSH() throws {
        let ssh = home + "/ssh"
        let script = """
            #!/bin/sh
            if [ "$1" = "-tt" ]; then echo ok; read -r line; exit 0; fi
            printf 'sudo: a terminal is required to read the password; either use the -S option to \
            read from standard input or configure an askpass helper\\nsudo: a password is required\\n' >&2
            exit 1

            """
        try script.write(toFile: ssh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ssh)
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
        // The read holds the command at its readiness point until Running has been asserted.
        fixture.panel.submit("echo ready; read -r line; exit 3")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        guard case .running = fixture.panel.state else {
            Issue.record("not Running at the readiness point: \(String(describing: fixture.panel.state))")
            return
        }
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
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
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
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
        try fixture.writeFakeSSH()

        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        #expect(!fixture.window.retryButton.isHidden)
        #expect(fixture.window.status.stringValue.contains("ssh -tt host 'sudo true'"))

        fixture.panel.submit("")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ok")
        guard case .running = fixture.panel.state else {
            Issue.record("not Running at the readiness point: \(String(describing: fixture.panel.state))")
            return
        }
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.retryButton.isHidden)
    }

    @Test("A dismissal takes a showing offer with it; an empty line then starts nothing")
    internal func dismissalClearsOffer() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()
        fixture.panel.show()
        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        fixture.panel.dismissIfAllowed()
        #expect(fixture.panel.state == nil)
        #expect(fixture.window.retryButton.isHidden)
        fixture.panel.show()
        fixture.panel.submit("")
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.panel.state == nil)
    }

    @Test("Dismissing returns the panel to Composing: no state, no transcript, no status, no buttons")
    internal func dismissalClears() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        try await fixture.transcriptContains("shown")
        #expect(!fixture.window.openButton.isHidden)

        fixture.panel.dismissIfAllowed()
        #expect(!fixture.window.isVisible)
        fixture.panel.show()
        #expect(fixture.panel.state == nil)
        #expect(fixture.window.transcript.string.isEmpty)
        #expect(fixture.window.status.stringValue.isEmpty)
        #expect(fixture.window.retryButton.isHidden)
        #expect(fixture.window.openButton.isHidden)
    }

    @Test("The block cursor shows only while Running and is never part of the transcript's text")
    internal func cursor() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        #expect(!fixture.window.transcript.showsCursor)
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(fixture.window.transcript.showsCursor)
        #expect(fixture.window.transcript.string == "ready\n")

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(!fixture.window.transcript.showsCursor)
        #expect(!fixture.window.transcript.string.contains("\u{2588}"))
        #expect(!fixture.window.transcript.string.contains("\u{FFFC}"))
        fixture.panel.dismissIfAllowed()
        #expect(!fixture.window.transcript.showsCursor)
    }
}

// The launch task, output, failure and quitting: an extension, not a second suite, so these stay
// serialized with the rest of Panel's tests.
extension PanelTests {
    @Test("The first command waits for the launch task")
    internal func launchTaskAwaited() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.submit("echo ready; read -r line")
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.panel.state == nil)
        #expect(fixture.window.transcript.string.isEmpty)

        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        guard case .running = fixture.panel.state else {
            Issue.record("not Running at the readiness point: \(String(describing: fixture.panel.state))")
            return
        }
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
    }

    @Test("A submission in flight cannot be dismissed, through the launch wait and while it runs")
    internal func inFlightIsUndismissable() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        await Task.yield()
        fixture.panel.dismissIfAllowed()
        fixture.panel.toggle()
        #expect(fixture.window.isVisible)
        #expect(fixture.window.isKeyWindow)
        #expect(!fixture.panel.canDismiss)
        #expect(fixture.panel.state == nil)

        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(!fixture.panel.canDismiss)
        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
        #expect(fixture.panel.canDismiss)
        fixture.panel.dismissIfAllowed()
        #expect(!fixture.window.isVisible)
    }

    @Test("A dismissal after start but before Running arrives leaves the panel up (ho-03x run 2)")
    internal func dismissalBeforeRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("sleep 30")
        await Task.yield()
        // Held, the main actor lets Run start the command without delivering Running.
        usleep(50_000)
        fixture.panel.dismissIfAllowed()
        #expect(fixture.window.isVisible)

        let pid = try await fixture.running()
        fixture.panel.stop()
        guard case .done(.signal, _) = try await fixture.done() else {
            Issue.record("not ended by a signal: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(try await survivors(ofGroup: pid).isEmpty)
        #expect(fixture.panel.canDismiss)
    }

    @Test("A second Return while the launch task is pending is ignored; one command runs")
    internal func oneSubmission() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.submit("touch \"$HOME/first\"; echo ready; read -r line")
        fixture.panel.submit("touch \"$HOME/second\"")
        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(FileManager.default.fileExists(atPath: fixture.home + "/first"))
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/second"))
        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/second"))
        guard case .done = fixture.panel.state else {
            Issue.record("not Done: \(String(describing: fixture.panel.state))")
            return
        }
    }

    @Test("Every chunk is drawn before Done, and none reaches the panel after a dismissal clears it")
    internal func outputBeforeDone() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("sleep 0.1; head -c 65536 /dev/zero | tr '\\000' x")
        _ = try await fixture.running()
        // Held, the main actor draws nothing while the command writes everything and ends.
        usleep(300_000)
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let text = fixture.window.transcript.string
        #expect(text.count == 65_536)
        #expect(text.allSatisfy { $0 == "x" })

        fixture.panel.dismissIfAllowed()
        fixture.panel.show()
        #expect(fixture.window.transcript.string.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.window.transcript.string.isEmpty)
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

    @Test("Quit during the launch wait kills the command once it starts and leaves no child")
    internal func killForQuitInFlight() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.submit("sleep 30")
        let quit = Task { await fixture.panel.killForQuit() }
        try await Task.sleep(for: .milliseconds(100))
        open()
        await quit.value
        #expect(fixture.panel.state == .done(.signal(SIGKILL), retry: nil))
        // No group check: the kill lands before the command can report its pid, and Done after SIGKILL is Run's reap.
        #expect(try await children().isEmpty)
    }

    @Test("Open in Terminal resolves Terminal.app")
    internal func terminalResolves() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Panel.terminal)
        #expect(url?.lastPathComponent == "Terminal.app")
    }
}

// The transcript (ho-04): what the model makes of real output, copying, and the two cards.
extension PanelTests {
    @Test("Colours reach the storage: red in the table's index 1, the rest in ink, no escape bytes")
    internal func colours() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("printf '\\033[31mred\\033[0m plain\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let transcript = fixture.window.transcript
        #expect(transcript.string == "red plain\n")
        #expect(same(attribute(.foregroundColor, of: "red", in: transcript) as? NSColor, Theme.transcriptColors[1]))
        #expect(same(attribute(.foregroundColor, of: "plain", in: transcript) as? NSColor, Theme.Token.ink))
    }

    @Test("Bold reaches the storage as the bold monospace font at the same size; the rest is regular")
    internal func bold() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("printf '\\033[1mbold\\033[22m plain\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let transcript = fixture.window.transcript
        #expect(transcript.string == "bold plain\n")
        let bold = try #require(attribute(.font, of: "bold", in: transcript) as? NSFont)
        let plain = try #require(attribute(.font, of: "plain", in: transcript) as? NSFont)
        #expect(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        #expect(bold.isFixedPitch)
        #expect(bold.pointSize == TranscriptView.font.pointSize)
        #expect(plain == TranscriptView.font)
    }

    @Test("A progress line rewrites itself in place")
    internal func progressLine() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("printf '1%%\\r2%%\\r3%%\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == "3%\n")
    }

    @Test("Copy: the whole transcript with no selection, only the selection with one; plain text only")
    internal func copy() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        fixture.panel.submit("printf '\\033[34mfirst\\033[0m line\\nsecond\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let transcript = fixture.window.transcript
        let pasteboard = NSPasteboard.general

        transcript.copy(nil)
        #expect(pasteboard.string(forType: .string) == "first line\nsecond\n")
        #expect(pasteboard.pasteboardItems?.map(\.types) == [[.string]])

        transcript.setSelectedRange(NSRange(location: 0, length: 5))
        transcript.copy(nil)
        #expect(pasteboard.string(forType: .string) == "first")
        #expect(pasteboard.pasteboardItems?.map(\.types) == [[.string]])

        transcript.setSelectedRange(NSRange(location: 0, length: 0))
        pasteboard.clearContents()
        fixture.window.copyButton.performClick(nil)
        #expect(pasteboard.string(forType: .string) == "first line\nsecond\n")
    }

    @Test("Composing is the bar alone; the output card shows from Running with Copy and goes at dismissal")
    internal func layout() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        #expect(fixture.window.outputCard.isHidden)
        #expect(fixture.window.frame.height == fixture.window.bar.frame.height)
        // The bar's row: the input, then the gear at the trailing edge, centred top to bottom.
        let row = try #require(fixture.window.input.superview as? NSStackView)
        let gear = try #require(row.arrangedSubviews.last)
        #expect(gear.frame.maxX == row.bounds.maxX)
        #expect(abs(gear.frame.midY - row.bounds.midY) <= 0.5)
        let composingGear = gear.frame.maxX

        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(!fixture.window.outputCard.isHidden)
        #expect(!fixture.window.copyButton.isHidden)
        #expect(fixture.window.frame.height > fixture.window.bar.frame.height + fixture.window.outputCard.frame.height)
        #expect(fixture.window.input.currentEditor() == nil)
        #expect(gear.frame.maxX == composingGear)
        let input = fixture.window.input
        #expect(input.alignmentRect(forFrame: input.frame).maxX + row.spacing == gear.frame.minX)

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(!fixture.window.outputCard.isHidden)
        fixture.panel.dismissIfAllowed()
        fixture.panel.show()
        #expect(fixture.window.outputCard.isHidden)
        #expect(fixture.window.transcript.string.isEmpty)
        #expect(fixture.window.frame.height == fixture.window.bar.frame.height)
    }

    @Test("The ceiling holds through the panel: 12,000 lines leave 10,000")
    internal func ceiling() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("yes | head -n 12000")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let lines = fixture.window.transcript.string.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 10_001)
        #expect(lines.dropLast().allSatisfy { $0 == "y" })
        #expect(lines.last?.isEmpty == true)
    }

    @Test("With no command running, Escape pressed in the transcript dismisses the panel")
    internal func escapeInTranscript() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let window = fixture.window
        #expect(window.makeFirstResponder(window.transcript))
        window.transcript.keyDown(with: try key("\u{1B}", code: 53, in: window))
        #expect(!window.isVisible)
        #expect(fixture.panel.state == nil)
    }

    @Test("With no command running, a character pressed in the transcript types into the input; Return submits it")
    internal func typingInTranscript() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let window = fixture.window
        #expect(window.makeFirstResponder(window.transcript))
        window.transcript.keyDown(with: try key("a", code: 0, in: window))
        #expect(window.input.stringValue == "a")
        #expect(window.input.currentEditor() != nil)
        #expect(window.isVisible)

        window.input.stringValue = "echo again"
        #expect(window.makeFirstResponder(window.transcript))
        window.transcript.keyDown(with: try key("\r", code: 36, in: window))
        try await fixture.transcriptContains("again")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == "again\n")
    }

    @Test("Command-C with the input focused copies the transcript, unless text is selected in the input")
    internal func commandC() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        fixture.panel.show()
        fixture.panel.submit("printf 'first line\\nsecond\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let window = fixture.window
        let pasteboard = NSPasteboard.general
        let editor = try #require(window.input.currentEditor())
        #expect(window.firstResponder === editor)

        pasteboard.clearContents()
        #expect(window.performKeyEquivalent(with: try key("c", code: 8, modifiers: .command, in: window)))
        #expect(pasteboard.string(forType: .string) == "first line\nsecond\n")

        window.input.stringValue = "typed text"
        editor.selectedRange = NSRange(location: 0, length: 5)
        pasteboard.clearContents()
        #expect(window.performKeyEquivalent(with: try key("c", code: 8, modifiers: .command, in: window)))
        #expect(pasteboard.string(forType: .string) == "typed")
    }

    @Test("The rows a command is told are the same in Composing as at Running")
    internal func terminalRows() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        #expect(fixture.window.outputCard.isHidden)
        let composing = fixture.window.terminalSize.rows
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(!fixture.window.outputCard.isHidden)
        #expect(fixture.window.terminalSize.rows == composing)
        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
    }

    @Test("The transcript enters its scroll view at the clip view's width, and a line wider than the panel wraps")
    internal func longLineWraps() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        // Before any layout the clip view already has the transcript's width: the transcript's width mask
        // becomes a constraint against it, and one made against a clip view with no width kept the
        // transcript that much wider than the clip in the running app.
        let bare = PanelWindow()
        let bareClip = try #require(bare.transcript.enclosingScrollView?.contentView)
        #expect(bareClip.bounds.width > 0)
        #expect(bareClip.bounds.width == bare.transcript.frame.width)
        fixture.panel.show()
        fixture.panel.submit("printf '%0.s-' $(seq 1 120); echo")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let transcript = fixture.window.transcript
        #expect(transcript.string == String(repeating: "-", count: 120) + "\n")
        let clip = try #require(transcript.enclosingScrollView?.contentView)
        #expect(transcript.frame.width == clip.bounds.width)
        let layout = try #require(transcript.layoutManager)
        var fragments = 0
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: 120)) { _, _, _, _, _ in
            fragments += 1
        }
        #expect(fragments == 2)
    }

    @Test("After Stop nothing more is drawn; Done arrives within seconds; the next command draws again")
    internal func nothingDrawnAfterStop() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("yes | head -n 2000000")
        _ = try await fixture.running()
        let transcript = fixture.window.transcript
        try await fixture.until { transcript.string.count > 10_000 }
        let drawn = transcript.string
        let clock = ContinuousClock()
        let asked = clock.now
        fixture.panel.stop()
        guard case .done = try await fixture.done() else {
            Issue.record("not Done: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(clock.now - asked < .seconds(5))
        #expect(transcript.string == drawn)

        fixture.panel.submit("echo again")
        try await fixture.transcriptContains("again")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(transcript.string == "again\n")
    }
}
