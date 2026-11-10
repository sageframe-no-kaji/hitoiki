// One suite, serialized, in the one test file ho-04's Decision 8 lists for the panel: the suite
// cannot move to a second file this ho does not name, so the file runs past the length rule.
// swiftlint:disable file_length

import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import Testing

@testable import Hitoiki
@testable import HitoikiCore

/// A directory the test owns, removed by the test.
private func makeDirectory() throws -> String {
    let path = NSTemporaryDirectory() + "hitoiki-panel-tests-" + UUID().uuidString
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

/// The panel in the vocabulary of ho-04.6: visibility, key status, `state`, transcript text, status
/// text, the offer, and the input's text.
private struct Look: Equatable {
    /// Clean, on screen, with the keyboard.
    static let clean = Self(visible: true, key: true, state: nil, transcript: "", status: "", offer: false, input: "")

    let visible: Bool
    let key: Bool
    let state: RunState?
    let transcript: String
    let status: String
    let offer: Bool
    let input: String

    /// The same panel off screen: a hide changes nothing else.
    var hidden: Self { on(screen: false, key: false) }

    /// The same panel on screen with the keyboard, as a show or taking the keyboard leaves it.
    var withKeyboard: Self { on(screen: true, key: true) }

    /// The same panel on screen without the keyboard, as a click-out leaves a running one.
    var withoutKeyboard: Self { on(screen: true, key: false) }

    /// The same panel with `input` in the input: a macro's load changes nothing else.
    func with(input: String) -> Self {
        Self(
            visible: visible,
            key: key,
            state: state,
            transcript: transcript,
            status: status,
            offer: offer,
            input: input)
    }

    private func on(screen: Bool, key: Bool) -> Self {
        Self(
            visible: screen,
            key: key,
            state: state,
            transcript: transcript,
            status: status,
            offer: offer,
            input: input)
    }
}

/// A launch task that returns only once the test calls `open`.
@MainActor
private func gate() -> (launch: Task<Void, any Error>, open: () -> Void) {
    let (opened, opener) = AsyncStream<Void>.makeStream()
    return (Task { for await _ in opened {} }, { opener.finish() })
}

/// A Panel over a real Run, a real window and a store over a throwaway suite, its commands starting in a
/// directory the test owns: the store's fixed folder.
@MainActor
private struct Fixture {
    let home: String
    let panel: Panel
    let window: PanelWindow
    let suite: ThrowawaySuite
    let settings: Settings
    /// Another window, in this app, for a click-out to give the keyboard to.
    let other = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
        styleMask: [.titled, .nonactivatingPanel],
        backing: .buffered,
        defer: false)

    /// `homeOnPath` makes the test's directory the whole `PATH`, for a fake `ssh`; `failingCapture` makes
    /// Refresh Environment's capture a shell that exits 3.
    init(homeOnPath: Bool = false, launch: Task<Void, any Error> = Task {}, failingCapture: Bool = false) throws {
        home = try makeDirectory()
        window = PanelWindow()
        suite = try ThrowawaySuite()
        settings = Settings(defaults: suite.defaults)
        settings.directoryMode = .fixed
        settings.directoryPath = home
        let environment = homeOnPath ? ownedEnvironment(home: home, path: home) : ownedEnvironment(home: home)
        var captureShell: String?
        if failingCapture {
            let shell = home + "/failing-shell"
            try "#!/bin/sh\nexit 3\n".write(toFile: shell, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell)
            captureShell = shell
        }
        panel = Panel(
            run: Run(environment: environment, captureShell: captureShell),
            launch: launch,
            window: window,
            settings: settings)
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

    /// The panel as the vocabulary reads it.
    func look() -> Look {
        Look(
            visible: window.isVisible,
            key: window.isKeyWindow,
            state: panel.state,
            transcript: window.transcript.string,
            status: window.status.stringValue,
            offer: !window.retryButton.isHidden,
            input: window.input.stringValue)
    }

    /// The keyboard is in the input: its field editor is the window's first responder.
    var keyboardInInput: Bool {
        guard let editor = window.input.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    /// A click into another window: that window takes the keyboard, and the panel's resign-key path runs.
    func clickOut() {
        other.makeKeyAndOrderFront(nil)
    }

    /// The panel on screen without the keyboard: after a click-out, ordered front if the click-out hid it.
    func loseKeyboard() {
        clickOut()
        if !window.isVisible { window.orderFront(nil) }
    }

    /// The command alive and reading: writes `tag` and a carriage return to it and waits for the file
    /// `Fixture.held` touches for that line.
    func alive(_ tag: String) async throws {
        panel.keystroke(.write(Array("\(tag)\r".utf8)))
        try await until { FileManager.default.fileExists(atPath: home + "/got-" + tag) }
    }

    /// Opens the launch, and if a command runs or is in flight, kills it, waits for its Done and
    /// checks that its group is gone.
    func end(opening open: () -> Void) async throws {
        open()
        guard panel.isBusy else { return }
        let group = try await running()
        panel.stop()
        panel.stop()
        _ = try await done()
        #expect(try await survivors(ofGroup: group).isEmpty)
    }

    func tearDown() {
        other.orderOut(nil)
        window.orderOut(nil)
        suite.remove()
        try? FileManager.default.removeItem(atPath: home)
    }

    /// A command that ignores SIGINT, prints `ready`, then for each line it reads prints and touches a file.
    ///
    /// The line `x` prints `got x` and touches `got-x` in the command's directory: a Stop leaves it alive,
    /// and the file shows it alive whether or not its output is drawn. The file follows the print, so by
    /// the command's Done the print has been read.
    static let held =
        "sh -c 'trap \"\" INT; echo ready; while read -r line; do echo \"got $line\"; touch \"got-$line\"; done'"
}

extension PanelTests {
    /// The ladder's six states, as ho-04.6's vocabulary names them, with Done also reached with a
    /// typed line (the table does not distinguish the two).
    internal enum Rung: String, Sendable, CustomTestStringConvertible {
        case clean = "Clean"
        case typed = "Typed"
        case inFlight = "In flight"
        case live = "Running, live"
        case stopped = "Running, stopped"
        case done = "Done"
        case doneTyped = "Done, typed"

        var testDescription: String { rawValue }

        /// A submission in flight or a command running: the states nothing may hide.
        var busy: Bool { [.inFlight, .live, .stopped].contains(self) }
    }
}

/// A panel shown, with the keyboard, in `rung`, and the opener of its launch task: held shut for
/// In flight, open for every other state.
///
/// Running states run `Fixture.held` at its readiness point; Running, stopped is reached with
/// `stop()`, the Stop button's call. Done is `echo shown; exit 3`.
@MainActor
private func reach(_ rung: PanelTests.Rung) async throws -> (fixture: Fixture, open: () -> Void) {
    let (launch, open) = gate()
    if rung != .inFlight { open() }
    let fixture = try Fixture(launch: launch)
    fixture.panel.show()
    switch rung {
    case .clean:
        break
    case .typed:
        fixture.window.input.stringValue = "typed line"
    case .inFlight:
        fixture.window.input.stringValue = Fixture.held
        fixture.panel.submit(fixture.window.input.stringValue)
        await Task.yield()
    case .live, .stopped:
        fixture.panel.submit(Fixture.held)
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        if rung == .stopped { fixture.panel.stop() }
    case .done, .doneTyped:
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        if rung == .doneTyped { fixture.window.input.stringValue = "typed line" }
    }
    return (fixture, open)
}

/// After an event that did nothing to a busy panel, the command is as it was: an In flight line still
/// starts; a live command still draws what it prints; a stopped one is still alive and still not drawn.
@MainActor
private func expectUntouched(_ rung: PanelTests.Rung, _ fixture: Fixture, opening open: () -> Void) async throws {
    switch rung {
    case .inFlight:
        #expect(fixture.panel.isBusy)
        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
    case .live:
        try await fixture.alive("after")
        try await fixture.transcriptContains("got after")
    case .stopped:
        let drawn = fixture.window.transcript.string
        try await fixture.alive("after")
        // At Done every chunk has been through the panel, the line's print among them.
        try await fixture.end(opening: open)
        #expect(fixture.window.transcript.string == drawn)
        return
    default:
        Issue.record("\(rung) is not busy")
    }
    try await fixture.end(opening: open)
}

/// Submits `line` while this process may create no process, so the start fails in forkpty before
/// Running, and restores the limit as soon as the panel has taken the failure.
///
/// The kernel lowers the hard limit to its per-user ceiling at the first set, so the soft limit goes
/// back under the hard limit as it then stands.
@MainActor
private func failStart(_ line: String, in fixture: Fixture) async throws {
    var limit = rlimit()
    try #require(getrlimit(RLIMIT_NPROC, &limit) == 0)
    var none = rlimit(rlim_cur: 1, rlim_max: limit.rlim_max)
    try #require(setrlimit(RLIMIT_NPROC, &none) == 0)
    defer {
        var now = rlimit()
        #expect(getrlimit(RLIMIT_NPROC, &now) == 0)
        var restored = rlimit(rlim_cur: min(limit.rlim_cur, now.rlim_max), rlim_max: now.rlim_max)
        #expect(setrlimit(RLIMIT_NPROC, &restored) == 0)
    }
    fixture.panel.submit(line)
    let deadline = ContinuousClock.now + .seconds(10)
    while fixture.panel.isBusy, ContinuousClock.now < deadline {
        await Task.yield()
    }
}

// Serialized and on the main actor: Panel is main-actor bound, and two Runs spawning at once
// intermittently fail forkpty (ho-02 Reflect).
@Suite("Panel", .serialized)
@MainActor
internal struct PanelTests {
    @Test("Clean: not busy; show focuses the input; Escape hides; the hotkey shows and hides")
    internal func clean() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        #expect(fixture.panel.state == nil)
        #expect(!fixture.panel.isBusy)
        fixture.panel.show()
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        fixture.panel.escape()
        #expect(fixture.look() == Look.clean.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == .clean)
        fixture.panel.toggle()
        #expect(fixture.look() == Look.clean.hidden)
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

    @Test("Running stays up through click-out and the hotkey; keys go to the transcript; Stop ends it and its group")
    internal func runningStaysUp() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("sleep 30")
        let pid = try await fixture.running()
        #expect(fixture.panel.isBusy)
        fixture.clickOut()
        #expect(fixture.window.isVisible)
        fixture.panel.toggle()
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
        #expect(!fixture.panel.isBusy)
        #expect(fixture.window.stopButton.isHidden)
        fixture.clickOut()
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

    @Test("A clear takes a showing offer with it; an empty line then starts nothing")
    internal func clearTakesOffer() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()
        fixture.panel.show()
        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        fixture.panel.escape()
        #expect(fixture.panel.state == nil)
        #expect(fixture.window.retryButton.isHidden)
        #expect(fixture.look() == .clean)
        fixture.panel.submit("")
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.panel.state == nil)
    }

    @Test("A clear then a hide: the next summons is Clean — no state, no transcript, no status, no buttons")
    internal func clearThenHide() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        try await fixture.transcriptContains("shown")
        #expect(!fixture.window.openButton.isHidden)

        fixture.panel.escape()
        #expect(fixture.window.isVisible)
        fixture.panel.escape()
        #expect(!fixture.window.isVisible)
        fixture.panel.toggle()
        #expect(fixture.look() == .clean)
        #expect(fixture.panel.state == nil)
        #expect(fixture.window.transcript.string.isEmpty)
        #expect(fixture.window.status.stringValue.isEmpty)
        #expect(fixture.window.retryButton.isHidden)
        #expect(fixture.window.openButton.isHidden)
    }

    @Test("The block cursor shows only while Running, not after a clear, and is never part of the transcript's text")
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
        fixture.panel.escape()
        #expect(fixture.panel.state == nil)
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

    @Test("A submission in flight stays up through the launch wait and while it runs; at Done a click-out hides it")
    internal func inFlightStaysUp() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        await Task.yield()
        fixture.panel.escape()
        fixture.panel.toggle()
        #expect(fixture.window.isVisible)
        #expect(fixture.window.isKeyWindow)
        fixture.clickOut()
        #expect(fixture.window.isVisible)
        #expect(fixture.panel.isBusy)
        #expect(fixture.panel.state == nil)

        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(fixture.panel.isBusy)
        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
        #expect(!fixture.panel.isBusy)
        fixture.panel.toggle()
        fixture.clickOut()
        #expect(!fixture.window.isVisible)
    }

    @Test("A click-out or the hotkey after start but before Running arrives leaves the panel up (ho-03x run 2)")
    internal func hideBeforeRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("sleep 30")
        await Task.yield()
        // Held, the main actor lets Run start the command without delivering Running.
        usleep(50_000)
        fixture.panel.toggle()
        #expect(fixture.window.isVisible)
        fixture.clickOut()
        #expect(fixture.window.isVisible)

        let pid = try await fixture.running()
        fixture.panel.stop()
        guard case .done(.signal, _) = try await fixture.done() else {
            Issue.record("not ended by a signal: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(try await survivors(ofGroup: pid).isEmpty)
        #expect(!fixture.panel.isBusy)
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

    @Test("Every chunk is drawn before Done, and none reaches the panel after a clear")
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

        fixture.panel.escape()
        #expect(fixture.look() == .clean)
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

    @Test("Clean is the bar alone; the output card shows from Running with Copy and goes at a clear")
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
        fixture.panel.escape()
        #expect(fixture.window.isVisible)
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

    @Test("Escape route: with no command running, Escape pressed in the transcript reaches the ladder — Done clears")
    internal func escapeInTranscript() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let window = fixture.window
        #expect(window.makeFirstResponder(window.transcript))
        window.transcript.keyDown(with: try key("\u{1B}", code: UInt16(kVK_Escape), in: window))
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
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

    @Test("The transcript follows the end only when the end was in view")
    internal func scrollFollowsEnd() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let transcript = fixture.window.transcript
        transcript.append(Array((1...300).map { "row \($0)\n" }.joined().utf8))
        fixture.window.fit()
        #expect(transcript.atCap)
        #expect(transcript.bounds.height > transcript.visibleRect.height)

        transcript.scroll(.zero)
        let top = transcript.visibleRect
        #expect(top.minY == 0)
        transcript.append(Array("more\n".utf8))
        #expect(transcript.visibleRect == top)

        transcript.scrollToEndOfDocument(nil)
        transcript.append(Array("last\n".utf8))
        #expect(transcript.visibleRect.maxY == transcript.bounds.maxY)
        #expect(transcript.visibleRect.minY > 0)

        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
    }

    @Test("Command-C through the window while Running copies the transcript so far")
    internal func commandCWhileRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        guard case .running = fixture.panel.state else {
            Issue.record("not Running at the readiness point: \(String(describing: fixture.panel.state))")
            return
        }
        let window = fixture.window
        #expect(window.firstResponder === window.transcript)
        NSPasteboard.general.clearContents()
        #expect(window.performKeyEquivalent(with: try key("c", code: 8, modifiers: .command, in: window)))
        #expect(NSPasteboard.general.string(forType: .string) == "ready\n")

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
    }

    @Test("A selection the line ceiling evicts through still describes storage that exists, and copies it")
    internal func selectionAcrossEviction() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        let transcript = fixture.window.transcript
        transcript.append(Array((0..<10_000).map { "line \($0)\n" }.joined().utf8))
        let text = transcript.string as NSString
        let from = text.range(of: "line 5990\n").location
        let through = NSMaxRange(text.range(of: "line 6009\n"))
        transcript.setSelectedRange(NSRange(location: from, length: through - from))

        transcript.append(Array((10_000..<16_000).map { "line \($0)\n" }.joined().utf8))
        #expect(transcript.string.hasPrefix("line 6000\n"))
        let storage = try #require(transcript.textStorage)
        for range in transcript.selectedRanges.map(\.rangeValue) {
            #expect(NSMaxRange(range) <= storage.length)
        }
        NSPasteboard.general.clearContents()
        transcript.copy(nil)
        let copied = try #require(NSPasteboard.general.string(forType: .string))
        #expect(!copied.isEmpty)
        #expect(transcript.string.contains(copied))
    }
}

