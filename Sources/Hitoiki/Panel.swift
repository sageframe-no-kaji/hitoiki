import AppKit
import HitoikiCore

/// The controller behind the only visible surface: the last state Run reported, the three moves —
/// hide, show, clear — and the Escape ladder, and what each control and each key does to the Run.
///
/// The ladder's six states are read, where an event arrives, from facts held here and in the window:
/// `state`, `stopped`, `submission`, the input's text, and the window's visibility and key status. Recall,
/// the list under the input and the grey suggestion, is in the extension at the end.
@MainActor
internal final class Panel {
    /// The last state Run reported, or nil before the first command and after a clear.
    ///
    /// Nil is Composing, `.running` is Running, `.done` is Done.
    internal private(set) var state: RunState?

    private let run: Run
    private let launch: Task<Void, any Error>
    private let window: PanelWindow
    /// Read at use: the directory at Return, the terminal at Open in Terminal, a macro at Command-N.
    private let settings: Settings
    /// What ran, kept at each Running, and read at each recall.
    private let history: History
    /// Stops since the command started: the first interrupts, every later one kills.
    private var stops = 0
    /// Set by Stop, Control-C or Escape until the next command starts: the output is still taken from
    /// Run, so Done arrives, but no more of it is drawn (practitioner's ruling, ho-04 run sheet, item 8).
    private var stopped = false
    /// The submission from Return until Running arrives or the start fails; until then nothing hides
    /// the panel, so nothing starts hidden.
    private var submission: Task<Void, Never>?
    /// Starts waiting for the Done of a command a clear killed: non-nil from that clear until the Done
    /// arrives, which Run sends before it can start another.
    private var cleared: [CheckedContinuation<Void, Never>]?
    /// Why the last start failed before Running, shown on the strip until the next submission, the next
    /// Running or a clear; `apply` derives the strip from it, so a hide and a show keep it.
    private var failedStart: String?
    /// Where the submission in flight starts, and the fixed folder it could not find; the command's own
    /// from its Running.
    private var starting: (directory: String, missing: String?)?
    /// The line the submission in flight hands to Run: kept in the history at its Running, and at no other
    /// moment.
    private var startingLine: String?
    /// The directory the shown command ran in: Open in Terminal opens it.
    private var ranIn: String?
    /// The fixed folder the shown command could not find, said on the strip from its Running until the
    /// next command's Running or a clear.
    private var missingFolder: String?
    /// Why Open in Terminal opened nothing, shown on the strip until the next submission or a clear; held
    /// beside `failedStart`, so a hide and a show keep it.
    private var terminalFailure: String?
    private var notices: [String] = []

    /// The rest of the newest entry that starts with the input's last line, drawn in grey after the cursor
    /// and never part of the input's value; nil when none is shown.
    internal private(set) var suggestion: String?

    /// Opens a page in the browser: the site, from the update line.
    ///
    /// A test stands a recorder in its place, so the URL is witnessed and nothing opens.
    internal var openURL: @MainActor (URL) -> Void = { url in _ = NSWorkspace.shared.open(url) }

    /// True while a command runs or a start is in flight: nothing hides the panel, and Quit kills.
    internal var isBusy: Bool {
        if case .running = state { return true }
        return submission != nil
    }

    /// True from a clear that killed a running command until that command's Done has reached the panel
    /// and changed nothing on it.
    internal var awaitsClearedDone: Bool { cleared != nil }

    /// Drives `run` through `window` for the app's life.
    ///
    /// - Parameters:
    ///   - run: The app's one Run.
    ///   - launch: The capture of the login environment; the first command waits for it.
    ///   - window: The panel this controller shows, hides and fills.
    ///   - settings: The store, read at the moment each setting is used.
    ///   - history: What ran, written at each Running and read at each recall; its notices go on the notice.
    internal init(run: Run, launch: Task<Void, any Error>, window: PanelWindow, settings: Settings, history: History) {
        self.run = run
        self.launch = launch
        self.window = window
        self.settings = settings
        self.history = history
        window.panel = self
        window.transcript.panel = self
        window.recall.panel = self
        history.report = { [weak self] line in self?.note(line) }
        // Run's streams are single-consumer and end only when Run is released; these tasks hold
        // neither Run nor Panel, so both end with Panel.
        let bytes = run.bytes
        let states = run.states
        Task { [weak self] in
            for await chunk in bytes {
                guard let self, !self.stopped else { continue }
                self.window.transcript.append(chunk)
                // At the cap a chunk cannot change the panel's height.
                if !self.window.transcript.atCap { self.window.fit() }
            }
        }
        Task { [weak self] in
            for await next in states {
                self?.enter(next)
            }
        }
        Task { [weak self] in
            do {
                try await launch.value
            } catch {
                self?.note("Login environment not captured (\(Self.reason(error))); using the app's own environment.")
            }
        }
        apply()
    }

