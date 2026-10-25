---
created: 2026-10-25
status: complete
type: ho-document
project: issoku
ho: "00"
kamae: 5
shape: orientation
title: Orientation — scaffold the package and the verification stack
description: Brings the Issoku repository into existence with the Swift verification stack enforcing itself, the design tokens in place, and the first local commit.
builds-on:
  - kamae-1-issoku-seed
  - kamae-2-issoku-system-design
  - README.md
  - kamae-4-issoku-ho-overview
model: claude-opus-5-5
---

# ho-00 — Orientation

This session makes the repository exist. At the end of it `swift build` and `swift test` pass on targets that hold no application code, a commit cannot land without passing format, lint, and compile, the eight colour tokens from pālana's design system sit in a Theme file with their dark siblings, and the Kamae chain is committed in its canonical places. No application code. No icon. No remote.

The scaffold is the only thing in this ho that an agent executes. Everything else here is framing: the concepts the build meets for the first time, the shape the project's hos take, and what ho-01 needs on opening.

---

## 1. Pre-conditions

Verified 2026-10-25 at session start:

- `~/.claude/` carries the operating discipline, `languages-swift.md`, and the six Swift baselines in `~/.claude/templates/`.
- Toolchain on this machine: Swift 6.4 (Xcode), swift-format 602, SwiftLint 0.65.0, pre-commit at `~/.local/bin/pre-commit`, `codex` on the path.
- The Kamae chain is on disk at `ho-process/`: seed, System Design, ho overview, x-ho template. README at the root.
- The directory is not a git repository.
- pālana is checked out beside this project; its `Sources/Palana/Theme.swift` holds the light and dark token values and its `scripts/coverage-floor.sh` is the coverage script this ho adapts.

---

## 2. New concepts

The stack is Swift 6, AppKit, POSIX, and SwiftPM. The parts of it that pālana and Sharibako already exercised are not here: SwiftPM multi-target packages, swift-format and SwiftLint, swift-testing, llvm-cov coverage, SwiftUI inside AppKit, Developer ID signing and notarisation. What follows is the territory the seed's section 11 names as new, ordered by the ho that first meets it. Strike anything already known.

- **Pick-up-in-flight** — read the primer, learn while using.
- **Pre-read** — read the resource before opening the ho that uses it.

### Pseudoterminals and the controlling terminal — *pre-read, ho-01*

A pseudoterminal is a pair of file descriptors the kernel joins back to back: the child process sees the slave end as a real terminal, and the parent reads and writes the master end as if it were the keyboard and screen. Programs such as `sudo` and `ssh` ask the kernel "do I have a terminal?" and behave differently when the answer is no, which is why a plain pipe cannot run the remote `sudo` case. A process gets a *controlling* terminal only when it starts a new session (`setsid`) and then opens the slave; without that step `sudo` still reports no terminal even though one is attached. ho-01's first decision is exactly this sequence from Swift. Resource: Linus Åkesson, *The TTY demystified* (https://www.linusakesson.net/programming/tty/), then `man 4 pty` and `man 2 setsid` on this machine.

### Process groups and signal delivery — *pre-read, ho-01*

Interrupt and Stop must reach everything the command started, not only the shell that started it. The unit the kernel offers for that is the process group: the child is placed in its own group at spawn, and `killpg` delivers `SIGINT` or `SIGKILL` to every member at once. The remote side is a separate question. Killing the local `ssh` closes the connection, and the remote shell receives a hangup from its own terminal, so a remote process that ignores `SIGHUP` can outlive the panel. The orphan check in ho-01 looks at both process tables for this reason. Resource: `man 2 killpg`, `man 2 setpgid`; the signal chapter of Stevens and Rago, *Advanced Programming in the UNIX Environment*, if a longer treatment is wanted.

### termios and echo — *pick-up-in-flight, ho-01*

The terminal's line discipline is a set of flags on the slave end (`termios`). The one that matters here is `ECHO`: when `sudo` reads a password it clears the flag on *its* terminal, which on the remote host is the one `ssh -tt` allocated, so the characters never come back over the connection. Issoku never inspects the flag. The System Design relies on the behaviour, and ho-01 confirms it by watching the bytes that arrive. Resource: `man 4 termios`.

### Spawning from Swift 6 under strict concurrency — *pre-read, ho-01 and ho-02*

