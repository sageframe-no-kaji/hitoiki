# ho-03x report, run 3

Commit range: f371d87b18d101c5c9ea46bcace9ed3102939067..31d73750b5fb103dca6cad1eff9ec5c2d57b9e01
Build: pass — `swift build`, exit 0; `Build complete! (2.04 sec)`.
Tests: 66 passed, 0 failed — `swift test`, exit 0; 26 IssokuTests and 40 IssokuCoreTests.
Coverage: IssokuCore 93.73% over 4 files; Sources/Issoku 91.78% over 4 files — `swift test --enable-code-coverage` and `scripts/coverage-floor.sh`, both exit 0; both floors are 90%.

The source, tests, package and coverage script in the checkout match the range endpoint. Supplemental probes interpreted the existing source through Swift's standard input, omitting only the application entry annotation and imports between the combined targets; their windows stayed hidden and they created no source, test or fixture files. A submission was undismissable immediately after submit and during a gated launch; Quit awaited that gate, reached Done by SIGKILL, and `/bin/ps` showed no living child of the probe process. Another probe ran 100 successive commands, pausing the main actor for 50 ms on every tenth command: every transcript exactly matched the expected output at Done, stayed empty after dismissal, and left no living child. No remote host was contacted and `.build/debug/Issoku` was not launched.

## Findings

### Must fix

- none.

### Should fix

- none.

### Note

- N1 — `Tests/IssokuTests/PanelTests.swift:360` — The cursor test would still pass if `TranscriptPlaceholder.draw(_:)` drew nothing, because its assertions inspect the cursor flag and stored text; `terminalResolves()` at line 554 likewise queries NSWorkspace without calling `Panel.openInTerminal()`. These are the retained evidence boundaries at `ho-process/hos/ho-03.1-fix-pass.md:37` and `ho-process/hos/ho-03.2-fix-pass.md:32`, with the view/delegate coverage exclusions authorized at `ho-process/hos/ho-03-panel.md:129`. Cursor drawing and Terminal opening have practitioner evidence at that spec's lines 313 and 340; the automated results do not independently witness them. This answers brief question 3.

- N2 — `Tests/IssokuTests/PanelTests.swift:23` — The process-table reader and survivor polling duplicate `Tests/IssokuCoreTests/RunTests.swift:81` and line 94, while the owned environment at PanelTests line 18 duplicates RunTests line 26. PanelTests line 140 also embeds the sudo refusal held separately in `Tests/IssokuCoreTests/Fixtures/sudo-no-terminal.txt:1`. This is the cross-target duplication expressly retained at `ho-process/hos/ho-03.1-fix-pass.md:37` and `ho-process/hos/ho-03.2-fix-pass.md:32`; it answers brief question 5.

## Brief questions

1. none. No added protocol with one conformer, generic with one instantiation, or discretionary forwarding layer was found. The target/action selectors at `Sources/Issoku/PanelWindow.swift:182`, line 188 and line 193 are the AppKit bridges required by Decisions 7, 9 and 12 at `ho-process/hos/ho-03-panel.md:73`, line 99 and line 115. `Hotkey.register` makes the system calls specified at that document's line 107.