// The Escape ladder and the click-out rule (ho-04.6): every reachable cell of the table, one test per
// column and result, the state as the parameter. A cell that says "nothing" reads the panel before and
// after, then shows the command untouched.
extension PanelTests {
    @Test("Escape × Clean: hide")
    internal func escapeHidesClean() async throws {
        let (fixture, _) = try await reach(.clean)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.panel.escape()
        #expect(fixture.look() == before.hidden)
    }

    @Test("Escape × Typed, Done: clear", arguments: [Rung.typed, .done, .doneTyped])
    internal func escapeClears(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        #expect(fixture.look() != .clean)
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        #expect(fixture.window.outputCard.isHidden)
    }

    @Test("Escape × In flight: nothing")
    internal func escapeInFlight() async throws {
        let (fixture, open) = try await reach(.inFlight)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.panel.escape()
        #expect(fixture.look() == before)
        try await expectUntouched(.inFlight, fixture, opening: open)
    }

    @Test("Escape × Running, live: stop — the group is interrupted, the Stop count advances, nothing more is drawn")
    internal func escapeStops() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        let pid = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.escape()
        #expect(fixture.window.isVisible)
        guard case .done(.signal(SIGINT), _) = try await fixture.done() else {
            Issue.record("not ended by SIGINT: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(try await survivors(ofGroup: pid).isEmpty)

        // The same counter and flag as Stop: after Escape, Stop kills, and what the command printed
        // meanwhile was not drawn.
        fixture.panel.submit(Fixture.held)
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let drawn = fixture.window.transcript.string
        fixture.panel.escape()
        try await fixture.alive("a")
        fixture.panel.stop()
        #expect(try await fixture.done() == .done(.signal(SIGKILL), retry: nil))
        #expect(fixture.window.transcript.string == drawn)
    }

    @Test("Click-out × Clean, Typed, Done: hide, keeping everything", arguments: [Rung.clean, .typed, .done])
    internal func clickOutHides(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.clickOut()
        #expect(fixture.look() == before.hidden)
    }

    @Test(
        "Click-out × In flight, Running live, Running stopped: nothing; the panel stays",
        arguments: [Rung.inFlight, .live, .stopped])
    internal func clickOutStays(rung: Rung) async throws {
        let (fixture, open) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.clickOut()
        #expect(fixture.look() == before.withoutKeyboard)
        try await expectUntouched(rung, fixture, opening: open)
    }

    @Test("Hotkey, hidden × Clean, Typed, Done: show, as it was", arguments: [Rung.clean, .typed, .done])
    internal func hotkeyShows(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.clickOut()
        #expect(!fixture.window.isVisible)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(fixture.keyboardInInput)
    }

    @Test(
        "Hotkey, visible without the keyboard × every state: take the keyboard",
        arguments: [Rung.clean, .typed, .inFlight, .live, .stopped, .done])
    internal func hotkeyTakesKeyboard(rung: Rung) async throws {
        let (fixture, open) = try await reach(rung)
        defer { fixture.tearDown() }
        fixture.loseKeyboard()
        let before = fixture.look()
        #expect(before.visible && !before.key)
        fixture.panel.toggle()
        #expect(fixture.look() == before.withKeyboard)
        if rung.busy {
            try await expectUntouched(rung, fixture, opening: open)
        }
    }

    @Test(
        "Hotkey, visible with the keyboard × Clean, Typed, Done: hide, keeping everything",
        arguments: [Rung.clean, .typed, .done])
    internal func hotkeyHides(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.panel.toggle()
        #expect(fixture.look() == before.hidden)
    }

    @Test(
        "Hotkey, visible with the keyboard × In flight, Running live, Running stopped: nothing",
        arguments: [Rung.inFlight, .live, .stopped])
    internal func hotkeyStays(rung: Rung) async throws {
        let (fixture, open) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        #expect(before.visible && before.key)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        try await expectUntouched(rung, fixture, opening: open)
    }
}

// The race of Escape in Running, stopped against Done, and the invariants ho-04.6 tests on their own.
extension PanelTests {
    @Test("Escape × Running, stopped, the command alive: clear, killing it; its Done lands on nothing")
    internal func escapeClearsKilling() async throws {
        let (fixture, _) = try await reach(.live)
        defer { fixture.tearDown() }
        guard case .running(let pid) = fixture.panel.state else { throw TimedOut() }
        fixture.panel.escape()
        try await fixture.alive("a")
        #expect(fixture.panel.state == .running(pid: pid))
        fixture.panel.escape()
        #expect(fixture.panel.awaitsClearedDone)
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        #expect(!fixture.window.transcript.showsCursor)
        #expect(try await survivors(ofGroup: pid).isEmpty)

        // The killed command's Done has reached the panel once it is no longer awaited; the panel is
        // read after that, so a Done applied there would be seen, not overwritten unseen.
        try await fixture.until { !fixture.panel.awaitsClearedDone }
        #expect(fixture.look() == .clean)
        #expect(fixture.window.outputCard.isHidden)
        #expect(fixture.keyboardInInput)

        // Nothing of it reaches the next command either.
        fixture.panel.escape()
        #expect(fixture.look() == Look.clean.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == .clean)
        fixture.panel.submit("echo after")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == "after\n")
        #expect(fixture.window.status.stringValue == "exit 0")
    }

