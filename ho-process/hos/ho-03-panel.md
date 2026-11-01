---
created: 2026-10-31
status: complete
type: ho-document
project: issoku
ho: "03"
kamae: 5
shape: ha
phase: 2 — The Surface
title: Panel — the only visible surface
description: The AppKit panel in the Issoku app target — hotkey, non-activating floating window, the three states and their dismiss rules, Stop, Open in Terminal, the gear and Quit — driving Run end to end with a plain-text transcript placeholder.
builds-on:
  - kamae-1-issoku-seed
  - kamae-2-issoku-system-design
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-02-run.md
  - ho-process/hos/ho-02.1-fix-pass.md
  - ho-process/reviews/ho-02x-report-2.md
model: claude-opus-5-5
opening-hash: f371d87b18d101c5c9ea46bcace9ed3102939067
---

# ho-03 — Panel

This session builds Panel, the only visible surface: the global hotkey, the floating non-activating window, keyboard focus on appearance, the Composing, Running and Done states with their dismiss rules, Stop and Control-C, the `-tt` retry offer, Open in Terminal, the gear with Settings and Quit, and the app entry that runs with no Dock icon. Panel drives the Run that ho-02 built; nothing in `IssokuCore` changes. A plain-text transcript area stands in for ho-04's Transcript so the core interaction runs end to end on the practitioner's machine. The ho-02 run-sheet driver, `Sources/IssokuRunCLI/`, is deleted in this ho's first commit, as ho-02 ruled.

**Out of scope:** rendering beyond plain text—colour, carriage-return overwrite, the line ceiling, selection, Command-C and the Copy control (ho-04); settings storage, the shortcut recorder, the working-directory setting, the terminal picker, history, macros, Refresh Environment (ho-05); Check for Updates, the app bundle, the icon, signing (ho-06); any change under `Sources/IssokuCore/`; any dependency.

