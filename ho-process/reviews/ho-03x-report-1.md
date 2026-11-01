# ho-03x report, run 1

Commit range: f371d87b18d101c5c9ea46bcace9ed3102939067..ed9ee98d83920ccb8df345206f19372eb7185f68
Build: pass — `swift build`, exit 0; `Build complete! (13.43 sec)`.
Tests: 60 passed, 0 failed — `swift test`, exit 0; 21 IssokuTests and 39 IssokuCoreTests.
Coverage: IssokuCore 93.65% over 4 files; Sources/Issoku 92.28% over 4 files — `swift test --enable-code-coverage` and `scripts/coverage-floor.sh`, both exit 0; both floors are 90%.

The reviewed source, tests, package and coverage script match the closing commit in the current checkout. Supplemental local probes interpreted the existing source definitions through Swift's standard input with the application entry disabled, constructed hidden windows, and wrote no source, test or fixture files. No remote host was contacted, and the hidden-running probe killed its owned command and verified its process group empty with `/bin/ps`.

## Findings

### Must fix

- M1 — `Sources/Issoku/Panel.swift:109` — A submitted command survives dismissal while it awaits the launch task, then starts with the window hidden. With a 500 ms launch task, `submit("sleep 30")` followed by `dismissIfAllowed()` left `state == nil` and `canDismiss == true` before the wait, then produced `.running` with `window.isVisible == false`; `/bin/ps` confirmed the live sleep in its owned group. Dismissal at lines 87–92 neither invalidates the submission nor keeps its surface present, violating the System Design's lifecycle rule at `ho-process/kamae-2-issoku-system-design.md:86` and the seed's no-background-command requirement at `ho-process/kamae-1-issoku-seed.md:356`. Ensure a dismissed submission cannot subsequently start a hidden command, without adding a second representation of panel state.

- M2 — `Sources/Issoku/Panel.swift:53` — The independent byte and state consumers allow Done and dismissal to overtake displayed output, so old output repopulates a cleared Composing panel. In a fresh local probe, `sleep 0.1; head -c 65536 /dev/zero | tr '\000' x`, with the main actor occupied for 300 ms after Running, reached Done with only 1,024 bytes displayed; dismissal cleared it to zero, then 64,512 queued bytes appeared while `state` remained nil and the window stayed hidden. The unconditional append at line 58 continues after the clear at line 91, and the same consumer also crosses subsequent command boundaries. This violates the clean-dismissal requirement at `ho-process/hos/ho-03-panel.md:156`; make output completion and clearing agree at the command boundary, preserving every chunk required by Decision 10 at line 103.

- M3 — `Sources/Issoku/PanelWindow.swift:212` — Mechanical comments narrate the statements beneath them despite the explicit prohibition at `ho-process/hos/ho-03-panel.md:238`. The layout inventory here, `Sources/Issoku/App.swift:12` ("Runs the application with this delegate"), `Sources/Issoku/SettingsWindow.swift:8` ("A titled window holding `text`"), and `Sources/Issoku/TranscriptPlaceholder.swift:83` ("Appends `text` and scrolls to the end") describe operations already visible in the code. Delete these narrations and audit the remaining comments by the same rule; retain explanations of requirements, ownership, framework constraints and non-obvious choices. This answers brief question 6.

### Should fix

- S1 — `Tests/IssokuTests/PanelTests.swift:365` — The launch-wait test can pass without establishing that submission awaited the launch task, because its clock starts before fixture construction and it only checks elapsed time after observing Running or Done. Slow window construction or delayed observation can consume the entire 300 ms even if the await is removed. Assert completion of the supplied launch task at the point execution becomes observable, and cover dismissal during that wait as M1 demonstrates. This is the assumption-only-test debt prohibited by `ho-process/kamae-1-issoku-seed.md:452` and concerns Decision 3 at `ho-process/hos/ho-03-panel.md:55`.