    @Test("Escape × Running, stopped, Done landing first: the second Escape finds Done and clears")
    internal func escapeClearsAfterDone() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        let pid = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.escape()
        guard case .done(.signal, _) = try await fixture.done() else {
            Issue.record("not ended by a signal: \(String(describing: fixture.panel.state))")
            return
        }
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        #expect(try await survivors(ofGroup: pid).isEmpty)
    }

    // ho-02's ruling (2026-10-26), which the practitioner kept for the panel on 2026-11-05 (ho-04.6.1):
    // once the leader exits, the kernel's hang-up on the closing terminal is what reaches the rest of
    // the group, as a closed terminal window's does. A job that ignores it outlives the panel, and
    // nothing is built for it. The test records that, then kills the group itself.
    @Test("A job that ignores the hang-up outlives its leader's Done, a clear and a hide (ho-02's ruling, ho-04.6.1)")
    internal func survivorOfHangUp() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        var group: pid_t?
        // Cleanup only: the group is killed here if the test ends early with members left.
        defer {
            if let group, (try? ps(["-o", "pid=", "-g", "\(group)"]))?.isEmpty == false { killpg(group, SIGKILL) }
        }
        fixture.panel.show()
        fixture.panel.submit("sh -c 'trap \"\" HUP INT; echo ready; sleep 30' & wait")
        let pid = try await fixture.running()
        group = pid
        try await fixture.transcriptContains("ready")
        fixture.panel.escape()
        guard case .done = try await fixture.done() else { throw TimedOut() }
        // The leader is gone and the job is not; its sleep may still be starting, so later reads keep
        // every pid this one lists.
        let members = Set(try ps(["-o", "pid=", "-g", "\(pid)"]).split(whereSeparator: \.isNewline))
        #expect(try ps(["-o", "pid=", "-p", "\(pid)"]).isEmpty)
        #expect(!members.isEmpty)

        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        fixture.panel.escape()
        #expect(fixture.look() == Look.clean.hidden)
        #expect(members.isSubset(of: try ps(["-o", "pid=", "-g", "\(pid)"]).split(whereSeparator: \.isNewline)))

        killpg(pid, SIGKILL)
        #expect(try await survivors(ofGroup: pid).isEmpty)
    }

    @Test("Invariant 2: a start that fails before Running keeps its reason through a hide and a show")
    internal func failedStartKept() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let window = fixture.window
        fixture.panel.show()
        window.input.stringValue = "echo never"
        try await failStart(window.input.stringValue, in: fixture)
        #expect(!fixture.panel.isBusy)
        let before = fixture.look()
        #expect(before.state == nil && before.input == "echo never")
        #expect(before.status.hasPrefix("Could not start: "))
        #expect(same(window.status.textColor, Theme.Token.alarm))
        #expect(!window.outputCard.isHidden)

        fixture.clickOut()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(same(window.status.textColor, Theme.Token.alarm))
        #expect(!window.outputCard.isHidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(same(window.status.textColor, Theme.Token.alarm))
        #expect(!window.outputCard.isHidden)

        // The next submission and its Running end the reason.
        fixture.panel.submit("echo after")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.status.stringValue == "exit 0")
        #expect(same(window.status.textColor, Theme.Token.inkFaint))

        // So does a clear.
        window.input.stringValue = "echo never"
        try await failStart(window.input.stringValue, in: fixture)
        #expect(window.status.stringValue.hasPrefix("Could not start: "))
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(window.outputCard.isHidden)
    }

    @Test("Invariant 1: in flight, live and stopped, neither click-out nor the hotkey hides the panel")
    internal func nothingAliveHidden() async throws {
        let (fixture, open) = try await reach(.inFlight)
        defer { fixture.tearDown() }
        func attempt() {
            fixture.clickOut()
            #expect(fixture.window.isVisible)
            fixture.panel.toggle()
            #expect(fixture.window.isVisible)
            #expect(fixture.window.isKeyWindow)
            fixture.panel.toggle()
            #expect(fixture.window.isVisible)
        }
        attempt()
        #expect(fixture.panel.state == nil && fixture.panel.isBusy)
        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        attempt()
        fixture.panel.stop()
        attempt()
        guard case .running = fixture.panel.state else { throw TimedOut() }
        try await fixture.end(opening: open)
    }

    @Test("Invariant 2: a Done panel with an offer and a typed line, hidden and shown, is as it was")
    internal func hidingLosesNothing() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()
        fixture.panel.show()
        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        fixture.window.input.stringValue = "typed line"
        let before = fixture.look()
        #expect(before.offer && !before.transcript.isEmpty && !before.status.isEmpty)

        fixture.clickOut()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        fixture.panel.toggle()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(fixture.keyboardInInput)
    }

    @Test("Invariant 4: clear a live command, submit a new line at once, and it reaches Running")
    internal func submitAfterClear() async throws {
        let (fixture, _) = try await reach(.live)
        defer { fixture.tearDown() }
        guard case .running(let cleared) = fixture.panel.state else { throw TimedOut() }
        fixture.panel.escape()
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        fixture.window.input.stringValue = "echo next; read -r line"
        fixture.panel.submit(fixture.window.input.stringValue)
        let next = try await fixture.running()
        #expect(next != cleared)
        try await fixture.transcriptContains("next")
        #expect(fixture.window.status.stringValue == "running")
        #expect(try await survivors(ofGroup: cleared).isEmpty)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        // The terminal echoes the carriage return as an empty line; nothing of the cleared command is there.
        #expect(fixture.window.transcript.string == "next\n\n")
    }

    @Test("Invariant 5: Escape never reaches the command; a line read after it has length zero")
    internal func escapeNeverWritten() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        // The command ignores the interrupt Escape sends, and writes the length where the panel, now
        // stopped, does not draw.
        fixture.panel.submit("sh -c 'trap \"\" INT; echo ready; read -r secret; printf %s \"${#secret}\" > length'")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let window = fixture.window
        #expect(window.firstResponder === window.transcript)
        window.transcript.keyDown(with: try key("\u{1B}", code: UInt16(kVK_Escape), in: window))
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(try String(contentsOfFile: fixture.home + "/length", encoding: .utf8) == "0")
    }
}