    /// Places the panel on the mouse's screen if it is hidden, brings it forward and gives it the keyboard.
    internal func show() {
        if !window.isVisible { window.place() }
        window.makeKeyAndOrderFront(nil)
        apply()
    }

    /// Takes the panel off screen and keeps everything on it, unless a command runs or a start is in
    /// flight; the next summons shows it as it was.
    ///
    /// The click-out comes here; so do Escape on a clean panel and the hotkey on a panel with the keyboard.
    /// The recall list closes and the suggestion goes with it.
    internal func hide() {
        guard !isBusy else { return }
        closeList()
        setSuggestion(nil)
        window.orderOut(nil)
    }

    /// The hotkey: shows a hidden panel, gives the keyboard to a visible one without it, and hides one
    /// with it, except while a command runs or a start is in flight.
    internal func toggle() {
        guard window.isVisible else { return show() }
        guard window.isKeyWindow else { return window.makeKeyAndOrderFront(nil) }
        hide()
    }

    /// Escape, by every route: peels one layer.
    ///
    /// An open recall list is closed and nothing else changes. Otherwise a running
    /// command not yet stopped is stopped; a stopped command, a result or a typed line is cleared; a clean
    /// panel is hidden. In flight, nothing.
    internal func escape() {
        if listOpen { return closeList() }
        guard submission == nil else { return }
        switch state {
        case .running where !stopped:
            stop()
        case nil where window.input.stringValue.isEmpty:
            hide()
        default:
            clear()
        }
    }

    /// Starts `typed`; a blank line starts the `-tt` offer when there is one and otherwise nothing.
    ///
    /// One submission at a time: while one waits on the launch task, another does nothing. The directory
    /// is read from the store here, at Return; a fixed folder that does not exist gives way to home.
    internal func submit(_ typed: String) {
        let blank = typed.allSatisfy(\.isWhitespace)
        var line = blank ? nil : typed
        if blank, case .done(_, let offer?) = state { line = offer }
        guard let line, submission == nil else { return }
        closeList()
        setSuggestion(nil)
        failedStart = nil
        terminalFailure = nil
        let start = startingDirectory()
        starting = start
        startingLine = line
        let size = window.terminalSize
        submission = Task {
            // A failed capture is the notice's to report; the command runs with the app's environment.
            _ = try? await launch.value
            // Run starts nothing until the command a clear killed has reported its Done.
            if cleared != nil { await withCheckedContinuation { cleared?.append($0) } }
            do {
                try await run.start(line: line, cwd: start.directory, size: size)
            } catch RunError.spawnFailed(let code) {
                failStart("Could not start: " + String(cString: strerror(code)))
            } catch {
                failStart("Could not start: \(error)")
            }
        }
    }

    /// Stop, Control-C and Escape on a live command: the first since the command started interrupts the
    /// group, later ones kill it.
    internal func stop() {
        guard case .running = state else { return }
        stopped = true
        stops += 1
        let first = stops == 1
        Task {
            if first { await run.interrupt() } else { await run.kill() }
        }
    }

    /// Acts on a key pressed while a command runs; nothing written is kept or shown.
    internal func keystroke(_ action: Keystrokes.Action) {
        switch action {
        case .write(let bytes):
            Task { await run.write(bytes) }
        case .stop:
            stop()
        case .paste:
            guard let text = NSPasteboard.general.string(forType: .string) else { return }
            keystroke(.write(Array(text.utf8)))
        case .escape:
            escape()
        case .ignore:
            break
        }
    }

    /// Adds a line to the notice: the hotkey's failure, or the environment's.
    internal func note(_ line: String) {
        notices.append(line)
        apply()
    }

    /// The update line: shown under the bar with `version`, the newer release a check found; nil shows none.
    ///
    /// It touches nothing else: not the state, the input, the transcript, the keyboard or a running command.
    /// Only the panel's height follows the line.
    internal func announce(_ version: String?) {
        window.showUpdate(version.map(UpdateCheck.notice(for:)))
        window.fit()
    }

    /// A click on the update line: the project's site, where the download and what changed are.
    internal func openSite() {
        openURL(UpdateCheck.site)
    }

    /// Command-1 through Command-9: the slot's command replaces the input's text, the cursor at its end.
    ///
    /// Nothing runs; Return submits it as any typed line. An empty slot does nothing, and while a command
    /// runs the digits go nowhere. A load shows no suggestion; an open recall list filters by the new text,
    /// as after any key that changes it.
    internal func loadMacro(_ number: Int) {
        if case .running = state { return }
        let macros = settings.macros
        guard macros.indices.contains(number - 1) else { return }
        let command = macros[number - 1]
        guard !command.isEmpty else { return }
        load(command)
        if listOpen { refilter() }
    }