- S2 — `Tests/IssokuTests/PanelTests.swift:89` — `trace()` samples state after `Task.yield()` and therefore cannot guarantee observing every transition, although its callers require exactly three samples at lines 172 and 300. A correct short command can enter Running and Done between observations; the comment's claim that sampling happens after each main-actor job is unsupported. Give the command an observable readiness point and hold it until the test has asserted Running, as the existing Stop and no-echo tests already do. This is test scheduling debt under the seed's inspectable-behavior requirement at `ho-process/kamae-1-issoku-seed.md:314`, also acknowledged at `ho-process/hos/ho-03-panel.md:327`.

- S3 — `Sources/Issoku/PanelWindow.swift:22` — The transcript font and its geometry are independently defined here and at `Sources/Issoku/TranscriptPlaceholder.swift:18`, so terminal rows/columns and the cursor can drift from the text being displayed. `terminalSize` uses the window's font and line height at lines 115–119 while the text and cursor use the placeholder's separate font and metrics at lines 18–25. Read transcript measurements from the actual transcript font/layout when this seam is changed, keeping one definition of the rendering rule. This answers brief question 5 and follows the seed's tight-code requirement at `ho-process/kamae-1-issoku-seed.md:298`.

### Note

- N1 — `Tests/IssokuTests/PanelTests.swift:343` — The cursor test checks `showsCursor` and the stored string, so it still passes if `TranscriptPlaceholder.draw(_:)` draws nothing; actual drawing is outside this test's evidence. Likewise, `terminalResolves()` at line 423 queries NSWorkspace directly and does not exercise `Panel.openInTerminal()`, while the other Panel tests primarily call controller methods instead of routing UI events. Keep these boundaries explicit when assessing coverage: the four view/delegate files are deliberately excluded by Decision 14 at `ho-process/hos/ho-03-panel.md:129`, and the practitioner witnessed the cursor and Terminal opening in Reflect at lines 313 and 338. Automated coverage of the remaining specified UI behaviors is listed under brief question 3.

- N2 — `Sources/Issoku/App.swift:50` — The fixed shortcut's display name is embedded separately in the registered message here and in the failure message at `Sources/Issoku/Hotkey.swift:48`. Keep the display name beside `Hotkey.combination` when editing this seam so both messages track the same shortcut. The independently written expected name in `Tests/IssokuTests/HotkeyTests.swift:20` is a specification assertion. This answers brief question 5; the fixed combination and both messages are required by `ho-process/hos/ho-03-panel.md:107` and line 123.

- N3 — `Tests/IssokuTests/PanelTests.swift:23` — The process-table reader and survivor polling duplicate `Tests/IssokuCoreTests/RunTests.swift:76` and line 89; the owned environment at PanelTests line 18 also duplicates RunTests line 26. The sudo clause is separately embedded at PanelTests line 129 while the core test reads `Tests/IssokuCoreTests/Fixtures/sudo-no-terminal.txt` through RunTests line 175. Check both suites when changing these rules or fixture text, since they occupy separate test targets. This answers brief question 5; local fixtures and process-table witnesses are required by `ho-process/hos/ho-03-panel.md:206` and lines 216–220.

## Brief questions

1. none. No added protocol with one conformer, generic over one type, or discretionary forwarding layer was found. The selectors at `Sources/Issoku/PanelWindow.swift:184`, line 190 and line 195 bridge AppKit target/action into the controller required by Decisions 7, 9 and 12; `Hotkey` is the namespace for Decision 11's direct calls.