// Every route by which AppKit delivers Escape reaches `Panel.escape()`; the fourth, the transcript
// when no command runs, is `escapeInTranscript` above.
extension PanelTests {
    @Test("Escape route: the input's field editor, Clean: hides")
    internal func escapeInInput() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        let editor = try #require(fixture.window.input.currentEditor())
        editor.keyDown(with: try key("\u{1B}", code: UInt16(kVK_Escape), in: fixture.window))
        #expect(fixture.look() == Look.clean.hidden)
    }

    @Test("Escape route: the transcript while Running: stops")
    internal func escapeInTranscriptRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        let pid = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let window = fixture.window
        #expect(window.firstResponder === window.transcript)
        window.transcript.keyDown(with: try key("\u{1B}", code: UInt16(kVK_Escape), in: window))
        guard case .done(.signal(SIGINT), _) = try await fixture.done() else {
            Issue.record("not ended by SIGINT: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(window.isVisible)
        #expect(try await survivors(ofGroup: pid).isEmpty)
    }

    @Test("Escape route: the window's cancelOperation with no text responder, Clean: hides")
    internal func escapeInWindow() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        #expect(fixture.window.makeFirstResponder(nil))
        #expect(fixture.window.firstResponder === fixture.window)
        fixture.window.cancelOperation(nil)
        #expect(fixture.look() == Look.clean.hidden)
    }
}