The POSIX calls that set up a PTY and a process group (`posix_openpt`, `posix_spawn` with its attribute set, or `fork` plus `exec`) are C functions. Swift reaches them through the `Darwin` module and the values they hand back are raw file descriptors and process ids, which are plain integers and cross actor boundaries freely. The concurrency friction shows up around the read loop: a `FileHandle` or `DispatchIO` delivering bytes on a background queue into an actor that owns the transcript. Swift 6's strict checking refuses anything that is not `Sendable` crossing that line, and the answer is to move bytes as `Data`, never the handle itself. Resource: Swift.org, *Migrating to Swift 6* (https://www.swift.org/migration/documentation/migrationguide/), the sections on isolation boundaries and `Sendable`.

### Login-shell environment capture — *pick-up-in-flight, ho-02*

A GUI process on macOS starts with launchd's environment, not the shell's: no Homebrew path, no `SSH_AUTH_SOCK` from the user's config, none of the exports in `.zprofile`. Run captures the real environment once by executing the login shell non-interactively and asking it to print its variables, then hands that dictionary to every spawn. Which shell invocation, which variables are kept, and what Refresh Environment does mid-command are ho-02's decisions. Resource: `man zsh`, the *Startup/Shutdown Files* section, for the order in which `.zshenv`, `.zprofile`, and `.zshrc` are read.

### Non-activating panels in AppKit — *pre-read, ho-03*