    /// A new, empty window of the chosen terminal at the directory the command ran in.
    ///
    /// The command never re-runs. A terminal that is not installed is said on the strip until the next
    /// submission or a clear.
    internal func openInTerminal() {
        let identifier = settings.terminal
        guard let terminal = Terminals.url(for: identifier) else {
            terminalFailure = "\(identifier) could not be found."
            return apply()
        }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: ranIn ?? Self.home)],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration())
    }

    /// Quit: waits for a submission in flight, then kills the command, or the one a clear is still killing, and
    /// waits at most one second for its Done.
    internal func killForQuit() async {
        await submission?.value
        guard isBusy || awaitsClearedDone else { return }
        await run.kill()
        let deadline = ContinuousClock.now + .seconds(1)
        while isBusy || awaitsClearedDone, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The panel becomes Clean and stays on screen with the keyboard in the input; a command still
    /// running is killed, and nothing of it is drawn from here on.
    private func clear() {
        closeList()
        setSuggestion(nil)
        if case .running = state {
            stopped = true
            cleared = cleared ?? []
            Task { await run.kill() }
        }
        state = nil
        failedStart = nil
        missingFolder = nil
        terminalFailure = nil
        window.input.stringValue = ""
        window.transcript.clear()
        apply()
    }

    /// The start ended before Running: the reason is held and shown until something replaces it.
    private func failStart(_ reason: String) {
        submission = nil
        starting = nil
        startingLine = nil
        failedStart = reason
        apply()
    }

    /// Takes what Run reports.
    ///
    /// A Done that finds no command on the panel is the Done of one a clear killed: it changes nothing,
    /// and a start waiting for it goes ahead. At Running the line that started is kept in the history, and
    /// at no other moment; the recall list closes and the suggestion goes.
    private func enter(_ next: RunState) {
        var ran: String?
        switch next {
        case .running:
            ran = startingLine
            startingLine = nil
            closeList()
            setSuggestion(nil)
            submission = nil
            failedStart = nil
            ranIn = starting?.directory
            missingFolder = starting?.missing
            starting = nil
            stops = 0
            stopped = false
            window.transcript.clear()
        case .done:
            guard state != nil else {
                for waiting in cleared ?? [] { waiting.resume() }
                cleared = nil
                return
            }
        }
        state = next
        apply()
        if let ran { history.record(ran) }
    }

    /// Derives every control's visibility, the status line and the keyboard's place from `state`, a failed
    /// start's or Open in Terminal's reason, and a missing folder.
    private func apply() {
        let failure = terminalFailure ?? failedStart
        var running = false
        var exit: Exit?
        var offer: String?
        switch state {
        case .running:
            running = true
        case .done(let ended, let retry):
            exit = ended
            offer = retry
        case nil:
            break
        }
        window.stopButton.isHidden = !running
        window.retryButton.isHidden = offer == nil
        window.openButton.isHidden = exit == nil
        // Composing is the bar alone; a start that failed before Running shows its reason on the strip.
        window.outputCard.isHidden = state == nil && failure == nil
        window.input.isEditable = !running
        window.transcript.showsCursor = running

        var status = ""
        switch exit {
        case .status(let code):
            status = "exit \(code)"
        case .signal(let number):
            status = "signal \(number)"
        case nil:
            status = running ? "running" : ""
        }
        if let offer { status += " · Return or Retry runs \(offer)" }
        if let missingFolder {
            status = "\(missingFolder) could not be found; ran in home" + (status.isEmpty ? "" : " · " + status)
        }
        let alarm = failure != nil || missingFolder != nil || (exit != nil && exit != .status(0))
        window.status.stringValue = failure ?? status
        window.status.textColor = (alarm ? Theme.Token.alarm : Theme.Token.inkFaint).nsColor
        window.notice.stringValue = notices.joined(separator: "\n")
        window.notice.isHidden = notices.isEmpty

        if running {
            if window.firstResponder !== window.transcript { window.makeFirstResponder(window.transcript) }
            window.input.stringValue = ""
        } else if window.input.currentEditor() == nil {
            window.makeFirstResponder(window.input)
        }
        window.fit()
    }

    /// The user's home: where commands start by default, and instead of a fixed folder that is gone.
    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// Where the next command starts, read from the store now: home, or the fixed folder if it is an
    /// existing directory; otherwise home, with the folder that could not be found.
    private func startingDirectory() -> (directory: String, missing: String?) {
        guard settings.directoryMode == .fixed, let path = settings.directoryPath else { return (Self.home, nil) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return (Self.home, path)
        }
        return (path, nil)
    }

    private static func reason(_ error: any Error) -> String {
        switch error as? LoginEnvironment.CaptureError {
        case .noLoginShell?:
            "no login shell"
        case .shellFailed(let status)?:
            "shell exited \(status)"
        case .timedOut?:
            "timed out after five seconds"
        case nil:
            error.localizedDescription
        }
    }
}