2. Unrequired types, functions or branches: none. The requirement map covers the added source, the changed Run behavior and their tests. The temporary unbounded transcript is explicitly authorized at `ho-process/hos/ho-03-panel.md:103`; the five-second undismissable launch interval is the practitioner's recorded choice at `ho-process/hos/ho-03.2-fix-pass.md:43` and line 81.

   | Code | Requirement |
   |---|---|
   | `Sources/Issoku/App.swift:7`: delegate, entry, accessory policy, launch capture and reopen | `ho-process/hos/ho-03-panel.md:51` and line 55, Decisions 2–3 |
   | `Sources/Issoku/App.swift:37`: immediate/deferred termination, Quit guard and Settings window | `ho-process/hos/ho-03-panel.md:123` and line 125; `ho-process/hos/ho-03.2-fix-pass.md:58` and line 77 |
   | `Sources/Issoku/Panel.swift:14`: state, initialization, stream consumers, capture notice and error reasons | `ho-process/hos/ho-03-panel.md:55`, line 65 and line 103; failure-notice timing at line 311 |
   | `Sources/Issoku/Panel.swift:24`: submission handle, one dismiss rule, show/dismiss/toggle and clearing | `ho-process/hos/ho-03-panel.md:59`, line 65, line 69 and line 156; `ho-process/hos/ho-03.2-fix-pass.md:36` through line 41 |
   | `Sources/Issoku/Panel.swift:108`: typed/blank/offered submit, launch await, sizing, single submission and start-failure branches | `ho-process/hos/ho-03-panel.md:55` and lines 93–99; whitespace ruling at line 308; `ho-process/hos/ho-03.1-fix-pass.md:89`; `ho-process/hos/ho-03.2-fix-pass.md:38` |
   | `Sources/Issoku/Panel.swift:130`: Stop counter, interrupt/kill and keystroke write/stop/paste/ignore | `ho-process/hos/ho-03-panel.md:73` through line 89, Decisions 7–8 |
   | `Sources/Issoku/Panel.swift:155`: notices, Terminal resolution/open, Quit submission wait and bounded Done wait | `ho-process/hos/ho-03-panel.md:55`, line 109, line 115 and line 125; `ho-process/hos/ho-03.2-fix-pass.md:40` and line 75 |
   | `Sources/Issoku/Panel.swift:182`: enter/apply, controls, status/alarm, focus, clearing and cursor | `ho-process/hos/ho-03-panel.md:65`, line 73, lines 97–103 and line 160; status wording at line 311; submission handoff at `ho-process/hos/ho-03.2-fix-pass.md:38` |
   | `Sources/Issoku/Keystrokes.swift:7`: Action and modifier/key/printable branches | `ho-process/hos/ho-03-panel.md:77` through line 89, Decision 8 |
   | `Sources/Issoku/Hotkey.swift:6`: combination, display name, handler/references, register/install failure, unregister and status text | `ho-process/hos/ho-03-panel.md:107` and line 210; `ho-process/hos/ho-03.1-fix-pass.md:58` |
   | `Sources/Issoku/PanelWindow.swift:9`: panel initialization/style/layout/hairlines, placement, terminal size, fitting and text-change handling | `ho-process/hos/ho-03-panel.md:59`, line 61 and lines 93–95; collection behavior at line 311; shared metrics at `ho-process/hos/ho-03.1-fix-pass.md:56` |
   | `Sources/Issoku/PanelWindow.swift:92`: editing equivalents, Escape/resignKey, newline dispatch and Retry/Stop/Open/gear selectors | `ho-process/hos/ho-03-panel.md:69` through line 99, line 123 and line 165; resignKey choice at line 306 |
   | `Sources/Issoku/TranscriptPlaceholder.swift:8`: text-view initialization/required overrides, keyDown/paste, append, cursor drawing/redraw and metrics | `ho-process/hos/ho-03-panel.md:77` through line 89, line 103 and line 160; `ho-process/hos/ho-03.1-fix-pass.md:56` |
   | `Sources/Issoku/SettingsWindow.swift:7`: titled notice window | `ho-process/hos/ho-03-panel.md:109` and line 123, Decisions 11 and 13 |
   | `Sources/IssokuCore/Run/Run.swift:229`, line 279 and line 301: consumption acknowledgment, held Done and iterator-held count; removed start-time ceiling check | `ho-process/hos/ho-03.1-fix-pass.md:43` through line 48 and execution ruling at line 91; retained ceiling/draining contract at `ho-process/hos/ho-02.1-fix-pass.md:43` |
   | `Tests/IssokuTests/PanelTests.swift:10`, `Tests/IssokuTests/KeystrokesTests.swift:8`, `Tests/IssokuTests/HotkeyTests.swift:9`: fixtures, gates, process witnesses and tests | `ho-process/hos/ho-03-panel.md:206` through line 224 and Decisions 17–18 at lines 156–160; `ho-process/hos/ho-03.1-fix-pass.md:41` through line 58 and lines 89–95; `ho-process/hos/ho-03.2-fix-pass.md:45` through line 50 and lines 77–79 |
   | `Tests/IssokuCoreTests/RunTests.swift:35`, line 69 and line 423: concurrent drain helper, held-Done and backpressure regressions | `ho-process/hos/ho-03.1-fix-pass.md:48`, line 71 and line 91 |
   | `scripts/coverage-floor.sh:63`: measured app set, named exclusions and failing exit below the floor | `ho-process/hos/ho-03-panel.md:129`, Decision 14 |