2. No unrequired product type, function or branch: none. The requirement map below covers the added types and method/branch groups; M1 and M2 concern incorrect behavior within required code, and M3 concerns unrequired narration.

   | Code | Requirement in `ho-process/hos/ho-03-panel.md` |
   |---|---|
   | `Sources/Issoku/App.swift:7`: delegate, `main`, launch, accessory policy, reopen | Decisions 2–3, lines 51–55 |
   | `Sources/Issoku/App.swift:38`: immediate/deferred termination; `showSettings` and retained settings window | Decision 13, lines 123–125 |
   | `Sources/Issoku/Panel.swift:14`: state, `canDismiss`, initialization, byte/state consumers, capture notice and `reason` cases | Decisions 3, 5, 10, lines 55, 65, 103; failure notice on task completion recorded at line 311 |
   | `Sources/Issoku/Panel.swift:78`: show, dismiss, toggle, clearing on dismissal | Decisions 4, 6, 17, lines 59, 69, 156 |
   | `Sources/Issoku/Panel.swift:103`: blank/typed/offered submit, launch await, sizing, start-error branches | Decisions 3 and 9, lines 55, 93–99; whitespace ruling at line 308 |
   | `Sources/Issoku/Panel.swift:123`: Stop counter and interrupt/kill; keystroke write/stop/paste/ignore | Decisions 7–8, lines 73–89 |
   | `Sources/Issoku/Panel.swift:148`: notices, Terminal resolution/open, bounded Quit wait | Decisions 3, 11–13, lines 55, 109, 115, 125 |
   | `Sources/Issoku/Panel.swift:174`: enter/apply, clearing, controls, status/alarm, focus, cursor | Decisions 5, 7, 9–10, 18, lines 65, 73, 97–103, 160; status wording at line 311 |
   | `Sources/Issoku/Keystrokes.swift:7`: Action, modifier/key-code branches, printable filter | Decision 8's table and pure function, lines 77–89 |
   | `Sources/Issoku/Hotkey.swift:6`: combination, callback/references, register/install failure, unregister, statusText | Decision 11, lines 107–111; unregister test at line 210 |
   | `Sources/Issoku/PanelWindow.swift:9`: NSPanel, initialization/layout/style/hairlines, placement, terminalSize, fit, text-change handling | Decisions 4 and 9, lines 59–61, 93–95; collection behavior recorded at line 311 |
   | `Sources/Issoku/PanelWindow.swift:94`: editing equivalents, Escape/resignKey, newline dispatch, Retry/Stop/Open/gear selectors | Decisions 6–9 and 13, lines 69–99, 123; editing discovery at line 165; resignKey choice at line 306 |
   | `Sources/Issoku/TranscriptPlaceholder.swift:8`: NSTextView initialization/required overrides, keyDown/paste, append | Decisions 8 and 10, lines 77–89, 103 |
   | `Sources/Issoku/TranscriptPlaceholder.swift:14`: showsCursor, metrics, drawing/redraw branches | Decision 18, line 160 |
   | `Sources/Issoku/SettingsWindow.swift:7`: retained titled notice window | Decisions 11 and 13, lines 109, 123 |
   | `Tests/IssokuTests/KeystrokesTests.swift:8`, `HotkeyTests.swift:9`, `PanelTests.swift:10`: table cases, registration test, local fixtures/polling and controller tests | Tests at lines 206–224; Decisions 17–18 tests at lines 156 and 160 |
   | `scripts/coverage-floor.sh:63`: second measured set, named exclusions and failure result | Decision 14, line 129 |

3. S1 (`Tests/IssokuTests/PanelTests.swift:365`) can pass with the required await absent; S2 (`Tests/IssokuTests/PanelTests.swift:89`) assumes a sampling schedule; N1 (`Tests/IssokuTests/PanelTests.swift:343`) would pass without cursor drawing. No added controller test substitutes a mock for Run or PanelWindow: the fake ssh exercises the real Run through a local executable, as the spec requires. There is no test for pending-submit dismissal (M1) or Done/dismissal with queued output (M2); the dismissal test at PanelTests line 324 waits for its small output before dismissing.

   Other specified behavior without an automated test: actual Escape/resignKey event routing (`Sources/Issoku/PanelWindow.swift:102`); Control-C and Command-V through the responder chain (`Sources/Issoku/TranscriptPlaceholder.swift:55`); Retry button dispatch and typed-command precedence over an offer (`Sources/Issoku/PanelWindow.swift:184`, `Sources/Issoku/Panel.swift:105`); whitespace-only Return with an offer; Shift-/Option-Return, composing editing equivalents, and five-line input scrolling (`Sources/Issoku/PanelWindow.swift:94`, line 132 and line 161); screen placement, half-screen output cap and terminal-size measurement (lines 114–153); start-error presentation (`Sources/Issoku/Panel.swift:114`); hotkey failure presentation in both windows and delegate-driven Quit/reopen (`Sources/Issoku/App.swift:21`, line 33, line 38 and line 49). The hotkey actually firing and the Dock icon's absence are witnessed only by the practitioner's run sheet at `ho-process/hos/ho-03-panel.md:331`; they are not untested claims. Terminal opening, keystroke/password behavior and multiline entry also have run-sheet evidence at lines 334, 338–339, the cursor has the later confirmation at line 313, reopen is explicitly deferred to ho-06 at line 319, and the Character Viewer conflict remains unobserved on this machine at line 340.