**Resolves deferred decisions** (from the System Design and the overview's ho-03 entry):
- Hotkey failure presentation, including the Character Viewer conflict.
- Transcript carry-over into the terminal: dropped (Decision 12).
- Opening Terminal.app at a directory, and how installed terminals are detected for ho-05's picker.
- Whether `Sources/Issoku` carries a coverage floor (left to ho-03 by `scripts/coverage-floor.sh`): yes (Decision 14).

**Every command this ho runs against a host reads. None writes.** Automated tests never touch a live host. The practitioner's run sheet in Execute, part H, runs against one real host; every command on it is read-only and the sudo password is typed by the practitioner and by no one else.

**Tight.** The seed's constraint applies in full and the subagent's brief carries it: no abstraction with one implementation, no state-management framework, no second representation of the panel state, no configuration surface, no helper that wraps one call. ho-03x reads for exactly these (overview, "ho-03x — Review of Panel").

---

## Phase 1 — Think

Sixteen decisions, settled 2026-10-31 between the practitioner and the orchestrator, and two more (17, 18) added the same day from the practitioner's run sheet. Decisions 11, 12 and 14 are the ones the System Design and the coverage script assigned here; the rest fix the shape of the work so the subagent has nothing architectural left to decide. Two facts were checked by a probe before authoring: `RegisterEventHotKey` from `Carbon.HIToolbox` compiles under Swift 6 with strict concurrency and returns `noErr` for the default combination, and registering the same combination a second time in the same process returns `eventHotKeyExistsErr` (−9878); an `NSPanel` with `[.borderless, .nonactivatingPanel]` constructs.

### Decision 1 — The first commit deletes the driver

`Sources/IssokuRunCLI/`, the `issoku-run` product and target in `Package.swift`, and the `Sources/IssokuRunCLI/` entry in the coverage script's ignore pattern go in the opening commit, together with this document, as ho-02's first commit deleted the spike. The orchestrator does this; the subagent starts from a tree with `IssokuCore` and `Issoku` only. ho-02x's N1 dies with it.

### Decision 2 — App entry: an AppKit delegate, accessory activation, reopen built now

The entry point is an `NSApplicationDelegate` class under `@main` in `Sources/Issoku/App.swift`, replacing the placeholder enum. No SwiftUI `App`. At launch the delegate calls `NSApplication.shared.setActivationPolicy(.accessory)`: no Dock icon, no menu bar, which is what a SwiftPM executable without an `Info.plist` can do and what `LSUIElement` would do in a bundle. The delegate implements `applicationShouldHandleReopen(_:hasVisibleWindows:)` to show the panel and return `false`; that is the System Design's recovery path when the hotkey fails. macOS sends reopen only to a bundled app, so the path is built here and demonstrated at ho-06. Recorded in Reflect as deferred proof, not as done.

### Decision 3 — Launch and the environment: one Run, one launch task, `start` waits for it

The delegate creates the app's one `Run` with `Run(environment:)` and the process environment, then starts one task that calls `run.refreshEnvironment()`—the capture of the login shell, which blocks up to five seconds inside the actor, never on the main thread. That task is handed to Panel as `Task<Void, any Error>`. Panel's first `submit` awaits the task before calling `start`, so every command runs with the captured environment, as the System Design says, and no second "ready" state exists. If the task throws, Panel's notice line reads `Login environment not captured (<reason>); using the app's own environment.` where `<reason>` names the `LoginEnvironment.CaptureError` case in plain words (no login shell / shell exited <n> / timed out after five seconds). A command still runs. Tests hand Panel a task that returns at once or throws a chosen error.

### Decision 4 — The window: one non-activating `NSPanel`, Spotlight placement, grows to a cap

`PanelWindow` is an `NSPanel` subclass with style `[.borderless, .nonactivatingPanel]`, level `.floating`, `hidesOnDeactivate = false`, `isMovableByWindowBackground = true`, `canBecomeKey` returning `true`. Non-activating means the panel takes keyboard focus while the app the practitioner was in stays frontmost and has focus the instant the panel hides. Width is fixed at 640 points. The panel appears on the screen that holds the mouse, horizontally centred, its top edge one quarter of the screen's visible height below the screen's top. Height is the input, the control strip, and the transcript; the transcript grows with its content until the panel's height reaches half the screen's visible height, after which the transcript scrolls. Hidden with `orderOut(nil)`, never closed: one window for the app's life. Corner radius 10, ground `Theme.Token.ground`, ink `Theme.Token.ink`, hairlines `inkFaint` at 0.15, per the design system §§2, 4, 5. The subagent reads `../palana/design/palana-design-system.md` §§1–5 and 7 for the rest of the layout. No SwiftUI anywhere in the panel window (ho-03x asks).

**Typography.** System font at 12 for the input and the control strip, 11 for status and notice lines (§3). The transcript area is the one monospace zone, `.monospacedSystemFont(ofSize: 12, weight: .regular)`. The input shows a typed command, which §3 counts as a command line: monospace 12. Nothing else is monospace.

### Decision 5 — One state: the last `RunState`, and one dismiss rule

Panel stores exactly one state value: `private var state: RunState?`, the last value received from `run.states`, nil before the first command. Nil is Composing, `.running` is Running, `.done` is Done. There is no `PanelState` enum and no `isRunning` flag beside it. `var canDismiss: Bool` is one computed property—`true` unless `state` is `.running`—and every dismiss path reads it. Whether the panel is on screen is the window's own `isVisible`, read from the window and copied nowhere. Every control's visibility and every status string is derived from `state` in one method that applies the state to the window; nothing else writes to the controls. This answers ho-03x's first and third questions.

### Decision 6 — Dismiss paths: Escape, click-out, and the hotkey toggles

Three ways to dismiss, all through one `dismissIfAllowed()`: Escape (`cancelOperation(_:)` reaching the window), the panel resigning key (`NSWindow.didResignKeyNotification`, the click-out), and the hotkey pressed while the panel is visible. While Running all three do nothing except that the hotkey brings the panel forward and focuses it; the panel cannot be hidden while a command runs. When Composing or Done, `dismissIfAllowed()` orders the panel out. Showing the panel is `makeKeyAndOrderFront(nil)` after placement, then first responder to the input. Practitioner's ruling 2026-10-31: the hotkey toggles like Spotlight; Escape remains a dismissal in Composing and Done.

### Decision 7 — Stop and Control-C: one action, first interrupts, second kills

Stop and Control-C are the same action behind one counter that resets to zero at every `.done`: the first call is `run.interrupt()`, the second and any later call is `run.kill()`. Control-C is handled by Panel and is never written to the pseudoterminal as byte 0x03. The Stop button is visible only while Running. This matches the System Design ("Stop or Control-C sends an interrupt … a second Stop forces termination") and the ho-02 driver the practitioner used.

### Decision 8 — Keystrokes while Running: the transcript area takes focus and translates

The rule is that nothing typed is drawn locally. While Running the input field resigns first responder and the transcript area becomes first responder. Its `keyDown` hands the event's plain values to one pure function, `Keystrokes.action(characters:modifiers:keyCode:) -> Keystrokes.Action`, with cases `.write([UInt8])`, `.stop`, `.paste`, `.ignore`, and Panel acts on the result:

| Key | Action |
|---|---|
| Printable characters, with or without Shift or Option | `.write` the characters as UTF-8 |
| Return or Enter | `.write([0x0D])` — carriage return, which sudo's password read ends on |
| Delete | `.write([0x7F])` |
| Command-V | `.paste` — Panel writes the general pasteboard's string as UTF-8 |
| Control-C | `.stop` — Decision 7 |
| Escape | `.ignore` — Decision 6 |
| Anything else: arrows, function keys, other Command and Control combinations | `.ignore` |

The function takes `String?` for the characters, `NSEvent.ModifierFlags` for the modifiers and `UInt16` for the key code, nothing else from AppKit, so it is table-tested without a window. The transcript area's `paste(_:)` responder action also maps to `.paste`, so Command-V reaches Run whether it arrives as a key equivalent or a menu action. Full-screen programs are out of scope, so cursor keys are not forwarded. Practitioner's ruling 2026-10-31.

### Decision 9 — The input: wrapping field, Return starts, Shift-Return and Option-Return break, retry by button or empty Return

The input is an `NSTextField` with `usesSingleLineMode = false`, wrapping, growing to at most five lines before it scrolls. Return starts the field's whole string as the line; Shift-Return and Option-Return insert a line break (the field's delegate handles `insertNewline:` and checks the modifier flags; Option-Return is AppKit's own text-field convention). Pasted text keeps its newlines and is shown in full. The whole string, newlines included, is the single `line` argument to `start`; the shell runs it as it would any script text, one process, one exit status. Practitioner's ruling 2026-10-31: pasted sequences run as written and may be composed in the panel; this is recorded here for ho-03x as a deliberate widening of the seed's "one-line" wording, not scope creep.

An empty or whitespace-only line does nothing. The working directory is the user's home (`FileManager.default.homeDirectoryForCurrentUser.path`), the System Design's default until ho-05 adds the setting. The terminal size passed to `start` is computed once per command from the transcript area: columns are the area's width divided by the advance of `M` in the transcript font, rows are the cap height divided by the font's line height. `resize` is not called; ho-04 owns width changes.

`start`'s errors appear in the status line in the alarm colour: `RunError.alreadyRunning` cannot occur because the input is not first responder while Running, but it is still shown if thrown; `RunError.spawnFailed(errno:)` shows `Could not start: <strerror text>`.

**The retry offer.** When `.done` carries `retry: line`, a Retry button appears in the control strip and the status line names the offer; pressing the button or pressing Return in the empty input starts that line verbatim through the same `submit` path. Typing anything into the input leaves the offer available by button but Return then starts what was typed. The offer clears at the next `.running`. Panel makes no change to any line beyond handing Run's `retry` string back to `start`. Practitioner's ruling 2026-10-31: both the button and empty-Return.

### Decision 10 — The transcript placeholder: plain, unbounded, deleted at ho-04

`TranscriptPlaceholder` is a non-editable, non-selectable-for-now `NSTextView` in a scroll view, monospace 12, that appends each chunk from `run.bytes` decoded with `String(decoding:as:UTF8.self)` and scrolls to the end. No colour, no carriage-return handling, no stripping, no ceiling. It is cleared at each `.running`. Panel owns the one task that iterates `run.bytes` for the app's life and appends on the main actor; `Run.Output` is single-consumer and finishes only when Run is released, so the task never ends while the app runs. These limits are stated here as scope: a command that prints without end grows the view until Stop. ho-04 replaces this file entirely. Practitioner's ruling 2026-10-31: plain and unbounded, no crude cap.

### Decision 11 — Hotkey: `RegisterEventHotKey` directly, failure as a status, the Character Viewer case as Discovery

`Hotkey.swift` holds one `register(keyCode:modifiers:handler:) -> OSStatus` that calls `InstallEventHandler` once for `kEventHotKeyPressed` on `GetApplicationEventTarget()` and `RegisterEventHotKey` for the combination, keeping the returned `EventHotKeyRef` for `UnregisterEventHotKey`, and one `statusText(for: OSStatus) -> String?` that is nil for `noErr` and otherwise reads `Control-Command-Space is unavailable (<status>). Another app or macOS may own it; see System Settings > Keyboard > Keyboard Shortcuts.` About forty lines, no type around the call (ho-03x's fourth question). The default is `kVK_Space` with `controlKey | cmdKey`, one constant in `Hotkey.swift`; configurability is ho-05. The handler calls Panel's `toggle()`.

**Presentation** (the System Design's first ho-03 question): the status text, when non-nil, is the panel's notice line and the only content of the Settings window. The panel is reachable by relaunch (Decision 2) when the hotkey never fires.

**Discovery.** Whether macOS's Character Viewer shortcut, when enabled at Control-Command-Space, makes `RegisterEventHotKey` fail or lets it succeed silently so that the handler never fires. The subagent records what it observes on the build machine as the machine is; it does not change system settings. The practitioner's run sheet toggles the system shortcut and records both states. If registration succeeds silently, Reflect says so and the notice cannot be shown for that case in v1; nothing is built to read the system's shortcut preferences.

### Decision 12 — Open in Terminal: the workspace opens the directory in Terminal.app; carry-over dropped

The Open in Terminal button, visible in Done, calls `NSWorkspace.shared.open([cwdURL], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration())` with `cwdURL` the command's working directory and `terminalURL` from `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")`. That is `open -a Terminal <dir>`: a new Terminal window at the directory, empty. If the URL cannot be resolved the status line says so in the alarm colour. The command is never re-run.

**For ho-05's picker, recorded here and not built:** installed terminals are detected by the same `urlForApplication(withBundleIdentifier:)` over a fixed list—`com.apple.Terminal`, `com.mitchellh.ghostty`, `com.googlecode.iterm2`, `net.kovidgoyal.kitty`, `com.github.wez.wezterm`, `org.alacritty`—and opened by the same call. Whether each accepts a directory URL the way Terminal.app does is ho-05's to verify per terminal.

**Carry-over** (the System Design's second ho-03 question): handing the transcript into the new window needs Apple events to Terminal and an Automation permission prompt. Not free; dropped, per the System Design's own rule. Practitioner's ruling 2026-10-31.

### Decision 13 — The gear: Settings… and Quit; Quit kills, waits briefly, terminates

The gear is a button that pops an `NSMenu` with two items: Settings… and Quit. Check for Updates is ho-06. Refresh Environment is a settings action in the System Design and lands at ho-05 with the real settings; ho-02x's N2 test travels with it. `SettingsWindow` at ho-03 is a plain titled window holding the hotkey notice (Decision 11) or the line `Control-Command-Space is registered.`, and nothing else.

Quit: the delegate's `applicationShouldTerminate` returns `.terminateNow` when no command runs. When one runs it returns `.terminateLater` and calls Panel's `killForQuit()`, which calls `run.kill()` and awaits `.done` for at most one second, then the delegate replies `true`. The overview's done criterion is a demonstrated kill, read from the process table.

### Decision 14 — A coverage floor on `Sources/Issoku`, view files excluded by name

`scripts/coverage-floor.sh` gains a second measured set after `IssokuCore`: `Sources/Issoku/` at the same 90% floor, ignoring `Sources/Issoku/App.swift`, `PanelWindow.swift`, `TranscriptPlaceholder.swift` and `SettingsWindow.swift`, each named in a comment that says why—the delegate needs a running application, and the three view files hold layout and event forwarding that cannot be driven headless. `Panel.swift`, `Keystrokes.swift`, `Hotkey.swift` and `Theme.swift` are measured. The script's exit is non-zero if either set is under the floor. The `IssokuRunCLI` ignore goes in Decision 1.

Measured means testable without a window being on screen, not without AppKit: the tests construct a real `PanelWindow` in the test process (AppKit permits this without a bundle) and drive `Panel` through its methods, reading `state`, `canDismiss`, the window's `isVisible`, the placeholder's `string`, and the process table. Panel is `@MainActor`; the suite is `@MainActor` and `.serialized`, because two Runs spawning at once intermittently fail `forkpty` (ho-02 Reflect).

### Decision 15 — Files: seven source files, three test files

```text
Sources/Issoku/App.swift                  the delegate: activation policy, Run, the launch task, Panel, hotkey, reopen, terminate   (modify)
Sources/Issoku/Panel.swift                the controller: state, dismiss rule, submit, stop counter, keystrokes, retry, Open in Terminal, killForQuit
Sources/Issoku/Keystrokes.swift           the pure translation of Decision 8
Sources/Issoku/Hotkey.swift               register, unregister, statusText, the default combination
Sources/Issoku/PanelWindow.swift          the NSPanel subclass, layout, placement, the control strip, the gear menu
Sources/Issoku/TranscriptPlaceholder.swift the plain text view, keyDown and paste forwarding
Sources/Issoku/SettingsWindow.swift       the placeholder settings window
Tests/IssokuTests/PanelTests.swift
Tests/IssokuTests/KeystrokesTests.swift
Tests/IssokuTests/HotkeyTests.swift
```

`Theme.swift` is not modified; the panel reads `Theme.Token.<name>.nsColor`, the appearance-aware `NSColor` that already exists. `Package.swift` is not modified by the subagent (Decision 1 is the orchestrator's). No file under `Sources/IssokuCore/` or `Tests/IssokuCoreTests/` changes.

### Decision 16 — One Opus subagent, no agent-task files, no split

The seams (entry, controller, keystrokes, hotkey, window, placeholder, settings) are real but share one controller and one test suite. One subagent builds them in the order of Decision 15, test first for each measured file, with this document as its whole instruction. The overview's reserve split (ho-03.1 panel and states; ho-03.2 hotkey, recorder, conflicts) is not taken: the recorder is ho-05's and the hotkey is forty lines. If the subagent halts on size or on a question this document does not answer, the orchestrator stops and the practitioner rules.

### Decision 17 — Added at the run sheet: dismissing the panel clears it

Practitioner's ruling 2026-10-31, from run-sheet item 4. The System Design's Composing state allowed "Transcript empty or showing the previous result"; the practitioner rules empty. `dismissIfAllowed()`, when it hides the panel, also returns Panel to Composing: `state` becomes nil, the transcript and the status line clear, and any retry offer goes with them. Every summons starts clean. `state` is still the one stored value; its meaning widens to "the last state Run reported, or nil before the first command and after a dismissal". The stop counter is already zero at Done. Test: a command runs to Done, the panel is dismissed and shown again; `state` is nil, the transcript and status are empty, the Retry and Open in Terminal buttons are hidden.

### Decision 18 — Added at the run sheet: a block cursor while Running

Practitioner's ruling 2026-10-31, from run-sheet item 4 (the sudo prompt). While a command runs the transcript area shows a block cursor after the last byte of output, in the ink colour, so the user can see that keystrokes now go to the command. It is removed at Done. It is not an echo and it is not content: `transcript.string` holds only what the command sent, so the no-echo tests read the same string as before. The mechanism is the subagent's (a trailing glyph outside the stored text, or a drawn rectangle); the placeholder exposes one `showsCursor: Bool` that Panel's `apply` sets from `state`. ho-04's Transcript carries the cursor over. Test: `showsCursor` is true while `.running` and false at `.done` and after dismissal; the string never contains the cursor glyph.

### Discovery (deferred to execution) — three things only the build can show

- **The Character Viewer conflict** (Decision 11): fail or silent success, observed on the build machine as it is.
- **Key equivalents without a menu bar.** An accessory app has no visible menu, and AppKit routes Command-key equivalents through the main menu. The subagent records which mechanism makes Command-V, Command-A, Command-X and Command-C work in the input field in Composing and Done—an `NSApp.mainMenu` carrying a standard Edit menu that is never shown, or the window's `performKeyEquivalent`—and uses the smaller one. Command-V into a running command is Decision 8 and separate.
- **The reopen path** (Decision 2): built, demonstrated at ho-06.

---

## Phase 2 — Execute

One subagent, in the order of Decision 15, test first for `Panel.swift`, `Keystrokes.swift` and `Hotkey.swift`.

### Files

The subagent creates or modifies only:

| Path | Action |
|---|---|
| `Sources/Issoku/App.swift` | modify: the delegate entry of Decisions 2, 3, 13 |
| `Sources/Issoku/Panel.swift` | create |
| `Sources/Issoku/Keystrokes.swift` | create |
| `Sources/Issoku/Hotkey.swift` | create |
| `Sources/Issoku/PanelWindow.swift` | create |
| `Sources/Issoku/TranscriptPlaceholder.swift` | create |
| `Sources/Issoku/SettingsWindow.swift` | create |
| `Tests/IssokuTests/PanelTests.swift` | create |
| `Tests/IssokuTests/KeystrokesTests.swift` | create |
| `Tests/IssokuTests/HotkeyTests.swift` | create |
| `scripts/coverage-floor.sh` | the second measured set of Decision 14, with its comment; nothing else |

The orchestrator, not the subagent, does:

| Path | Change |
|---|---|
| `Sources/IssokuRunCLI/` | `git rm -r` in the opening commit |
| `Package.swift` | remove the `issoku-run` product and the `IssokuRunCLI` target in the opening commit |
| `scripts/coverage-floor.sh` | remove the `Sources/IssokuRunCLI/` ignore in the opening commit |
| `ho-process/hos/ho-03-panel.md` | Reflect, status, frontmatter at close |
| `ho-process/kamae-4-issoku-ho-overview.md` | build-record entry |
| `ho-process/kamae-6-issoku-state-memory.md` | state-summary block |
| `metadata/ho-status.md`, `metadata/ho-status.json` | roster |

### Tests

Every test runs local processes only. The Panel suite is `@MainActor` and `.serialized`.

**Keystrokes** (table-driven, no window): each row of Decision 8's table, plus `a` with Shift (`A`), `é` via Option, Enter on the keypad, Command-C (`.ignore`), Control-D (`.ignore`), an arrow key (`.ignore`), and `nil` characters (`.ignore`).

**Hotkey:** `register` of the default returns `noErr` and `statusText` is nil; a second `register` of the same combination in the same process returns `eventHotKeyExistsErr` and `statusText` names the combination and the status; `unregister` then a third `register` returns `noErr`. The handler firing is not testable and is not tested.

**Panel**, each against a real `Run` and a real `PanelWindow` constructed in the test, with a launch task that returns at once unless the test says otherwise:

- *Composing.* `state` is nil, `canDismiss` is true; `show()` makes the window visible and the input first responder; `dismissIfAllowed()` hides it; `toggle()` twice shows then hides.
- *Submit.* `submit("exit 3")` leads to `.running` then `.done(.status(3), retry: nil)`; the status line reads `exit 3` in the alarm colour; `submit("")` and `submit("   ")` leave `state` nil and start nothing.
- *Running is undismissable.* `submit("sleep 30")`; while `.running`, `dismissIfAllowed()` and `toggle()` leave the window visible and `toggle()` leaves it key; `canDismiss` is false; the input is not first responder and the transcript area is. Then `stop()` and `.done` arrive; the process table for the child's group is empty (`ps -o pid= -g <pgid>`, retried for up to two seconds, read by the test itself).
- *Stop twice.* `submit("sh -c 'trap \"\" INT; sleep 300'")`; `stop()` once, the child is still in the process table after half a second; `stop()` again, `.done(.signal(9), …)` arrives and the group is empty. The counter is zero again: a following `submit("sleep 30")` then one `stop()` ends it.
- *Keystrokes reach the command, nothing echoes.* `submit("stty -echo; read -r secret; echo \"length ${#secret}\"")`; `keystroke` with the bytes of `hunter2` then Return; the placeholder's string contains `length 7` and never `hunter2`.
- *Paste reaches the command.* The test sets the general pasteboard to a known string, calls the action for `.paste`, and the child's `read -r` reports its length; the pasteboard is restored afterwards.
- *The offer.* A fake `ssh` on a test-controlled `PATH` (as ho-02's RunTests build it: prints the sudo fixture's clause to stderr and exits 1 unless its first argument is `-tt`, then prints `ok` and exits 0); the Run is created with that `PATH` and a launch task that returns at once, so the environment is not replaced. `submit("ssh host 'sudo true'")` ends `.done(.status(1), retry: "ssh -tt host 'sudo true'")`, the Retry button is visible, and `submit("")` then starts the offered line, which ends `.status(0)` with no offer and the button hidden.
- *The launch task.* With a task that sleeps 300 ms then returns, `submit("echo ready")` produces no `.running` before the task finishes and `.done` after it. With a task that throws `LoginEnvironment.CaptureError.timedOut`, the notice line contains `not captured` and `timed out`, and the command still runs to `.done`.
- *Start failure.* `submit` with a line in a Run whose working directory is a path that does not exist still reaches `.done` with a non-zero status (ho-02 Reflect: the child exits 127 silently). This test records the behaviour Panel shows; the validation belongs to ho-05.
- *Quit.* `submit("sleep 300")`, then `await killForQuit()` returns within about one second with `state` `.done(.signal(9), …)` and the group empty in the process table.
- *Open in Terminal resolution.* The Terminal.app URL resolves to a path ending in `Terminal.app`. The open call itself is not made in a test.

**Coverage.** `IssokuCore` at or above 90% as before; `Sources/Issoku` measured per Decision 14 at or above 90%. If the floor on the app set cannot be reached without a test that exists only to execute lines, the subagent halts and reports which lines, rather than writing that test.

### Rules for the subagent

- No commits. The orchestrator commits.
- No files outside the table above. Nothing under `Sources/IssokuCore/`, nothing in `Package.swift`, nothing in `Theme.swift`.
- No dependencies. `Carbon.HIToolbox` and `AppKit` are system frameworks and are the only imports beyond Foundation and IssokuCore.
- No SwiftUI in any file this ho touches.
- No architectural decisions. If this document and the System Design do not answer a question, halt and report the question. Do not pick.
- No test touches a live host or the network. No test changes system settings. No test reads the test process's stdin. No test or source logs, stores, or echoes anything written through `Run.write`.
- Never `pkill` or `killall` by pattern, in a test or by hand. Tests kill by pid or pgid they own.
- Strict concurrency, language mode 6. Panel, the window, the views and the delegate are `@MainActor`. No `@unchecked Sendable`, no `nonisolated(unsafe)`, no force unwrap without a `// FORCE:` comment, no lint suppression without a comment naming why.
- Tight: one stored state value (Decision 5); one dismiss rule; no protocol with one conformer; no generic over one type; no configuration struct; no manager; no helper that wraps one call; no comment that says what the next line does.
- Report back with: every file written, every command in Verification with its full output, both coverage numbers, the Discovery results, and the mechanism chosen for key equivalents.

### Verification

Run from the repository root, in this order, all green before reporting:

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
swift test --enable-code-coverage && scripts/coverage-floor.sh
swift build -c release
```

The orchestrator then reads the whole diff, runs the stack again, runs `pre-commit run --all-files` with the ho-03 paths staged, sweeps for secrets and real names, and commits.

### H. The practitioner's run sheet (after the orchestrator's verification, before close)

From the repository root with `swift build` done, launch `.build/debug/Issoku` from a terminal (it stays attached; Control-C there quits it) or with `open .build/debug/Issoku`. Every command reads. Record what the panel shows and the status of each.

1. No Dock icon appears. Press Control-Command-Space: the panel appears over the current app with focus in the input; the app underneath stays frontmost. Press it again: the panel hides.
2. `uptime` — output below the input, `exit 0`. Escape hides the panel.
3. `ssh host-a uptime` — remote, `exit 0`.
4. `ssh host-a 'sudo true'` — sudo's two refusal lines, `exit 1` in rust, the Retry button and the offer in the status line. Press Return in the empty input: the line relaunches with `-tt`, the password prompt appears, type the password, nothing is drawn, `exit 0`.
5. `sleep 30` — while it runs: Escape, a click on another window, and the hotkey each leave the panel up; the input does not take typing; Stop ends it with a non-zero status.
6. `sh -c 'trap "" INT; sleep 300'` — Stop once, still running; Stop again, `signal 9`. In a terminal, `ps -o pid= -g <pid shown or found with pgrep -x sleep>` is empty.
7. `sleep 299` — then gear → Quit. In a terminal, `pgrep -fx 'sleep 299'` prints nothing.
8. Relaunch. Run `pwd` so the panel is Done, then Open in Terminal: a Terminal.app window opens at your home directory, empty.
9. Paste two lines, `echo one` and `echo two`, into the input; both show; Return runs both, `exit 0`. Then compose the same with Shift-Return between them.
10. In System Settings > Keyboard > Keyboard Shortcuts > Input Sources, enable "Show Emoji & Symbols" at Control-Command-Space if it is not already; quit and relaunch Issoku; record whether the notice line appears in the panel (reached by relaunching Issoku again) and in Settings, and whether the hotkey still fires. Restore the setting to what it was.

The practitioner pastes the observations; the orchestrator records them in Reflect with host names redacted per the project's map.

### Done means

- The core interaction's steps 1 through 7 run end to end on the practitioner's machine with the plain-text placeholder, recorded in the run sheet.
- Escape, click-out and the hotkey are inert while Running and dismiss when Done, demonstrated (item 5) and tested.
- Quit kills a running command, demonstrated with the process table (item 7) and tested.
- Stop then Stop interrupts then kills, demonstrated and tested with the process table as witness.
- Nothing typed while Running is drawn locally, demonstrated with a sudo password (item 4) and tested with `stty -echo`.
- One stored state value in Panel and one dismiss rule, by inspection of the diff.
- `IssokuCore` and the measured `Sources/Issoku` set both at or above 90%.
- The six verification commands pass with output recorded; no warning suppressed, no force unwrap without `// FORCE:`; no SwiftUI in the panel.
- Two commits on `main`: `ho-03: panel — open; delete the driver` (this document, the driver removal) and `ho-03: panel — the only visible surface` (everything else, the build-record entry). No trailers.
- The closing hash is recorded; ho-03x is authored from the x template over `f371d87b18d101c5c9ea46bcace9ed3102939067..<closing hash>` with the overview's ho-03x questions pasted verbatim.

---

## Phase 3 — Reflect

Drafted 2026-10-31 after the subagent's return and the orchestrator's verification, before the practitioner's run sheet; the run-sheet sections were filled the same day after it.

**Commits.** The practitioner lifted the spec-approval gate for this ho before leaving the session ("lift for now, do as much as you can"), so the build ran unattended against the spec. Done means named two commits; there are five, because the run sheet needs the practitioner at the keyboard and produced two more decisions:

| Commit | Message |
|---|---|
| `dec68946185e57ddea39672794dc66b2a884ae27` | `ho-03: panel — open; delete the driver` |
| `7775d8dfb45e7cdb18563599411a36597badf7a3` | `ho-03: panel — build verified; run sheet pending` |
| `489eaf5b117ace05737183629e2c091e994a31b9` | `ho-03: panel — Reflect drafted before the run sheet` |
| `205f618d6e15b8a2cf889694c206f5a45df0223e` | `ho-03: panel — clear on dismiss and the block cursor, from the run sheet` |
| the closing commit | `ho-03: panel — the only visible surface` (this Reflect, the build-record entry) |

ho-03x reads the whole range from `f371d87b18d101c5c9ea46bcace9ed3102939067`, the commit before the first of these.

**Did the design hold?** Yes, as built and tested; the run sheet decides the rest. Panel holds one `private(set) var state: RunState?` and derives every control, the status line and the keyboard's place from it in one `apply` method; `canDismiss` is the one rule and Escape, the click-out (`resignKey`) and the hotkey all reach `dismissIfAllowed()`. The hotkey is `RegisterEventHotKey` behind one `register` function; Keystrokes is one pure function over the event's plain values; the window is an `NSPanel` with no SwiftUI. Four things the Think phase did not have:

1. **The click-out is `resignKey()`, not the notification.** Observing `didResignKeyNotification` leaves an observer token that a nonisolated `deinit` cannot remove under strict concurrency; overriding the method that posts it has no token. Same behaviour, less state.
2. **The spec's test commands race.** Stop can reach the child before `trap` is installed, and keystrokes before `stty -echo`. The tests put `echo ready` after the set-up and wait for it in the transcript. The spec's intent is unchanged.
3. **Whitespace-only Return with an offer showing takes the offer.** The spec said both that empty Return takes the offer and that a whitespace-only line does nothing; the subagent read whitespace-only as empty. Not reversed at the run sheet; it stands, and ho-03x may read it.
4. **`Panel.init` takes `directory:`**, defaulting to home, so the missing-directory test can set it; ho-05's working-directory setting is its second caller. Not a configuration surface: one plain value.

Two further choices of the subagent's, recorded for ho-03x: `collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]` on the window, with a comment tracing it to the System Design's "appears over the current app"; and the status line reading `running` while a command runs, `exit N` or `signal N` after, with ` · Return or Retry runs <line>` appended when there is an offer. The capture-failure notice is posted when the launch task fails, not held until the first submit. The input and the transcript both clear at `.running`. One lint suppression, `optional_data_string_conversion`, on the `String(decoding:as:)` Decision 10 requires, with its reason beside it.

**Decision review.** 2 through 14 hold as written. 5 (one state) and 14 (the app floor) did their work: the floor is met at 92.28% with the four named files excluded, and nothing about the panel state exists outside Panel. 8 (the keystroke set) and 9 (line breaks) are built as ruled and passed the run sheet (items 4 and 9). 11's about-forty lines came in at 51, which includes `unregister` and `statusText`. 17 and 18 were added from the run sheet and built the same day: `dismissIfAllowed()` sets `state` to nil and clears the transcript before `apply()`, so one more write to the one state value and no new rule; the cursor is a rectangle drawn in `TranscriptPlaceholder.draw(_:)` after the last glyph, or at the extra line fragment when the text is empty or ends a line, switched by `showsCursor`, which `apply` sets from `state`. `PanelWindow.fit()` keeps the transcript area open while the cursor shows, so an empty Running panel has somewhere to draw it. The practitioner confirmed both behaviours in the rebuilt binary.

**Discovery results.**

- *The Character Viewer conflict.* On the build machine `RegisterEventHotKey` returned `noErr` for Control-Command-Space and `eventHotKeyExistsErr` (−9878) for a second registration in the same process; a read-only look at the system's symbolic-hotkey preferences showed nothing bound to Control-Command-Space on this machine, so the conflict case did not arise here. Whether the handler fires needs a real key press: run sheet items 1 and 10.
- *Key equivalents without a menu bar.* The subagent probed both mechanisms in a scratch accessory app: with no menu, a synthesized Command-A did nothing; a hidden main menu with an Edit menu worked; the window's `performKeyEquivalent` worked. Both are about ten lines. It chose the window override because it does not depend on AppKit consulting the main menu for an app that is not active, which the probe could not exercise. The override maps Command-X, C, V, A to `cut:`, `copy:`, `paste:`, `selectAll:` on the first responder. While Running, Command-V therefore reaches the transcript's `paste(_:)`, which is Decision 8's `.paste`.
- *The reopen path.* `applicationShouldHandleReopen` is built and returns `false` after showing the panel; demonstrated at ho-06 with the bundle.

**Verification, orchestrator's run, 2026-10-31.** `swift-format lint --recursive --strict Sources Tests`: exit 0. `swiftlint lint --strict`: 0 violations in 21 files. `swift build`: complete, 0 warnings. `swift test`: 18 tests in 4 suites in `IssokuTests` (Keystrokes 13 rows, Theme 3, Hotkey 1, Panel 13 cases) and 39 in 4 suites in `IssokuCoreTests`, 0 failures; the app target was run seven times in all without a failure. `scripts/coverage-floor.sh`: IssokuCore 93.65% over 4 files; `Sources/Issoku` 92.18% over 4 files (Hotkey 83.33%, the press callback and the install-failure return; Keystrokes 100%; Panel 93.12%, `openInTerminal`, the spawn-failure and generic catch branches and the reason fallback; Theme 84.21%, its SwiftUI `color` accessors, unused by AppKit). `swift build -c release`: complete, 0 warnings. `pre-commit run` with the eleven paths staged: every hook passed. The subagent's own transcript of the same six commands matched. A launch probe of `.build/debug/Issoku` stayed up for three seconds, exited 143 on `SIGTERM`, and left no process behind.

**Verification after Decisions 17 and 18, orchestrator's runs, 2026-10-31.** The same six commands at `205f618` and again on the unchanged tree before the closing commit: format exit 0; 0 violations in 21 files; build complete, 0 warnings; 21 tests in 4 suites in `IssokuTests` (Panel 16 cases, three new: `dismissalClears`, `cursor`, and the offer clearing on dismissal) and 39 in `IssokuCoreTests`, 0 failures; IssokuCore 93.65%, `Sources/Issoku` 92.28%; release build complete, 0 warnings. The subagent's first run of the D17/18 change failed swift-format on four lines (doc-comment summaries over the line length); it fixed them and reran green before reporting.

**Size.** `Sources/Issoku/` at close: App 50, Hotkey 51, Keystrokes 48, Panel 223, PanelWindow 234, SettingsWindow 29, TranscriptPlaceholder 78 nonblank lines, 713 new; Theme 111 unchanged. The three test files: PanelTests, KeystrokesTests, HotkeyTests.

**Watch items for ho-03x and ho-04.** The placeholder calls `fit()` after every chunk and `fit()` lays out the whole text each time, so a very large output grows slower as it grows; it is the placeholder ho-04 deletes, and ho-04's ceiling is the fix. The `exit 3` state-trace test samples `state` between main-actor jobs and asserts exactly three values; stable in seven runs, named here in case it is not under load.

**The run sheet.** Run by the practitioner 2026-10-31 against the build at `7775d8d`, from `.build/debug/Issoku`; host names redacted per the project's map. Items 1–10 of part H:

1. Pass. No Dock icon; Control-Command-Space showed the panel over the current app with focus in the input, and hid it again. The hotkey fires on this machine.
2. Pass. `uptime`, output below the input, `exit 0`, Escape hid the panel.
3. Pass. `ssh host-a uptime`, remote, `exit 0`. The practitioner noted once that Escape did not dismiss the panel afterwards; the step could not be repeated ("couldn't repeat it") and is recorded as unreproduced, not as a defect. ho-04 and ho-05 keep an eye on Escape in Done.
4. Pass, with two rulings. `ssh host-a 'sudo true'` showed sudo's refusal lines, `exit 1` in the alarm colour, the Retry button and the offer in the status line. Return in the empty input relaunched with `-tt`; the panel then read `running`, Stop, `[sudo] password for <user>:` and nothing more; the password was typed, nothing was drawn, `exit 0`. Two things the practitioner saw: after Escape, the next summons still showed the previous output ("it shouldn't be"), which became Decision 17; and the bare prompt gave no sign that keystrokes now went to the command ("would a cursor help?"), which became Decision 18. Both built and committed at `205f618` and confirmed by the practitioner in the rebuilt binary before close.
5. Pass. During `sleep 30`, Escape, a click on another window and the hotkey each left the panel up; the input took no typing; Stop ended it with a non-zero status.
6. Pass. `sh -c 'trap "" INT; sleep 300'`: after the first Stop the command was still running and `pgrep -fx 'sleep 300'` printed its pid; after the second, `signal 9` and the same `pgrep` printed nothing.
7. Pass. `sleep 299`, gear, Quit; `pgrep -fx 'sleep 299'` printed nothing.
8. Pass. After relaunch and `pwd`, Open in Terminal opened a Terminal.app window at the home directory, empty.
9. Pass. Two pasted lines showed in full and ran as one command, `exit 0`; the same composed with Shift-Return between them ran the same way.
10. Not reproducible on this machine. System Settings > Keyboard > Keyboard Shortcuts > Input Sources has no "Show Emoji & Symbols" item on this macOS; only the two input-source items (Control-Space, Control-Option-Space) are listed, both unchecked. Nothing was changed and nothing had to be restored. Together with item 1 and the Discovery result above, the conflict case did not arise here: registration returned `noErr` and the hotkey fires. If a machine does own Control-Command-Space, what `RegisterEventHotKey` returns there is still unobserved; the notice is built for the failing case and the relaunch path (Decision 2) is the fallback for silent success.

The practitioner also asked for a command history during item 3. It is ho-05's (the System Design's Memory component); nothing was built for it here and nothing in Panel anticipates it beyond `submit(_:)` taking the whole line as one string.

**What broke that the tests didn't catch?** Nothing in the code failed. Two gaps were in the design, both inside what the System Design allowed: Composing permitted the previous result to stay on screen, and the practitioner found it wrong at the keyboard; and a running command that waits silently for input looked the same as one doing nothing. Both were decided and built as Decisions 17 and 18 within the ho rather than deferred, because each was one write to the one state value and one drawn rectangle. The one thing the tests cannot witness remains the hotkey firing (item 1).

**Followups for ho-04 and ho-05.** Facts only.

- ho-04 Think input, practitioner's ruling 2026-10-31 after seeing Spotlight's bar: Composing collapses to the input alone, with the transcript appearing beneath it as its own surface once there is output. Derived from `state`, no style switch. One style only; a capsule shape or larger input type is a pālana question, decided once, not a setting.
- ho-05: history. Asked for at the run sheet; Memory's.

- ho-04 replaces `TranscriptPlaceholder.swift` whole and takes over the `bytes` task in `Panel.init`, `terminalSize` in `PanelWindow`, and `fit()`'s transcript measurement. Call `resize` when the width changes.
- ho-05: `Panel.init(directory:)` is where the working-directory setting arrives; validate a stored directory (a missing one exits 127 silently, tested here as `missingDirectory`). `Hotkey.combination` is the one constant the recorder replaces. The terminal picker's detection list is in Decision 12. Refresh Environment and ho-02x's N2 test land with settings.
- ho-06: demonstrate reopen with the bundle; `Hotkey.unregister` is never called at quit, since process exit releases it.

### Closing this ho

Closing = fill this Reflect + flip `status: complete` in the frontmatter + write the state-summary block to the top of `ho-process/kamae-6-issoku-state-memory.md` + append a build-record entry to `ho-process/kamae-4-issoku-ho-overview.md` with the closing hash recorded by the convention ho-00's entry states + regenerate `metadata/ho-status.md` and `metadata/ho-status.json`. Then author `ho-process/hos/ho-03x-review-of-panel.md` from `ho-process/x-ho-template.md`, commit it, and hand off to Codex. The block, verbatim labels and order:

**STATE-SUMMARY**
- **COMPLETED** — <what this ho finished>
- **NEXT** — <the single pointer to what comes next>
- **ACTION ITEMS / BLOCKS** — <open items; blocks loudly, or `none`>
- **PROJECT LIFECYCLE** — kamae

---

_Authored: 2026-10-31 (Think phase, practitioner and orchestrator)._
_Executed and closed: 2026-10-31. ho-03x pending._