3. N1 identifies the cursor and Terminal tests' limits at `Tests/IssokuTests/PanelTests.swift:360` and line 554. Run-2 M1 is answered: `Sources/Issoku/Panel.swift:114` sets the submission handle before its task can suspend, and only Running at line 186 or start failure at lines 120 and 123 clears it, so the dismiss rule at line 28 covers both gaps named by run 2. The launch-gate test at PanelTests line 406 and the yield/50 ms regression at line 432 passed in both test runs; the latter also checks the owned process group after Stop. Quit-in-flight at line 539 asserts reaped SIGKILL and independently checks for living children, as settled at `ho-process/hos/ho-03.2-fix-pass.md:77`; the delegate's guard at `Sources/Issoku/App.swift:38` reads the same rule, though the delegate itself is excluded from automated coverage.

   Run-1 M2 and the three Should-fix findings remain answered: the held-Done regression at `Tests/IssokuCoreTests/RunTests.swift:442`, the 65,536-byte Panel regression at `Tests/IssokuTests/PanelTests.swift:476`, the gated launch test at line 385 and the readiness-held submit/offer tests at lines 178 and 300 passed. The coverage run also passed the 8 MiB delayed-consumer test at RunTests line 423 and the 65-command regression at line 468. No Panel test substitutes a mock for Run or PanelWindow; the fake ssh is the local executable the spec requires.

   Other specified behavior without an automated test: actual Escape/resignKey routing (`Sources/Issoku/PanelWindow.swift:100` and line 105); Control-C and Command-V through the responder chain (`Sources/Issoku/TranscriptPlaceholder.swift:56` and line 80); Retry button dispatch, typed-command precedence and whitespace-only Return with an offer (`Sources/Issoku/PanelWindow.swift:182`, `Sources/Issoku/Panel.swift:109`); Shift-/Option-Return, composing editing equivalents and five-line input scrolling (`Sources/Issoku/PanelWindow.swift:92`, line 130 and line 159); screen placement, height cap and terminal-size measurement (lines 112–155); start-error presentation and release of the submission guard after start failure (`Sources/Issoku/Panel.swift:119`); hotkey-failure presentation and delegate-driven Quit/reopen (`Sources/Issoku/App.swift:20`, line 32, line 37 and line 48). Hotkey firing and the Dock icon's absence are witnessed only by the practitioner's run sheet at `ho-process/hos/ho-03-panel.md:333`. That run sheet also witnesses password input, dismissal/Stop, Quit, Terminal opening and multiline entry at lines 336–341, with cursor confirmation at line 313; reopen proof is deferred to ho-06 at line 319 and the Character Viewer conflict remains unobserved on this machine at line 342.

4. none. The source/test files, coverage change and process-document/roster updates are authorized at `ho-process/hos/ho-03-panel.md:135`, lines 180–202 and line 359; the driver/product deletion is authorized there and excluded from this review. Run source/test changes are opened by `ho-process/hos/ho-03.1-fix-pass.md:64` and line 71, while the second fix pass names Panel, PanelTests and App at `ho-process/hos/ho-03.2-fix-pass.md:56` through line 58. `Package.swift:20` retains an empty dependency list; no additional setting, flag or feature lacks a requirement.