4. none. The seven source files, three tests, coverage change, driver/product deletion and process-document/roster updates are all named at `ho-process/hos/ho-03-panel.md:135`, lines 180–202 and line 357. `Package.swift:20` still has an empty dependency list, and no IssokuCore source or test changed. Decisions 17–18, the five-commit range, whitespace-only retry and the directory argument are authorized in the spec and its Reflect at lines 154–160, 292–309.

5. S3: transcript font/metrics at `Sources/Issoku/PanelWindow.swift:22` and `Sources/Issoku/TranscriptPlaceholder.swift:18`. N2: shortcut display name at `Sources/Issoku/App.swift:50` and `Sources/Issoku/Hotkey.swift:48`. N3: environment/process-table helpers and sudo fixture text at `Tests/IssokuTests/PanelTests.swift:18`, line 23, line 36 and line 129. There is no second stored panel-state representation; see the ho-specific answers.

6. M3: narration at `Sources/Issoku/PanelWindow.swift:212`, `Sources/Issoku/App.swift:12`, `Sources/Issoku/SettingsWindow.swift:8` and `Sources/Issoku/TranscriptPlaceholder.swift:83`. Unexplained force unwraps, lint suppressions and concurrency annotations: none. The decoding suppression has its reason at `Sources/Issoku/Panel.swift:55`, and the Carbon main-thread assertion has its reason at `Sources/Issoku/Hotkey.swift:52`; UI isolation and the pure nonisolated status function follow their actual execution boundaries.

7. M2 requires reading `Sources/Issoku/Panel.swift:53` together with three other files: `Sources/IssokuCore/Run/Run.swift:280` and line 295 establish that Done publication and byte consumption have separate schedules; `Sources/Issoku/TranscriptPlaceholder.swift:84` appends unconditionally; `Sources/Issoku/PanelWindow.swift:132` performs layout for every chunk. Reading only the controller's state transition misses the outstanding output that can arrive after its clear. No additional intermediary abstraction needs to be removed.

## Ho-specific questions

- State representations: one stored `RunState?` at `Sources/Issoku/Panel.swift:14`; none beyond it. The local `running`, `exit` and `offer` values in `apply` at line 187 are derived, and `showsCursor` at `Sources/Issoku/TranscriptPlaceholder.swift:14` is the explicitly required view property from Decision 18. The Stop counter at Panel line 21 records interruption attempts, and visibility is read from `window.isVisible` at line 97.
- SwiftUI in the panel window: none. `Sources/Issoku/PanelWindow.swift:1` and `Sources/Issoku/TranscriptPlaceholder.swift:1` use AppKit; the existing SwiftUI color accessors in unchanged `Sources/Issoku/Theme.swift:57` do not install a SwiftUI view in the panel.
- Dismiss rule: one `canDismiss` at `Sources/Issoku/Panel.swift:25`, read by `dismissIfAllowed()` at line 88. Escape, resignKey and hotkey reach it through `Sources/Issoku/PanelWindow.swift:102`, line 107, line 171 and `Sources/Issoku/Panel.swift:98`; M1 concerns the pending submission outside the running state, not a second dismiss calculation.
- Hotkey: direct `InstallEventHandler` and `RegisterEventHotKey` at `Sources/Issoku/Hotkey.swift:25` and line 30, within the required `register` function. An additional wrapper, protocol, instance manager or dependency: none.

## Verdict
Return
