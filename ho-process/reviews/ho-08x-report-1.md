# ho-08x report, run 1

Commit range: 3b0c944..45c10a1
Build: pass (debug and release; all six VM commands exit 0)
Tests: 300 passed, 0 failed in each run (229 app + 71 core; normal and coverage runs)
Coverage: HitoikiCore 95.76%; Sources/Hitoiki 98.35% (coverage script's measured files)

Role: independent reviewer; ho-review mode; pass 1 of 2. No implementation or builder deliberations were supplied to this reviewer. The review context is `ho-process/hos/ho-08x-review-of-the-first-launch.md` at `fb5a20b10ff623c55627cb47426b778b67491687`.

Governing skill: Ho System commit `552fb4a49857f03b11fe2a5a4360d6e255614b8d`, subdirectory `skills/ho-antagonist-review`, tree `37ad44698f7e95f6002470a788829753aa9af156`. The complete package is recoverable from that Git tree. The installed package differs; this review used the pinned instructions through `git show`. The context's report format, two-verdict rule and single-file boundary supersede the skill's general format and separate-handoff requirement.

Reviewed endpoints: `3b0c944fb19e6e41ce811b79f670995df51ba82d` and `45c10a12a7f8fccc0367169cabbe4f4c362f0bc9`. The verification checkout is `fb5a20b10ff623c55627cb47426b778b67491687`; its only committed difference from the endpoint is the review context. Sources, tests, package, scripts and build configuration match the endpoint. The pre-existing `.keisaku.json` modification is outside the reviewed range.

Binding rulings: the AppKit face is assessed against the stated appearance and behavior, not About's use of SwiftUI; actual `SMAppService` delivery of the login-item mark remains unverified by ruling; the K2 amendment and test-title correction are authorized additions and are assessed only for truth.

## Findings

### Must fix

- none

### Should fix

- none

### Note

- **N1 — evidence limit:** `Tests/HitoikiTests/WelcomeWindowTests.swift:25` calls `app.welcome` directly, so the launch tests would still pass if the production call at `Sources/Hitoiki/App.swift:89` were removed. This is a confirmed static limit under brief question 3: the tests witness the welcome routine and real windows, while inspection establishes its connection to the launch callback. They do not witness an application launch or a process quit/restart; `firstLaunch` constructs a second delegate over the same store at `Tests/HitoikiTests/WelcomeWindowTests.swift:154`. No listed partition at the routine boundary is missing, and the required production call is present, so this is not a demonstrated behavior defect. Any later claim of end-to-end first-launch verification needs an actual launch witness; the release run sheet at `ho-process/hos/ho-08-the-first-launch.md:100` remains unperformed here.
- **N2 — comment accuracy:** `Sources/Hitoiki/WelcomeWindow.swift:6` says that nothing else on screen indicates the app is running, although the menu bar item is now enabled before the welcome appears (`Sources/Hitoiki/App.swift:83`, `Sources/Hitoiki/Settings.swift:142`). This is a confirmed minor documentation inconsistency under brief question 6; removing or qualifying that clause would make the comment agree with Decision 4 without changing behavior.

## Brief questions

1. **Which abstraction has one implementation?** None introduced in production. The test-only `Launch` wrapper (`Tests/HitoikiTests/WelcomeWindowTests.swift:12`) assembles a real `Fixture` and `HitoikiApp`, forwards the welcome call and centralizes teardown; its `settings` and `suite` properties forward to that fixture at lines 21–22. Its purpose is the repeated launch-state tests in spec lines 79–83, rather than a new production service layer. No protocol, generic abstraction or dependency was added.

2. **Which code has no requirement behind it?** None. The changed declarations and branches trace as follows; test helpers support inspection and operation of the real components required by spec lines 75–83.

   | Changed code | Requirement |
   |---|---|
   | `Sources/Hitoiki/App.swift:18`, `:115` — window ownership, once guard, key write, login branch | Spec lines 49–51, Decisions 2–3 |
   | `Sources/Hitoiki/App.swift:70`, `:89`, `:94` — launch event, call and mark reader | Spec lines 49–51 |
   | `Sources/Hitoiki/App.swift:119` — status, shortcut and menu setting passed to the window; panel/settings callbacks and activation | Spec lines 36–47 |
   | `Sources/Hitoiki/Settings.swift:55`, `:185` — eleventh key and direct defaults access | Spec lines 49, 80 |
   | `Sources/Hitoiki/Settings.swift:139` — absent-on menu default, retained stored value | Spec lines 53, 81 |
   | `Sources/Hitoiki/WelcomeWindow.swift:16`, `:37` — window, initialization, retained buttons and actions | Spec lines 36–47 |
   | `Sources/Hitoiki/WelcomeWindow.swift:76`, `:93` — one/two buttons and registered/default/failure text branches | Spec lines 40, 43, 45 |
   | `Sources/Hitoiki/WelcomeWindow.swift:81`, `:111`, `:117` — Escape and button actions | Spec line 47 |
   | `Sources/Hitoiki/WelcomeWindow.swift:124`, `:173` — ordered face, icon, wrapping labels and theme attributes | Spec lines 36–43 |
   | `Tests/HitoikiTests/WelcomeWindowTests.swift:12`, `:46`, `:51` — launch fixture, visible-window count and event fixture | Spec lines 79–80; Decision 3 |
   | `Tests/HitoikiTests/WelcomeWindowTests.swift:66`, `:72`, `:81`, `:89`, `:96`, `:102` — text/view inspection, button dispatch and Escape event | Spec lines 82–83 |
   | `Tests/HitoikiTests/WelcomeWindowTests.swift:118` — independent shortcut, error and text expectations | Spec lines 40–45, 82 |
   | Changed Settings and MenuBarItem tests | Spec lines 69, 80–81; invariant map below |

3. **Which test only confirms the implementation's assumptions?** N1 identifies the unexercised launch connection. None of the new tests is merely a mock of the welcome component: text is read from the laid-out window, button actions reach the actual panel/settings windows, and key assertions read the defaults domain (`Tests/HitoikiTests/WelcomeWindowTests.swift:72`, `:96`, `:146`, `:301`, `:318`). The literal expectations are independently stated requirements rather than values read back from production constants. The `loginMark` fixture tests reading a supplied event, not whether macOS supplies that event (`Tests/HitoikiTests/WelcomeWindowTests.swift:205`); that latter limit is ruled out of acceptance. Actual Return-key dispatch, screen centering, foreground activation and icon rendering are not exercised by these tests; the source sets the corresponding properties/calls, while the tests inspect default-button key equivalents and window width/title-bar properties at lines 234–239 and 272–273.

4. **Where did the ho exceed its spec?** None beyond the additions explicitly accounted for in the review context. The K2 amendment is `ho-process/kamae-2-hitoiki-system-design.md:156`; the title-only correction is `Tests/HitoikiTests/SettingsWindowTests.swift:187`. The range also adds the build specification itself, as planned by `ho-process/hos/ho-08-the-first-launch.md:112`. No additional feature, key, flag, configuration format or package dependency appears.

5. **What is duplicated?** No duplicated persistent state. Escape handling at `Sources/Hitoiki/WelcomeWindow.swift:81` repeats `Sources/Hitoiki/AboutWindow.swift:30`; the width, icon size and name styling at WelcomeWindow lines 48, 128 and 132 repeat AboutWindow lines 14, 50 and 53, as Decision 1 requests. The 360-point width appears again at WelcomeWindow line 167, and its 304-point text width at line 18 incorporates the two 28-point margins at line 149. Required display strings recur as independent expectations in `Tests/HitoikiTests/WelcomeWindowTests.swift:123`, `:224`, `:251`, `:267`, rather than a second runtime source of truth. None requires a finding under the pinned skill's consequential-complexity standard.

6. **What is unexplained?** N2 is the inaccurate comment. No new force unwrap, lint suppression or concurrency-warning escape hatch appears; `@MainActor` scopes the AppKit operations and callbacks. Mechanical comments include the Return assignment at `Sources/Hitoiki/WelcomeWindow.swift:65`, face ordering at `:122`, and direct window/key assertions at `Tests/HitoikiTests/WelcomeWindowTests.swift:147`, `:149`, `:200`; they restate the adjacent operation but introduce no additional defect. The activation and test-serialization comments explain their reasons at `Sources/Hitoiki/App.swift:127` and `Tests/HitoikiTests/WelcomeWindowTests.swift:127`.

7. **What would you need to read to understand this?** The launch path requires `Sources/Hitoiki/App.swift:67`, the persisted guard in `Sources/Hitoiki/Settings.swift:185`, and the face/actions in `Sources/Hitoiki/WelcomeWindow.swift:37`. Understanding the view's external values also requires `Sources/Hitoiki/Shortcut.swift:175` for symbol formatting and `Sources/Hitoiki/Theme.swift:52` for appearance-aware colors. The Change the Shortcut path continues through `Sources/Hitoiki/App.swift:155` to the existing origin/close rule at `Sources/Hitoiki/SettingsWindow.swift:79`; Open Hitoiki reaches `Sources/Hitoiki/Panel.swift:125`. These are the existing component boundaries used by the diff, with no new indirection finding.

## Ho-specific questions

- **Is each decision built as written?** Departures: none. Exact strings and the decision-to-code comparison are below; line numbers under Spec refer to `ho-process/hos/ho-08-the-first-launch.md`.

  | Decision / requirement | Spec | Implementation |
  |---|---|---|
  | 360-point width, theme ground, transparent title bar, background movability, centering, forcing activation | 36 | `Sources/Hitoiki/WelcomeWindow.swift:48`, `:54`, `:55`, `:56`, `:71`, `:167`; `Sources/Hitoiki/App.swift:128` |
  | `Welcome to Hitoiki`; 92-point icon; `Hitoiki is running`, About's 18-point semibold style | 36–39 | `Sources/Hitoiki/WelcomeWindow.swift:52`, `:125`–`:132`; comparison: `Sources/Hitoiki/AboutWindow.swift:47`–`:54` |
  | `Press ⌃⌘Space to open it from any app.`; accent symbols; faint `(Control-Command-Space)` only for the default | 40 | `Sources/Hitoiki/WelcomeWindow.swift:93`–`:107`; `Shortcut.displayName` supplies the current combination |
  | Both exact menu bar sentences, selected by stored/default setting | 41 | `Sources/Hitoiki/WelcomeWindow.swift:133`–`:139`; `Sources/Hitoiki/App.swift:122` |
  | `In the panel, ⌘, (Command-comma) opens Settings.` | 42 | `Sources/Hitoiki/WelcomeWindow.swift:141` |
  | `Open Hitoiki` alone and default on success; failure text with attempted symbols, `Change the Shortcut` added and default on any nonzero status | 43–45 | `Sources/Hitoiki/WelcomeWindow.swift:46`, `:57`–`:66`, `:95`–`:100`; `Sources/Hitoiki/App.swift:121` |
  | Open/Change close first and show the intended surface; Escape/close show nothing | 47 | `Sources/Hitoiki/WelcomeWindow.swift:81`–`:86`, `:111`–`:119`; `Sources/Hitoiki/App.swift:123`–`:125` |
  | Once, including quit while open and an upgrade with no key | 49 | `Sources/Hitoiki/Settings.swift:55`, `:185`–`:190`; `Sources/Hitoiki/App.swift:116`–`:129` |
  | Read only the open-application event's login-item mark, write true and suppress the welcome | 51 | `Sources/Hitoiki/App.swift:70`, `:94`–`:99`, `:117`–`:118` |
  | Menu bar absent=true, stored false=false, stored true=true | 53 | `Sources/Hitoiki/Settings.swift:139`–`:144`, `:218`–`:219` |

- **Does the window show exactly once?** No duplicate or skipped first manual showing was found in the inspected paths. Absent/false plus not-at-login reaches the window after writing true; absent plus marked login writes true and returns; true returns before any write (`Sources/Hitoiki/App.swift:116`–`:129`). Quitting with the welcome still open does not undo that write, and a later delegate reads the same persisted setting (`Sources/Hitoiki/Settings.swift:185`). Reopen shows only the panel (`Sources/Hitoiki/App.swift:134`); Settings, About and Check for Updates use their existing windows (`:155`, `:176`, `:187`). The sole production call and window construction are at App.swift lines 89 and 119; neither close nor button action calls them. This is source tracing plus the routine-level tests, subject to N1 and the explicit login-delivery ruling.

- **Do the tests establish the spec's invariants?** No named partition is missing at the tested component boundary. Each row identifies the witness and the incorrect behavior its assertions distinguish; N1 limits the application-lifecycle claim.

  | Spec invariant | Test and location | Distinguishing witness |
  |---|---|---|
  | Absent key, manual launch; also stored false | `firstLaunch`, `Tests/HitoikiTests/WelcomeWindowTests.swift:136` | Visible welcome, exactly one welcome, persisted true and no extra key; another delegate over the store has no welcome |
  | Absent key, login launch | `firstLaunchAtLogin`, same file `:161` | No welcome or panel, persisted true |
  | True key, login and manual launch | `laterLaunches`, same file `:174` | No welcome, true retained, key set unchanged in both partitions |
  | No other path opens the welcome | `noOtherPath`, same file `:190` | Settings, About, Check for Updates and reopen leave no visible/owned welcome and do not write its key; call-site inspection covers the production connections |
  | Eleventh key; no writes outside the list | `keyList`, `eachWritesItsKey`, `roundTrip`, `Tests/HitoikiTests/SettingsTests.swift:100`, `:106`, `:128`; `firstLaunch:148` | Independently enumerated key set, exact domain after each write, and value read through a second defaults/store instance |
  | Menu absent/on, false/off, true/on | `menuBarDefault`, `Tests/HitoikiTests/SettingsTests.swift:88`; `followsSetting`, `Tests/HitoikiTests/MenuBarItemTests.swift:24` | Three stored-value partitions; real status item exists immediately for absent key, disappears and reappears on changes |
  | Registered default shortcut | `registeredDefault`, `Tests/HitoikiTests/WelcomeWindowTests.swift:217` | Exact ordered text, symbols' accent, single button and Return equivalent |
  | Registered recorded shortcut | `registeredRecorded`, same file `:243` | Recorded symbols, no spelled-out line, single button |
  | Unregistered shortcut | `notRegistered`, same file `:257` | Default and recorded attempted symbols, exact failure text, no spelled-out line, both buttons and only Change has Return |
  | Menu bar on/off wording | `menuBarLine`, same file `:278` | Correct sentence present and opposite sentence absent for each setting |
  | Open Hitoiki | `openHitoiki`, same file `:294` | Welcome hidden, real panel visible, settings absent for successful and failed registration |
  | Change the Shortcut | `changeTheShortcut`, same file `:310` | Welcome hidden, real settings visible with nil origin, panel hidden |
  | Escape and close | `escapeAndClose`, same file `:325` | Both actions hide the welcome without opening panel/settings |

  `loginMark` (`Tests/HitoikiTests/WelcomeWindowTests.swift:205`) additionally distinguishes the marked open event from no mark, a service-item mark, a reopen event and nil. It does not claim the ruled-out system delivery test.

  **Against `3b0c944`: static comparison only, not a second execution.** The new welcome suite cannot compile against that endpoint because `WelcomeWindow`, `welcome`, `welcomeWindow` and `launchedAtLogin` do not exist there; changed Settings tests also refer to the absent `welcomeShown` property. At the assertion level, `menuBarDefault`'s absent-key expectation and `followsSetting`'s immediate-item requirement contradict the old false default, and `keyList` contradicts the old ten-key enumeration. The added welcome tests distinguish their individual incorrect branches as mapped above, but no baseline or mutation-test run was authorized or performed.

- **Does any document claim more than the code does?** None in the reviewed document changes. `README.md:21`, `:39` match `Sources/Hitoiki/App.swift:115` and `Sources/Hitoiki/Settings.swift:139`. `TECHNICAL.md:34`, `:38`, `:91`, `:114` match the same code and the welcome face/actions; its login exception is explicit. `packaging/release-notes-1.0.1.md:3`, `:5` match the welcome/error/menu paths, and lines 7, 9 and 11 retain the corresponding distribution, privacy and README sentences from the 1.0.0 notes as spec line 71 requires. The unchanged platform/dependency declarations and update-request implementation support those inherited source claims (`Package.swift:8`, `:20`; `Sources/Hitoiki/UpdateCheck.swift:116`), without establishing that a 1.0.1 artifact has been signed or published. The K2 amendment at `ho-process/kamae-2-hitoiki-system-design.md:156` matches App.swift lines 94–129 and Settings.swift lines 139–144; the test-title correction matches the eleven-key enumeration. N2 concerns a source comment, not these documents.

- **Does anything else change?** None under Sources, Tests, Package.swift or scripts outside the declared unit and authorized title correction. The range contains 12 files, 792 insertions and 21 deletions; Package.swift and scripts are unchanged. Inspection of the diff and commit messages found no credential, private hostname, personal absolute home path, private address or attribution line introduced for publication; the website/repository links are the intended public product links. `.keisaku.json` is outside the range and was left alone.

## Verification

Ran `scripts/vm-test.sh` once from the repository root, without arguments or `--skip`. It exited 0 after 528 seconds, including guest startup, copy and shutdown. Log: `.build/vm-test/20261119T221639Z.log`; verification ran inside the headless Tart guest `hitoiki-test`, with test output reporting Testing Library 2084 and target platform `arm64e-apple-macos14.0`. The final log reports `vm-test: all six green` and that the guest stopped.

| Step | Command inside the guest | Exit | Seconds |
|---|---|---|---|
| 1 | `swift-format lint --recursive --strict Sources Tests` | 0 | 5 |
| 2 | `swiftlint lint --strict` | 0 | 69 |
| 3 | `swift build` | 0 | 51 |
| 4 | `swift test` | 0 | 167 |
| 5 | `swift test --enable-code-coverage && scripts/coverage-floor.sh` | 0 | 199 |
| 6 | `swift build -c release` | 0 | 7 |

Both test-target completion lines for step 4, from log lines 733 and 1019:

```text
Test run with 229 tests in 14 suites passed after 40.417 seconds.
Test run with 71 tests in 4 suites passed after 93.222 seconds.
```

Both test-target completion lines for step 5, from log lines 1681 and 1967:

```text
Test run with 229 tests in 14 suites passed after 38.110 seconds.
Test run with 71 tests in 4 suites passed after 121.952 seconds.
```

Both coverage results from the script:

```text
HitoikiCore line coverage: 95.76% over 5 files (floor: 90%)
Sources/Hitoiki line coverage: 98.35% over 13 files (floor: 90%)
```

The app percentage uses the script's existing nine-file exclusion list, including `App.swift`; it is not whole-application coverage. `WelcomeWindow.swift` is included and reports 99.26% line coverage. No failed test, compiler error, lint violation or unsatisfied-constraint diagnostic was reported; no retry was run. The application was not launched, no host Swift build/test or packaging command was run, no secret file was opened, and no Git remote was touched.

Before staging, `git status --porcelain` showed exactly the expected tracked modification and the new report:

```text
 M .keisaku.json
?? ho-process/reviews/ho-08x-report-1.md
```

The contents of the pre-existing, tool-owned `.keisaku.json` changed during the review; the reviewer did not edit or stage it. All 12 reviewed files were compared byte-for-byte with `45c10a1`, and executable inputs were checked against that endpoint. The only reviewer-authored repository file is this report; the VM log is an authorized ignored output.

Pass 1 closes this review cycle with zero Must-fix findings and the two Notes above. No repairs, additional reviewer pass or builder dispatch were performed. The report alone is authorized for commit; release, merge and owner acceptance remain separate acts.

## Verdict

Pass