An ordinary window brings its application to the front when it appears, which moves keyboard focus away from whatever the user was doing. `NSPanel` with the `.nonactivatingPanel` style mask takes keyboard input without activating the app, which is how Spotlight-shaped surfaces behave. The panel floats above other windows at a chosen level, can be made to hide when it loses key status, and is the only AppKit facility the System Design names as the reason SwiftUI cannot own the window. Resource: Apple, *NSPanel* (https://developer.apple.com/documentation/appkit/nspanel), with attention to `styleMask`, `level`, and `becomesKeyOnlyIfNeeded`.

### System hotkey registration — *pick-up-in-flight, ho-03*

The call that registers a global keyboard shortcut without Accessibility permission is `RegisterEventHotKey`, which lives in the Carbon event framework and is still supported. It takes a key code and modifier mask, returns a reference, and fails with a status code when the combination is already owned; that status is the conflict signal the System Design asks Panel to report. The shortcut library the System Design rejected wraps this same call. Resource: Apple, *Carbon Event Manager* reference for `RegisterEventHotKey`; `man 3 Carbon` is not useful, so read the header `HIToolbox/CarbonEvents.h` in the SDK directly.

### Agent apps and the bundle Issoku assembles — *pick-up-in-flight, ho-03 and ho-06*

An app with no Dock icon and no menu bar by default is an *agent* app: `LSUIElement` set to true in its `Info.plist`. SwiftPM does not write an `Info.plist`; the bundle is assembled by script, as pālana does it, and that script is where the key goes. The same script is where the ho-06 signing and notarisation steps attach. Resource: Apple, *LSUIElement* (https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement); pālana's `scripts/build_macos.sh` for the bundle assembly.

### Terminal control sequences — *pick-up-in-flight, ho-04*

Programs that colour their output or draw progress bars do it with byte sequences the terminal interprets: an escape, a bracket, some parameters, a letter. The subset the System Design commits to is the colour family (SGR, ending in `m`) and the carriage return, which moves the cursor to the start of the line so the next bytes overwrite. Everything else is stripped. The complete grammar is large; ho-01 measures how much of it the real command set emits, and ho-04 implements only what that list needs. Resource: the XTerm control sequence reference (https://invisible-island.net/xterm/ctlseqs/ctlseqs.html), the *CSI* and *SGR* sections only.

---

## 3. Project ho shape

Decisions about how this project's hos are written and run, set here so no later ho re-decides them.

- **Build hos are ha-shaped.** ho-01 through ho-06 each carry a Think phase; the overview lists the decisions each resolves. ho-01's Think phase is short because the spike's questions are already written; its findings document is the Reflect phase.
- **x hos are shape `x`.** Authored by filling `ho-process/x-ho-template.md`, no Think phase, run in Codex, reports to `ho-process/reviews/`. The template's notes section is the authority on the `run` and `model` fields.
- **One subagent per build ho, briefed with the ho document itself.** The per-ho document is the subagent's instruction. Separate agent task files under `ho-process/agent-tasks/` appear only when a ho decomposes into disjoint-file pieces; none is expected before ho-03.
- **Models.** Build subagents run `claude-opus-5-5`. The orchestrator runs `claude-fable-5-1`. The antagonist's exact Codex model id is recorded in each x ho's frontmatter at authoring time.
- **The ho-process directory is public; the State Memory is not.** `ho-process/` is committed with the code, as the overview decided. The one exception is `ho-process/kamae-6-issoku-state-memory.md`, which is gitignored: it is the hot working register, and it stays on this machine. The cold record (git, each ho's close, the overview's build record) is the public trail.
- **Commits.** One commit per ho close, message `ho-NN: <title>`, lower case after the colon, no trailers. Fix passes commit as `ho-NN.1: <what was fixed>`. The hash of each ho's opening and closing commit is recorded in the overview's build record.
- **Coverage.** The floor is 90% line coverage on `IssokuCore`, enforced by `scripts/coverage-floor.sh`. The app target `Issoku` is excluded from the floor with a comment in the script naming that its views cannot be driven headless. The Theme palette in the app target is tested anyway through its pure `resolved(dark:)` seam. Whether an application-logic floor is added, as pālana did at 35%, is a ho-03 decision.

---

## 4. The scaffold

The subagent's whole instruction. Files are created exactly as listed; nothing else is touched. Placeholders in the baselines are filled with the values given. Where a baseline and this section disagree, this section wins.

### Files to create

| Path | Source | Notes |
|---|---|---|
| `Package.swift` | `~/.claude/templates/Package.swift.baseline` | Package `Issoku`. Products: library `IssokuCore`, executable `Issoku`. Targets: `IssokuCore`, `Issoku` (depends on `IssokuCore`), `IssokuCoreTests`, `IssokuTests` (depends on `Issoku`). `platforms: [.macOS(.v14)]`, `swiftLanguageModes: [.v6]`, strict-concurrency setting on every non-test target per the baseline. No dependencies. Delete the commented-out CLI target and the dependency comments. |
| `.swift-format` | `~/.claude/templates/swift-format.baseline.json` | Verbatim. |
| `.swiftlint.yml` | `~/.claude/templates/swiftlint.baseline.yml` | Verbatim except: `warning_threshold: 1` (SwiftLint 0.65 reports "exceeded threshold of 0" at zero warnings, and `--strict` already makes every warning an error), and `trailing_comma`, `pattern_matching_keywords`, `extension_access_modifier` added to `disabled_rules`, each commented with the swift-format rule it contradicts. pālana carries the same three. |
| `.pre-commit-config.yaml` | `~/.claude/templates/pre-commit.swift.baseline.yaml` | Verbatim. |
| `.gitignore` | `~/.claude/templates/gitignore.swift.baseline` | Verbatim. `prompts/` is already ignored by the baseline; `ho-process/` and `metadata/` are tracked and stay out of the file. Append under "Project-specific": `ho-process/kamae-6-issoku-state-memory.md` with the comment "State Memory (Kamae 6): the hot working register stays local; the cold record is the build record", and `design/` with the comment "icon sources and design docs, not part of the build". |
| `LICENSE` | — | MIT, `Copyright (c) 2026 Andrew Todd Marcus`. The standard text, unchanged. |
| `CLAUDE.md` | `~/.claude/templates/project-CLAUDE.template.md`, shaped like pālana's | Content specified below. |
| `scripts/coverage-floor.sh` | Adapted from `palana/scripts/coverage-floor.sh` | Specified below. Executable bit set. |
| `Sources/IssokuCore/IssokuCore.swift` | Setup skill's Swift seed | `public enum IssokuCore { public static let version = "0.0.0" }` with a one-line `///` doc on each. The version string is the one ho-06's update checker compares against a release tag. |
| `Sources/Issoku/App.swift` | — | A `@main enum IssokuApp` whose `static func main()` is empty, with a `//` comment: "ho-03 replaces this with the AppKit application entry." Nothing else in the file. |
| `Sources/Issoku/Theme.swift` | Adapted from `palana/Sources/Palana/Theme.swift` | Specified below. |
| `Tests/IssokuCoreTests/IssokuCoreTests.swift` | Setup skill's Swift smoke suite | swift-testing. One test: `IssokuCore.version` is non-empty. |
| `Tests/IssokuTests/ThemeTests.swift` | — | Specified below. |
| `ho-process/reviews/.gitkeep` | — | Empty. |
| `ho-process/hos/` | — | Exists; this document lives in it. |
| `ho-process/agent-tasks/.gitkeep` | — | Empty. |
| `ho-process/kamae-6-issoku-state-memory.md` | Setup skill, step 7 | Frontmatter per the skill; the state-summary block is filled by the orchestrator at close, so the subagent writes the block with the skill's placeholder text. |
| `metadata/ho-status.md`, `metadata/ho-status.json` | Setup skill, step 8 | Seeded empty per the skill. `project: issoku`, overview path `ho-process/kamae-4-issoku-ho-overview.md`. |

Not created: `README.md` (exists, is Kamae 3, untouched this ho), `.env.example` (the app reads no environment of its own), `Package.resolved` (no dependencies, SwiftPM writes none), `Makefile`, any `xcode/` directory, any icon.

### `Theme.swift`

pālana's file, cut to what Issoku's System Design names. The header comment states that the light values are copied from `palana/design/palana-design-system.md` §2 and the dark values from pālana's `Sources/Palana/Theme.swift` (its ho-15 port of Sharibako's dark mode), and that pālana is the source of truth for both.

Keep from pālana:

- `RGBA` with `red`, `green`, `blue`, `alpha` and the `nsColor` accessor. Drop `over(_:)` and `luminance`; no Issoku requirement reads them.
- `Palette` with `light`, `dark`, `resolved(dark:)`, `nsColor` (the dynamic `NSColor(name:)` provider), and `color`.
- `enum Theme` with exactly eight `static let` `Color` accessors: `ground`, `groundDeep`, `ink`, `inkFaint`, `accent`, `panelGround`, `alarm`, `plugin`. Each resolved once into a `let`, as pālana's comment explains. Each `///` doc is one line from the design system's "Use" column.
- `enum Theme.Token` with the same eight `Palette` values, light and dark components copied digit for digit from pālana.

Drop from pālana: `paneShade`, `paneEdge`, `caretRest`, the `font(_:weight:design:)` factory and its `TypeScale` dependency, the `import PalanaCore`. Imports are `AppKit` and `SwiftUI` only.

Every declaration carries an explicit access modifier. Nothing is `public`; the app target is its own consumer.

### `ThemeTests.swift`

swift-testing, `@testable import Issoku`. Three tests, parameterised over the eight tokens where the form allows:

1. Each token's light value matches the design system's hex, row by row, each channel within half an 8-bit step (0.002) of the hex-derived value. The expected values are written from the design-system table (`#FAF7F3`, `#F4F1EA`, `#1D1B18`, `#1D1B18` at 0.55, `#5A7552`, `#EDEEF1`, `#984D3C`, `#945C2E`), not read back from `Token`. The tolerance exists because pālana writes `plugin` to two decimals (0.58, 0.36, 0.18) and the design-system table carries both those digits and the hex; both are kept as written.
2. `resolved(dark: true)` returns the `dark` member and `resolved(dark: false)` the `light` member, for every token.
3. No dark value is pure black or pure white: for every token, the dark `RGBA` has at least one channel strictly between 0.05 and 0.95. This is the design system's "never pure white, never pure black" rule.

No test asserts the dark values digit for digit; those are pālana's numbers and pālana's tests pin them.

### `scripts/coverage-floor.sh`

pālana's script reduced to one floor.

- Takes one optional argument, the floor, default 90.
- Assumes `swift test --enable-code-coverage` has run. Profdata at `.build/debug/codecov/default.profdata`. Swift 6.4 builds one test bundle per target, so the script collects every `.build/debug/*.xctest/Contents/MacOS/*` binary and passes the first positionally and the rest as `-object`.
- Measures `Sources/IssokuCore` only: `-ignore-filename-regex='(Tests/|\.build/|Sources/Issoku/)'`.
- A header comment states that `Sources/Issoku`, the surface, is excluded because its views cannot be driven headless, that the Theme palette is tested through `resolved(dark:)` regardless, and that adding an application-logic floor is a ho-03 decision.
- Prints the `llvm-cov report` table, then the percentage and the floor, and exits non-zero below the floor. When no files are measured it says so and exits zero: `IssokuCore` holds only a string constant until ho-02, and the practitioner accepted a vacuous pass for that interval. ho-02 turns the empty set into a failure, as pālana has it.
- No `REQUIRED_APP_FILES` machinery; there is one set and nothing to require.

### `CLAUDE.md`

Sections, in order:

1. Title `# Issoku 一息` and the README's one-line description.
2. `## Languages` — `@~/.claude/modules/languages-swift.md`.
3. `## Reading order for a fresh session` — K6 state memory, README, K2, K4, the current ho in `ho-process/hos/`.
4. `## Verification rhythm` — the five commands: `swift-format lint --recursive --strict Sources Tests`, `swiftlint lint --strict`, `swift build`, `swift test`, `swift test --enable-code-coverage && scripts/coverage-floor.sh`. The floor is stated: 90% on `IssokuCore`.
5. `## Kokoroe` — pālana's four lines verbatim: the spec is the authorization; verify by command, not by assertion; halt on surprise; propose, don't decide.
6. `## Hard rules (Issoku-specific)`:
   - The System Design's decisions are closed. A question it does not answer stops the work.
   - Every build ho from ho-01 is reviewed by an x ho. The reviewer is Codex, in a fresh session, from `ho-process/hos/ho-NNx-review-of-<title>.md`. No reviewer subagents run inside Claude Code.
   - The Kamae 5 skill authors `shape: x` documents from `ho-process/x-ho-template.md`; the template is the authority until it moves into the skill.
   - Tests never touch live hosts. The ho-01 spike runs against real hosts only with the practitioner driving and only the commands its spec lists.
   - No AI attribution in commits, PRs, or code. No `Co-Authored-By`, no "Generated with". Strip any template that adds one.
   - No dependencies in `Package.swift` at v1. A dependency is an architectural question for the practitioner.
   - No secrets in the repository. `ho-process/` is public; only the State Memory (`kamae-6-issoku-state-memory.md`) is gitignored.
7. `## Project structure` — `IssokuCore` (library, headless: Run and the Transcript model), `Issoku` (executable: Panel, Transcript view, Theme, Memory UI), SwiftPM only, bundle assembled by script at ho-06, `prompts/` gitignored.
8. `## Ho process` — the canonical paths: `ho-process/kamae-1-issoku-seed.md`, `ho-process/kamae-2-issoku-system-design.md`, `README.md`, `ho-process/kamae-4-issoku-ho-overview.md`, `ho-process/hos/`, `ho-process/kamae-6-issoku-state-memory.md`, `ho-process/agent-tasks/`, `ho-process/reviews/`, `ho-process/x-ho-template.md`.
9. `## References` — the design system at `../palana/design/palana-design-system.md`, pālana as the layout and pipeline lineage, the Ho System repo.

No other sections. No rules the documents above do not already state.

### Rules for the subagent

- No commits. The orchestrator commits.
- No files outside the table. No edits to `README.md` or anything under `ho-process/` except the three paths listed.
- No dependencies.
- If a baseline conflicts with the toolchain (a swift-format option the 602 release rejects, a SwiftLint rule 0.65 does not know), halt and report the exact message. Do not change the baseline to make it pass.
- Report back with every file written and the full output of each verification command below.

### Verification

Run from the repository root, in this order:

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
swift test --enable-code-coverage && scripts/coverage-floor.sh
```

The orchestrator then runs, after `git init -b main` and `pre-commit install`:

```bash
pre-commit run --all-files
```

and the refusal check: a file `Sources/IssokuCore/Bad.swift` containing `let  x=1` is written, `pre-commit run --all-files` is run and must fail on swift-format, and the file is deleted. The output is recorded in the Handoff.

### Done means

- All five verification commands pass with the exact output recorded.
- `pre-commit run --all-files` passes on the clean tree and fails on the misformatted file.
- `git status` after the commit shows a clean tree, with `prompts/`, `.DS_Store`, and the State Memory absent from the index.
- One commit on `main`: `ho-00: orientation — scaffold the package and the verification stack`, containing the scaffold and the Kamae chain, no trailers.
- The closing hash is recorded in the build record as ho-01's opening hash.

---

## 5. Handoff

**ho-01 opens on** the ho-00 closing commit, in a repository whose hooks refuse an unformatted file. Its spec is authored ha-shaped against the overview's six decisions. The spike's code lives under `spike/` at the repository root, outside `Sources/`, so the hooks' `Sources Tests` scope does not lint throwaway code and the package does not build it. Whether `spike/` is committed or kept only in the findings document is ho-01's first Think decision.

**Deferred from this ho:**

- An application-logic coverage floor on `Sources/Issoku`. ho-03, when the first non-view logic lands in the app target.
- The `swift build` hook versus `swift build --target Issoku`. pālana switched to the target build to dodge a swift-driver incremental bug on Swift 6.2.4. ho-00 ships the baseline's plain `swift build`; if the stale `@main` link error appears during any commit, the hook changes and the change is recorded in that ho's Reflect.
- README's Development section still reads "build instructions appear here with the first code." It is updated as a Kamae 3 update at ho-02, when there is code worth building.
- The coverage script's empty-set pass. ho-02 makes an empty measured set a failure.
- The SwiftLint baseline in `~/.claude/templates/swiftlint.baseline.yml` carries the three rules that contradict swift-format and the `warning_threshold: 0` that SwiftLint 0.65 cannot satisfy. Fixing the baseline is practitioner-scope work, outside this repository.

**Refusal check transcript:** run at close under the Xcode 26 toolchain (`xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`), with the ho-00 paths staged and `Sources/IssokuCore/Bad.swift` containing `let  x=1` staged alongside them.

```text
$ pre-commit run
trim trailing whitespace.................................................Passed
fix end of files.........................................................Passed
check yaml...............................................................Passed
check json...............................................................Passed
check for added large files..............................................Passed
check for merge conflicts................................................Passed
detect private key.......................................................Passed
swift-format lint........................................................Failed
- hook id: swift-format
- exit code: 1

Sources/IssokuCore/Bad.swift:1:4: error: [Spacing] remove 1 space
Sources/IssokuCore/Bad.swift:1:7: error: [Spacing] add 1 space
Sources/IssokuCore/Bad.swift:1:8: error: [Spacing] add 1 space

swiftlint --strict.......................................................Failed
- hook id: swiftlint
- exit code: 2

Sources/IssokuCore/Bad.swift:1:7: error: Operator Usage Whitespace Violation: Operators should be surrounded by a single whitespace when they are being used (operator_usage_whitespace)

swift build (type-check).................................................Passed
```

Exit 1. `Bad.swift` was then removed from the index and the tree; the same `pre-commit run` without it passed every hook. The full stack before the check: `swift-format lint --recursive --strict Sources Tests` exit 0, `swiftlint lint --strict` exit 0, clean `swift build` complete, `swift test` 4 tests in 2 suites passed, `scripts/coverage-floor.sh` reported IssokuCore has nothing to measure and exited 0.

One finding from the stack itself: the `end-of-file-fixer` hook added the missing final newline to `ho-process/kamae-1-issoku-seed.md`. Whitespace only; restaged.

Two things found during this ho that the Xcode toolchain resolved: with `xcode-select` pointing at the Command Line Tools, SwiftLint 0.65 crashed loading sourcekitd and swift-testing's `TestingMacros` plugin failed to load intermittently. Both went away once the developer directory was switched to `/Applications/Xcode.app/Contents/Developer` and the licence accepted. The verification rhythm assumes that toolchain from here on.

### Closing this ho

Flip `status: complete`. Write the state-summary block to `ho-process/kamae-6-issoku-state-memory.md`. Append the entry to the overview's build record with the closing hash. Refresh `metadata/ho-status.md` and `metadata/ho-status.json` by hand. The block, verbatim labels and order:

**STATE-SUMMARY**
- **COMPLETED** — ho-00. The Swift package (IssokuCore, Issoku, two test targets), the verification stack (swift-format, SwiftLint, pre-commit, coverage floor script), Theme with the eight pālana tokens in light and dark, MIT licence, project CLAUDE.md, State Memory, ho-status roster. Full stack green under the Xcode toolchain; the hooks refuse a misformatted file.
- **NEXT** — ho-01, the spike. Author its spec ha-shaped with the Kamae 5 skill; the practitioner approves before any subagent runs.
- **ACTION ITEMS / BLOCKS** — the developer directory must stay on Xcode. The SwiftLint baseline template fix is practitioner-scope. `resources/messages.MD` sits untracked at the repository root; the practitioner decides whether and where it is committed. Deferred items above.
- **PROJECT LIFECYCLE** — kamae

---

_Authored: 2026-10-25._
_Execution: one Opus subagent for section 4; orchestrator for git, hooks, the refusal check, and the commit._
