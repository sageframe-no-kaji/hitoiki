import AppKit
import IssokuCore

/// The controller behind the only visible surface: the last state Run reported, the one dismiss
/// rule, and what each control and each key does to the Run.
@MainActor
internal final class Panel {
    /// Terminal.app, which every Mac has; the picker is ho-05's.
    internal static let terminal = "com.apple.Terminal"

    /// The last state Run reported, or nil before the first command and after a dismissal.
    ///
    /// Nil is Composing, `.running` is Running, `.done` is Done.
    internal private(set) var state: RunState?

    private let run: Run
    private let launch: Task<Void, any Error>
    private let window: PanelWindow
    private let directory: String
    /// Stops since the last Done: the first interrupts, every later one kills.
    private var stops = 0
    private var notices: [String] = []

    /// True unless a command runs; every dismiss path reads it.
    internal var canDismiss: Bool {
        if case .running = state { return false }
        return true
    }

    /// Drives `run` through `window` for the app's life.
    ///
    /// - Parameters:
    ///   - run: The app's one Run.
    ///   - launch: The capture of the login environment; the first command waits for it.
    ///   - window: The panel this controller shows, hides and fills.
    ///   - directory: Where commands start; the working-directory setting is ho-05's.
    internal init(
        run: Run,
        launch: Task<Void, any Error>,
        window: PanelWindow,
        directory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.run = run
        self.launch = launch
        self.window = window
        self.directory = directory
        window.panel = self
        window.transcript.panel = self
        // Run's streams are single-consumer and end only when Run is released; these tasks hold
        // neither Run nor Panel, so both end with Panel.
        let bytes = run.bytes
        let states = run.states
        Task { [weak self] in
            for await chunk in bytes {
                // Decoding repairs, never drops: a chunk can end inside a UTF-8 sequence, and the
                // failable initializer the rule prefers would lose the whole chunk.
                // swiftlint:disable:next optional_data_string_conversion
                self?.window.transcript.append(String(decoding: chunk, as: UTF8.self))
                self?.window.fit()
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

    /// Hides the panel unless a command runs, and returns it to Composing.
    ///
    /// Every summons starts clean. Escape, click-out and the hotkey all come here.
    internal func dismissIfAllowed() {
        guard canDismiss else { return }
        window.orderOut(nil)
        state = nil
        window.transcript.string = ""
        apply()
    }

    /// The hotkey: shows a hidden panel, hides a visible one, and brings a running one forward.
    internal func toggle() {
        guard window.isVisible else { return show() }
        dismissIfAllowed()
        if window.isVisible { show() }
    }

    /// Starts `typed`; a blank line starts the `-tt` offer when there is one and otherwise nothing.
    internal func submit(_ typed: String) {
        let blank = typed.allSatisfy(\.isWhitespace)
        var line = blank ? nil : typed
        if blank, case .done(_, let offer?) = state { line = offer }
        guard let line else { return }
        let size = window.terminalSize
        Task {
            // A failed capture is the notice's to report; the command runs with the app's environment.
            _ = try? await launch.value
            do {
                try await run.start(line: line, cwd: directory, size: size)
            } catch RunError.spawnFailed(let code) {
                apply(failure: "Could not start: " + String(cString: strerror(code)))
            } catch {
                apply(failure: "Could not start: \(error)")
            }
        }
    }

    /// Stop and Control-C: the first since the last Done interrupts the group, later ones kill it.
    internal func stop() {
        guard case .running = state else { return }
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
        case .ignore:
            break
        }
    }

    /// Adds a line to the notice: the hotkey's failure, or the environment's.
    internal func note(_ line: String) {
        notices.append(line)
        apply()
    }

    /// A new, empty Terminal.app window at the command's working directory; the command never re-runs.
    internal func openInTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.terminal) else {
            return apply(failure: "Terminal.app could not be found.")
        }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: directory)],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration())
    }

    /// Quit: kills a running command and waits at most one second for its Done.
    internal func killForQuit() async {
        guard case .running = state else { return }
        await run.kill()
        let deadline = ContinuousClock.now + .seconds(1)
        while case .running = state, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func enter(_ next: RunState) {
        state = next
        switch next {
        case .running:
            window.transcript.string = ""
        case .done:
            stops = 0
        }
        apply()
    }

    /// Derives every control's visibility, the status line and the keyboard's place from `state`.
    private func apply(failure: String? = nil) {
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
        let alarm = failure != nil || (exit != nil && exit != .status(0))
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
