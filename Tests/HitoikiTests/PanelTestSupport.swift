import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import HitoikiCore
import Testing

@testable import Hitoiki

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

/// The test process's living children, less the `ps` that lists them, read until none remain or two
/// seconds pass.
internal func children() async throws -> [String] {
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
internal func same(_ color: NSColor?, _ token: Palette) -> Bool {
    color?.usingColorSpace(.sRGB) == token.nsColor.usingColorSpace(.sRGB)
}

/// The general pasteboard's items, to put back after a test that writes it.
@MainActor
internal func savePasteboard() -> [[(NSPasteboard.PasteboardType, Data)]] {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
    }
}

@MainActor
internal func restorePasteboard(_ saved: [[(NSPasteboard.PasteboardType, Data)]]) {
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
internal func key(
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

/// A condition the test waited ten seconds for: where in the test file the wait was asked for, and what it
/// waited for, so a timeout in the log can be read without running the test again.
internal struct TimedOut: Error, CustomStringConvertible {
    let waitingFor: String
    let location: SourceLocation

    init(_ waitingFor: String = "the condition written there", at location: SourceLocation = #_sourceLocation) {
        self.waitingFor = waitingFor
        self.location = location
    }

    var description: String { "TimedOut at \(location) waiting for \(waitingFor)" }
}

/// The panel as the tests read it: visibility, key status, `state`, transcript text, status text, the
/// offer, and the input's text.
internal struct Look: Equatable {
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
internal func gate() -> (launch: Task<Void, any Error>, open: () -> Void) {
    let (opened, opener) = AsyncStream<Void>.makeStream()
    return (Task { for await _ in opened {} }, { opener.finish() })
}

/// A Panel over a real Run, a real window, a store over a throwaway suite and a history in a folder of the
/// test's, its commands starting in a directory the test owns: the store's fixed folder.
@MainActor
internal struct Fixture {
    let home: String
    let panel: Panel
    let window: PanelWindow
    let suite: ThrowawaySuite
    let settings: Settings
    /// The history's folder, inside the test's directory: no test reaches the app's own.
    let historyFolder: URL
    let history: History
    /// Another window, in this app, for a click-out to give the keyboard to.
    let other = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
        styleMask: [.titled, .nonactivatingPanel],
        backing: .buffered,
        defer: false)

    /// `homeOnPath` makes the test's directory the whole `PATH`, for a fake `ssh`.
    init(homeOnPath: Bool = false, launch: Task<Void, any Error> = Task {}) throws {
        home = try makeDirectory()
        window = PanelWindow()
        suite = try ThrowawaySuite()
        let settings = Settings(defaults: suite.defaults)
        self.settings = settings
        settings.directoryMode = .fixed
        settings.directoryPath = home
        historyFolder = URL(fileURLWithPath: home).appending(path: "history-folder")
        history = History(folder: historyFolder) { settings.historyEnabled }
        let environment = homeOnPath ? ownedEnvironment(home: home, path: home) : ownedEnvironment(home: home)
        panel = Panel(
            run: Run(environment: environment),
            launch: launch,
            window: window,
            settings: settings,
            history: history)
    }

    /// The history file's text.
    func historyText() throws -> String {
        try String(contentsOf: historyFolder.appending(path: "history.txt"), encoding: .utf8)
    }

    /// Submits `line` and waits until its command has ended, or its start has failed.
    func ran(_ line: String, at location: SourceLocation = #_sourceLocation) async throws {
        panel.submit(line)
        try await until("\"\(line)\" to end or fail to start", at: location) { !panel.isBusy }
    }

    /// Waits, between main-actor jobs, until `condition` holds; after ten seconds it throws, naming the line
    /// that asked and `waitingFor`.
    ///
    /// The helpers below pass their caller's line on, so a timeout names the test's line, not this file's.
    func until(
        _ waitingFor: String = "the condition written there",
        at location: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw TimedOut(waitingFor, at: location) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// The pid of the running command, once Panel shows it running.
    func running(at location: SourceLocation = #_sourceLocation) async throws -> pid_t {
        try await until("Running", at: location) {
            if case .running = panel.state { return true }
            return false
        }
        guard case .running(let pid) = panel.state else { throw TimedOut("Running", at: location) }
        return pid
    }

    func done(at location: SourceLocation = #_sourceLocation) async throws -> RunState? {
        try await until("Done", at: location) {
            if case .done = panel.state { return true }
            return false
        }
        return panel.state
    }

    func transcriptContains(_ text: String, at location: SourceLocation = #_sourceLocation) async throws {
        try await until("the transcript to contain \"\(text)\"", at: location) {
            window.transcript.string.contains(text)
        }
    }

    /// An `ssh` in the test's directory: sudo's refusal on stderr and status 1, unless its first argument
    /// is `-tt`, then `ok`, and status 0 once it reads a line.
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
    func alive(_ tag: String, at location: SourceLocation = #_sourceLocation) async throws {
        panel.keystroke(.write(Array("\(tag)\r".utf8)))
        try await until("the file got-\(tag)", at: location) {
            FileManager.default.fileExists(atPath: home + "/got-" + tag)
        }
    }

    /// Opens the launch, and if a command runs or is in flight, kills it, waits for its Done and
    /// checks that its group is gone.
    func end(opening open: () -> Void, at location: SourceLocation = #_sourceLocation) async throws {
        open()
        guard panel.isBusy else { return }
        let group = try await running(at: location)
        panel.stop()
        panel.stop()
        _ = try await done(at: location)
        #expect(try await survivors(ofGroup: group).isEmpty)
    }

    func tearDown() {
        other.orderOut(nil)
        window.recall.withdraw()
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
    /// The Escape ladder's six states, with Done also reached with a typed line (the ladder's table does
    /// not distinguish the two).
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
internal func reach(
    _ rung: PanelTests.Rung, at location: SourceLocation = #_sourceLocation
) async throws -> (fixture: Fixture, open: () -> Void) {
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
        _ = try await fixture.running(at: location)
        try await fixture.transcriptContains("ready", at: location)
        if rung == .stopped { fixture.panel.stop() }
    case .done, .doneTyped:
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done(at: location) == .done(.status(3), retry: nil))
        if rung == .doneTyped { fixture.window.input.stringValue = "typed line" }
    }
    return (fixture, open)
}

/// Submits `line` while this process may create no process, so the start fails in forkpty before
/// Running, and restores the limit as soon as the panel has taken the failure.
///
/// The kernel lowers the hard limit to its per-user ceiling at the first set, so the soft limit goes
/// back under the hard limit as it then stands.
@MainActor
internal func failStart(_ line: String, in fixture: Fixture) async throws {
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

/// Delivers a key-down as AppKit does: the window's key equivalents first, then the first responder.
@MainActor
internal func press(_ event: NSEvent, in window: NSWindow) {
    if !window.performKeyEquivalent(with: event) { window.firstResponder?.keyDown(with: event) }
}

/// A digit, 1 through 9, as the keyboard sends it: with Command alone unless `modifiers` says otherwise.
@MainActor
internal func commandDigit(
    _ digit: Int, with modifiers: NSEvent.ModifierFlags = .command, in window: NSWindow
) throws -> NSEvent {
    let codes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]
    return try key("\(digit)", code: UInt16(codes[digit - 1]), modifiers: modifiers, in: window)
}