/// Delivers a key-down as AppKit does: the window's key equivalents first, then the first responder.
@MainActor
private func press(_ event: NSEvent, in window: NSWindow) {
    if !window.performKeyEquivalent(with: event) { window.firstResponder?.keyDown(with: event) }
}

/// Command and a digit, 1 through 9, as the keyboard sends it.
@MainActor
private func commandDigit(_ digit: Int, in window: NSWindow) throws -> NSEvent {
    let codes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]
    return try key("\(digit)", code: UInt16(codes[digit - 1]), modifiers: .command, in: window)
}

// Settings read at use (ho-05.1): the directory at Return, the macros at Command-N, the terminal at Open
// in Terminal; Refresh Environment; the hotkey's notice.
extension PanelTests {
    @Test("The fixed folder is read at Return: a change between two commands moves the second")
    internal func directoryReadAtReturn() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let first = fixture.home + "/first-" + UUID().uuidString
        let second = fixture.home + "/second-" + UUID().uuidString
        for folder in [first, second] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        }
        fixture.settings.directoryPath = first
        fixture.panel.submit("pwd")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        // `pwd` prints the physical path; the temporary directory sits behind a symbolic link.
        #expect(fixture.window.transcript.string.hasSuffix("/" + URL(fileURLWithPath: first).lastPathComponent + "\n"))
        #expect(fixture.window.status.stringValue == "exit 0")

        fixture.settings.directoryPath = second
        fixture.panel.submit("pwd")
        try await fixture.until { fixture.window.transcript.string.contains("second-") }
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string.hasSuffix("/" + URL(fileURLWithPath: second).lastPathComponent + "\n"))

        fixture.settings.directoryMode = .home
        fixture.panel.submit("pwd")
        try await fixture.until { !fixture.window.transcript.string.contains("second-") }
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == FileManager.default.homeDirectoryForCurrentUser.path + "\n")
    }

    @Test(
        "A fixed folder that is gone: the command runs in home, the strip says so from Running to Done, the next checks again"
    )
    internal func missingFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let folder = fixture.home + "/gone-" + UUID().uuidString
        fixture.settings.directoryPath = folder
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line; pwd")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let said = "\(folder) could not be found; ran in home"
        #expect(window.status.stringValue.hasPrefix(said))
        #expect(same(window.status.textColor, Theme.Token.alarm))

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(window.transcript.string.hasSuffix("\n" + home + "\n"))
        #expect(window.status.stringValue == said + " · exit 0")
        #expect(same(window.status.textColor, Theme.Token.alarm))
        fixture.clickOut()
        fixture.panel.toggle()
        #expect(window.status.stringValue == said + " · exit 0")

        // The folder back: the next command finds it, and the strip is the command's own.
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        fixture.panel.submit("pwd")
        try await fixture.until { window.transcript.string.contains("gone-") }
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.transcript.string.hasSuffix("/" + URL(fileURLWithPath: folder).lastPathComponent + "\n"))
        #expect(window.status.stringValue == "exit 0")
        #expect(same(window.status.textColor, Theme.Token.inkFaint))
    }

    @Test("A fixed folder that is a file, not a folder, is gone too")
    internal func folderIsAFile() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let file = fixture.home + "/a-file"
        try "".write(toFile: file, atomically: true, encoding: .utf8)
        fixture.settings.directoryPath = file
        fixture.panel.submit("pwd")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == FileManager.default.homeDirectoryForCurrentUser.path + "\n")
        #expect(fixture.window.status.stringValue.hasPrefix("\(file) could not be found"))
    }

    @Test("Command-1 in Composing loads slot 1 into the input, the cursor at its end, and runs nothing")
    internal func macroLoads() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let command = "touch macro-ran; echo macro"
        fixture.settings.macros = [Macro(name: "first", command: command)]
        let window = fixture.window
        fixture.panel.show()
        let before = fixture.look()
        press(try commandDigit(1, in: window), in: window)
        #expect(window.input.stringValue == command)
        let editor = try #require(window.input.currentEditor())
        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange == NSRange(location: (command as NSString).length, length: 0))
        let after = fixture.look()
        #expect(after.input == command)
        #expect(after.with(input: before.input) == before)
        #expect(fixture.panel.state == nil)
        #expect(!fixture.panel.isBusy)
        #expect(window.outputCard.isHidden)
        #expect(try await children().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/macro-ran"))
    }

    @Test(
        "Command-N replaces typed text; an empty slot leaves the input as it was; a slot changed in settings loads the change"
    )
    internal func macroReplaces() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        var macros = fixture.settings.macros
        macros[2] = Macro(name: "", command: "uptime")
        fixture.settings.macros = macros
        let window = fixture.window
        fixture.panel.show()
        window.input.stringValue = "typed line"
        press(try commandDigit(3, in: window), in: window)
        #expect(window.input.stringValue == "uptime")
        press(try commandDigit(2, in: window), in: window)
        #expect(window.input.stringValue == "uptime")
        press(try commandDigit(9, in: window), in: window)
        #expect(window.input.stringValue == "uptime")

        macros[2] = Macro(name: "", command: "df -h")
        fixture.settings.macros = macros
        press(try commandDigit(3, in: window), in: window)
        #expect(window.input.stringValue == "df -h")
        #expect(fixture.panel.state == nil)
    }

    @Test("In Done, Command-1 loads and changes nothing else; Return then runs the macro's command")
    internal func macroInDone() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.macros = [Macro(name: "", command: "echo from-the-macro")]
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        let before = fixture.look()
        press(try commandDigit(1, in: window), in: window)
        let after = fixture.look()
        #expect(after.input == "echo from-the-macro")
        #expect(after.with(input: before.input) == before)

        let editor = try #require(window.input.currentEditor())
        editor.keyDown(with: try key("\r", code: UInt16(kVK_Return), in: window))
        try await fixture.transcriptContains("from-the-macro")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.transcript.string == "from-the-macro\n")
    }

    @Test("While Running, Command-1 changes nothing and the command reads nothing")
    internal func macroWhileRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.macros = [Macro(name: "", command: "echo never")]
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r secret; printf %s \"${#secret}\" > length")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(window.firstResponder === window.transcript)
        let before = fixture.look()
        press(try commandDigit(1, in: window), in: window)
        #expect(fixture.look() == before)
        #expect(window.input.stringValue.isEmpty)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(try String(contentsOfFile: fixture.home + "/length", encoding: .utf8) == "0")
        #expect(window.input.stringValue.isEmpty)
    }

    @Test(
        "Open in Terminal with a terminal that is not installed: the strip says so through hide and show, until the next submission or a clear"
    )
    internal func terminalMissing() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.terminal = "org.example.no-such-terminal"
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(!window.openButton.isHidden)
        // The button's own action, sent as a click sends it: `performClick` spins the run loop for its
        // highlight, and the next await then found the main run loop ended and the test process exited 0.
        #expect(window.openButton.sendAction(window.openButton.action, to: window.openButton.target))
        let said = "org.example.no-such-terminal could not be found."
        #expect(window.status.stringValue == said)
        #expect(same(window.status.textColor, Theme.Token.alarm))
        let before = fixture.look()
        fixture.clickOut()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(same(window.status.textColor, Theme.Token.alarm))

        // The next submission takes it away.
        fixture.panel.submit("echo again")
        try await fixture.transcriptContains("again")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.status.stringValue == "exit 0")
        #expect(same(window.status.textColor, Theme.Token.inkFaint))

        // So does a clear.
        fixture.panel.openInTerminal()
        #expect(window.status.stringValue == said)
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(window.status.stringValue.isEmpty)
    }

    @Test("Refresh Environment through the panel: a failing capture puts the notice line on the panel")
    internal func refreshFails() async throws {
        let fixture = try Fixture(failingCapture: true)
        defer { fixture.tearDown() }
        #expect(fixture.window.notice.isHidden)
        fixture.panel.refreshEnvironment()
        let line = "Login environment not captured (shell exited 3); using the app's own environment."
        try await fixture.until { fixture.window.notice.stringValue == line }
        #expect(!fixture.window.notice.isHidden)
    }

    @Test("The hotkey's notice and the settings line name the registered combination, not a constant")
    internal func hotkeyNamed() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let combination = Shortcut.Combination(
            keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey | cmdKey))
        #expect(Hotkey.register(keyCode: combination.keyCode, modifiers: combination.modifiers) {} == noErr)
        defer { Hotkey.unregister() }
        #expect(Hotkey.settingsLine(launch: noErr, attempted: Settings.defaultShortcut) == "⌃⌥⌘J is registered.")

        let status = Hotkey.replace(keyCode: combination.keyCode, modifiers: combination.modifiers)
        let notice = try #require(Hotkey.statusText(for: status, combination: combination))
        fixture.panel.note(notice)
        #expect(fixture.window.notice.stringValue.hasPrefix("⌃⌥⌘J is unavailable (\(eventHotKeyExistsErr))."))
        #expect(!fixture.window.notice.stringValue.contains("Space"))

        // Nothing registered: settings says why the launch's failed, naming what it tried.
        Hotkey.unregister()
        #expect(
            Hotkey.settingsLine(launch: status, attempted: combination)
                == Hotkey.statusText(for: status, combination: combination))
    }
}