5. N2: the environment, process-table reader, survivor polling and sudo fixture text at `Tests/IssokuTests/PanelTests.swift:18`, line 23, line 36 and line 140 duplicate the core test target. The transcript font/line height have one definition at `Sources/Issoku/TranscriptPlaceholder.swift:19`, read by `Sources/Issoku/PanelWindow.swift:33`, line 58 and lines 114–147; the shortcut display name has one definition at `Sources/Issoku/Hotkey.swift:10`, read at line 50 and `Sources/Issoku/App.swift:49`. A second stored representation of Composing/Running/Done: none.

6. Unexplained force unwraps, lint suppressions or concurrency annotations: none. The decoding suppression is justified at `Sources/Issoku/Panel.swift:58`, the Carbon main-thread assertion at `Sources/Issoku/Hotkey.swift:54`, and Run's dispatch-queue isolation at `Sources/IssokuCore/Run/Run.swift:31` and line 78. The four comments named by run-1 M3 are absent at `Sources/Issoku/App.swift:12`, `Sources/Issoku/PanelWindow.swift:210`, `Sources/Issoku/SettingsWindow.swift:8` and `Sources/Issoku/TranscriptPlaceholder.swift:84`; the practitioner's ruling limits that trim to those comments at `ho-process/hos/ho-03.1-fix-pass.md:24` and line 50. The submission comment at `Sources/Issoku/Panel.swift:22` explains its changed lifetime and the dismissal gap it closes.

7. `Sources/Issoku/Panel.swift:56` requires three other files to establish output-before-Done: `Sources/IssokuCore/Run/Run.swift:301` acknowledges the previous chunk on the next pull and line 280 gates Done; `Sources/Issoku/TranscriptPlaceholder.swift:84` appends synchronously; `Sources/Issoku/PanelWindow.swift:130` lays out synchronously before the next pull. A consumer that stops pulling, including one that drops an iterator while holding a chunk, prevents Done and another start; this is the accepted consequence at `ho-process/hos/ho-03.1-fix-pass.md:91`. For the lifecycle fix, Panel's submission assignment at line 114, Running handoff at line 186 and Quit wait at line 173 must also be read with Run's start at `Sources/IssokuCore/Run/Run.swift:118` and the delegate guard at `Sources/Issoku/App.swift:38`.

## Ho-specific questions

- State representations: one stored `RunState?` at `Sources/Issoku/Panel.swift:14`; a second representation: none. The local `running`, `exit` and `offer` values at lines 196–204 are derived, the Stop counter at line 21 records interruption attempts, and `showsCursor` at `Sources/Issoku/TranscriptPlaceholder.swift:14` is the required view property. The submission at Panel line 24 is the in-flight task handle authorized at `ho-process/hos/ho-03.2-fix-pass.md:36`; visibility is read from the window at Panel line 100.
- SwiftUI in the panel window: none. `Sources/Issoku/PanelWindow.swift:1` and `Sources/Issoku/TranscriptPlaceholder.swift:1` use AppKit; the unchanged SwiftUI color accessors at `Sources/Issoku/Theme.swift:57` install no SwiftUI view in the panel.
- Dismiss rule: one `canDismiss` at `Sources/Issoku/Panel.swift:28`, read by `dismissIfAllowed()` at line 91 and by the Quit guards at line 174 and `Sources/Issoku/App.swift:38`. Escape, click-out and the hotkey reach it through `Sources/Issoku/PanelWindow.swift:100`, line 105, line 169 and `Sources/Issoku/Panel.swift:99`; its submission check covers Return through delivery of Running.
- Hotkey registration: direct `InstallEventHandler` and `RegisterEventHotKey` at `Sources/Issoku/Hotkey.swift:27` and line 32, inside the specified registration function. An additional wrapper, protocol, instance manager or dependency: none.

## Verdict

Pass