// Recall: the list under the input and the grey suggestion after the cursor. Neither runs anything: a choice,
// a taken suggestion and the list's opening change the input's text and nothing else, and only Return or
// Retry submits, with the input's value, which never holds grey text.
extension Panel {
    /// Asked of the list itself, not kept here, so it can never disagree with what is on screen.
    internal var listOpen: Bool { window.recall.isOpen }

    /// Down-arrow in the input: moves an open list's selection older, or opens the list when the cursor is
    /// on the input's last line and no command runs or is in flight.
    ///
    /// False leaves the key to the field editor, which moves the cursor as in any text field.
    internal func down() -> Bool {
        if listOpen {
            window.recall.select(window.recall.selected + 1)
            return true
        }
        guard !isBusy, let editor = window.input.currentEditor(), editor.selectedRange.location >= lastLineStart
        else { return false }
        setSuggestion(nil)
        refilter()
        return true
    }

    /// Up-arrow in the input: moves an open list's selection newer, and closes it from the top row.
    ///
    /// False, with the list closed, leaves the key to the field editor.
    internal func up() -> Bool {
        guard listOpen else { return false }
        if window.recall.selected == 0 {
            closeList()
        } else {
            window.recall.select(window.recall.selected - 1)
        }
        return true
    }

    /// Return in the input with the list open: the selected row is chosen, and nothing is submitted.
    ///
    /// False, with the list closed, leaves Return to submit.
    internal func returnInList() -> Bool {
        guard listOpen else { return false }
        choose(row: window.recall.selected)
        return true
    }

    /// A row chosen by Return or a click: it replaces the input's last line, the cursor goes to the end, and
    /// the list closes; with no rows the list closes and nothing changes.
    internal func choose(row: Int) {
        let rows = window.recall.rows
        closeList()
        guard rows.indices.contains(row) else { return }
        let text = window.input.stringValue as NSString
        load(text.substring(to: lastLineStart) + rows[row])
    }

    /// Right-arrow in the input: with a suggestion showing and the cursor at the end, the suggestion joins the
    /// input's text.
    ///
    /// False leaves the key to the field editor, which moves the cursor.
    internal func right() -> Bool {
        guard let suggestion, cursorAtEnd else { return false }
        load(window.input.stringValue + suggestion)
        return true
    }

    /// After a key that changed the input's text: an open list filters by the last line again, its top row
    /// selected; with the list closed, the suggestion is worked out again.
    internal func textChanged() {
        guard !listOpen else { return refilter() }
        setSuggestion(isBusy || !cursorAtEnd ? nil : history.suggestion(for: lastLine))
    }

    /// The input's cursor moved: a suggestion goes once the cursor is no longer at the end of the text.
    internal func selectionChanged() {
        guard suggestion != nil, !cursorAtEnd else { return }
        setSuggestion(nil)
    }

    /// Where the input's last line starts, in UTF-16 units: after its last line break, or at the start.
    private var lastLineStart: Int {
        let found = (window.input.stringValue as NSString).rangeOfCharacter(from: .newlines, options: .backwards)
        return found.location == NSNotFound ? 0 : NSMaxRange(found)
    }

    /// The input's text after its last line break: what the list filters by and the suggestion follows.
    private var lastLine: String {
        (window.input.stringValue as NSString).substring(from: lastLineStart)
    }

    /// True when the input has the keyboard and its cursor is at the end of its text, with nothing selected.
    private var cursorAtEnd: Bool {
        guard let editor = window.input.currentEditor() else { return false }
        return editor.selectedRange == NSRange(location: (editor.string as NSString).length, length: 0)
    }

    /// Opens the list, or fills it again, with the entries the last line matches, the top row selected.
    private func refilter() {
        let filter = lastLine
        let placeholder = filter.isEmpty ? "No commands yet" : "No match"
        window.recall.show(history.matches(filter), placeholder: placeholder, under: window.bar)
    }

    private func closeList() {
        window.recall.withdraw()
    }

    private func setSuggestion(_ text: String?) {
        suggestion = text
        window.showSuggestion(text)
    }

    /// A load: `text` replaces the input's text, the cursor at its end, and no suggestion shows; nothing runs.
    private func load(_ text: String) {
        setSuggestion(nil)
        window.input.stringValue = text
        if window.input.currentEditor() == nil { window.makeFirstResponder(window.input) }
        window.input.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        window.fit()
    }
}
