---
created: 2026-10-24
status: active
type: ho-overview
project: issoku
stage: kamae-4
kamae-chain: seed → system-design → readme → **ho-overview**
builds-on: kamae-2-issoku-system-design, kamae-3 README.md
next: ho-00 (kamae-5 authoring)
---

# Issoku — Ho Overview

Seven build hos in five phases, ho-00 through ho-06, each build ho from ho-01 on followed by a review ho that carries an x: ho-01x, ho-02x, and so on. Thirteen hos in all. The overview commits to the order, the phase boundaries, the decisions each ho resolves, the review that closes each build ho, and the two points where the plan is re-examined before continuing.

## What this is, and what it is not

This is the build's map. It sequences the architecture the System Design committed to, places each deferred decision with the ho that resolves it, places an adversarial review after every build ho, and marks where to stop and look before going on. It is not a contract and not a per-ho specification. Each ho gets its own document at authoring time, written as a dandori spec against this map. Hos split, insert, and reorder as the work shows what it needs; the numbering scheme exists for that. This document is edited as the build proceeds. The build record at the end is not; it only grows.

The System Design's provisional sequence is the starting material here. It survives intact. Two things are added: the phase grouping, which makes the two checkpoints visible, and the x hos, which make the seed's section 12 enforceable rather than aspirational. The seed asks for less unnecessary code, more understanding of what exists, and no claims of correctness without evidence. The x hos are where a second model, with no stake in the code it is reading, checks each of those against the diff.

## The x hos and the antagonist

Every build ho from ho-01 onward is followed by a review ho with the same number and an x suffix. The build ho is not closed until its x ho passes. The x ho is run by a different model from the one that built the code, in a fresh session, with no shared context. For this project the antagonist is Codex. It receives three things: the build ho's dandori spec, the diff between the commit that opened the ho and the commit that closed it, and the standing brief below. It reads the seed's section 8 as its rubric. It does not fix anything. It reports.

### The antagonist brief

You are reviewing one bounded unit of work against the specification that bounded it. You did not write this code and you have no reason to defend it. Your output is a list of findings and a verdict. You change no files.

Read, in this order: the project seed's section 8 (Constraints) and section 12 (What I Want to Learn); the ho's dandori spec; the diff. Then run the build and the tests yourself and record whether they pass. Do not take the builder's word for it.

Answer these questions, each with file and line references or the word "none":

1. **Which abstraction has one implementation?** A protocol with one conformer, a generic with one instantiation, a layer that forwards to exactly one thing. Name it and name what it is wrapping.
2. **Which code has no requirement behind it?** For each type, function, or branch, name the line in the spec or the seed that requires it. Anything you cannot trace is a finding.
3. **Which test only confirms the implementation's assumptions?** A test is suspect when it would still pass if the behaviour were wrong, when it asserts a value copied from the implementation, or when it tests a mock instead of the component. Also name any specified behaviour that has no test.
4. **Where did the ho exceed its spec?** Files touched outside the spec's file list. Features the spec did not ask for. Settings, flags, or configuration the spec did not name. A dependency added to Package.swift.
5. **What is duplicated?** The same state held in two places, the same rule written twice, the same string literal in more than one file.
6. **What is unexplained?** Force unwraps without a FORCE comment. Lint suppressions without a reason. Concurrency annotations that silence a warning rather than resolve it. Any comment that explains what the code does rather than why.
7. **What would you need to read to understand this?** If understanding one file requires holding three others in your head, say which.

Rate each finding: **Must fix** when it violates the spec or the seed's constraints; **Should fix** when it is debt the seed names; **Note** when it is a judgment the practitioner should see but may keep.

End with one of two verdicts. **Pass**: no Must-fix findings; the build ho closes. **Return**: one or more Must-fix findings; the build ho reopens for a fix pass, and this review runs again against the new diff.

Do not praise the code. Do not summarise what it does. Do not propose redesigns. Findings and a verdict.

### What an x ho's spec contains

The Kamae 5 skill authors each x ho's dandori spec from the template at `ho-process/x-ho-template.md`: the commit range, the path to the build ho's spec, the brief above pasted verbatim, and any ho-specific questions listed in that x ho's entry below. The spec's acceptance criterion is a written report at `ho-process/reviews/ho-NNx-report-<run>.md` and a verdict. A Return verdict produces a fix pass numbered as a decimal of the build ho (ho-02.1), and the x ho runs again with the run number advanced. The template is repo-local for now; it moves into the skill once the pattern has proven itself here.

## Phase structure

| Phase | Hos | What it produces |
|---|---|---|
| 0. Foundation | ho-00 | A scaffolded repo with the verification stack running and the design tokens in place |
| 1. The Process Model | ho-01, ho-01x, ho-02, ho-02x | A proven, tested way to run one command under a pseudoterminal, headless, reviewed |
| 2. The Surface | ho-03, ho-03x, ho-04, ho-04x | A usable app: shortcut, panel, run, read, dismiss, reviewed |
| 3. Memory | ho-05, ho-05x | Settings, macros, history, reviewed |
| 4. The Ship | ho-06, ho-06x | A signed, notarised release with updates, reviewed |

## Phase 0 — Foundation

The repo comes into existence with the verification stack already enforcing itself. Package.swift from the Swift baseline, swift-format and SwiftLint configured, pre-commit hooks installed, a project CLAUDE.md importing the Swift conventions, and the eight colour tokens from palana's design system copied into a Theme file. Nothing runs yet. At the end of the phase a commit cannot land without passing lint, and the next ho begins in a repo that already knows its standards. ho-00 has no x ho: it writes no application code, and the scaffold is checked by the hooks it installs.

*Release on phase complete: v0.0*

### ho-00 — Orientation

Scaffold the project with the project-environment setup skill. SwiftPM only, no Xcode project, matching palana. The Theme file carries palana's tokens with the attribution comment pointing at `palana/design/palana-design-system.md`. The git repo is initialised and the first commit is the scaffold alone. The remote under the no-kaji account is created when the practitioner says so; nothing is pushed until the build is done, and every local commit is kept. The seed, System Design, README, and this overview are committed in their canonical places.

**Depends on:** Nothing (this is the start).

**What's in scope:**
- Package.swift with an app target, a core target, and test targets, Swift 6 strict concurrency
- swift-format, SwiftLint, pre-commit, coverage script from the baselines
- Project CLAUDE.md importing `languages-swift.md`, naming Codex as the x-ho reviewer
- Theme.swift with palana's eight tokens
- `.gitignore` from the Swift baseline, `ho-process/` committed, `prompts/` ignored
- `ho-process/reviews/` created with a `.gitkeep`, for the x hos' reports

**What "done" means:**
- `swift build` and `swift test` pass on an empty-but-present target
- A deliberately misformatted file is refused by pre-commit
- First commit exists locally; no push until the practitioner says so

**What's out of scope:** Any application code. Any icon work.

## Phase 1 — The Process Model

The seed's directive was to prove the SSH/PTY process model before building any interface, and this phase does exactly that. ho-01 is a throwaway experiment: a command-line harness that spawns a command under a pseudoterminal, streams its output, forwards keystrokes, and kills it. It answers the questions the System Design could not answer from the desk. ho-01x checks the evidence, not the code, since the code is discarded. ho-02 then builds Run for real, from what the experiment taught, as a headless, fully tested component, and ho-02x is the first review of code that will ship. At the end of the phase there is still no window, but the hardest part of the app exists, is proven on real hosts, and has been read by a second model.

*Release on phase complete: v0.1*

### ho-01 — The Spike

A spike is a short, throwaway experiment built to answer specific technical questions. This one is a command-line program, not part of the app target, that opens a pseudoterminal, spawns the user's shell with a command line and a captured environment in a new process group, streams output to stdout, forwards stdin keystrokes, and responds to a signal by interrupting and then killing the group. It runs against the practitioner's real hosts: koan, tenzo, kanyo. Its code is not kept. Its findings are written into a findings document in the ho's folder and into ho-02's spec.

**Depends on:** ho-00.

**What's in scope:**
- The spawn path from Swift: PTY as controlling terminal, process group, environment
- Streaming, keystroke forwarding, interrupt, force-kill
- Measurement: latency, memory under large output
- A run of the practitioner's real command set through minimal terminal-control stripping
- A findings document with a recorded answer and evidence for every decision below

**What "done" means:**
- Every decision below has a recorded answer with evidence in the findings document
- ho-01x passes

**What's out of scope:** Reusable code. Any UI. Any error presentation beyond what the harness prints.

**Decisions required:**
- **Spawn mechanism**: which POSIX path gives a PTY that is the child's controlling terminal, in a new process group, with the captured environment, callable from Swift 6 with strict concurrency. Criterion: `ssh -tt koan 'sudo true'` prompts, a keystroke-typed password is accepted, nothing echoes, the command completes with status zero.
- **Process ownership**: interrupt reaches the whole group; a process that ignores it yields to force-kill; the process table shows no orphans afterwards, for a local command and for a remote `ssh` command.
- **Failure legibility**: unreachable host, rejected key, wrong sudo password each end with a status and a message the harness can distinguish.
- **Memory ceiling**: fifty megabytes of output stays within a fixed ceiling in the harness.
- **Latency**: measured time from spawn to first byte for local and remote `uptime`, recorded as numbers.
- **Terminal-control depth**: the real command set through colour-and-carriage-return handling only. A recorded list of any command whose output is unreadable. An empty list means Transcript never gets an emulator.

### ho-01x — Review of the Spike

The spike's code is discarded, so this review reads the findings document, not the diff. The antagonist's job is the seed's rule that no claim of correctness stands without evidence. For each of the six decisions it asks whether the recorded answer is supported by something it can see: a command transcript, a measurement, a process-table listing. An answer that says "works" with nothing behind it is a Return.

**Depends on:** ho-01.

**Ho-specific questions:**
- For each decision, is the evidence reproducible from what is recorded? Could the practitioner rerun it?
- Is the terminal-control list the result of running the real command set, or an assertion?
- Do the latency and memory numbers name the machine, the host, and the conditions?
- Does the findings document recommend anything the decisions did not ask for? If so, flag it as scope the spike is trying to smuggle into ho-02.

**Phase midpoint — replan checkpoint.** After ho-01x passes. The spike is the first contact with the stack. If the spawn mechanism costs more than the seed accepts, or the terminal-control list is not empty, the plan changes here before ho-02 commits. See Replan checkpoints.

### ho-02 — Run

Build the Run component from the spike's answers: environment capture at launch, launch under a PTY in a process group, a byte stream, a state stream, keystroke forwarding, interrupt, kill, exit status, and the `-tt` retry rule. Run is headless and depends on nothing else in the app. It is tested against a local sshd fixture where practical and against real hosts where not, and the tests are the specification of how a command lives and dies.

**Depends on:** ho-01x.

**What's in scope:**
- A Run type with `start`, `interrupt`, `kill`, a byte stream, a state stream
- Environment capture and Refresh Environment
- The sudo-message match and the `-tt` relaunch
- Tests to the 90% floor

**What "done" means:**
- The core interaction's steps 3 through 7 from the System Design pass as tests with no UI
- No orphan processes after any termination path, asserted by test
- ho-02x passes

**What's out of scope:** Rendering. Any window. Settings storage.

**Decisions required:**
- **Environment capture**: which shell invocation reads the login environment, which variables are kept, and that Refresh Environment waits while a command is running.
- **The sudo message**: the exact text matched for the retry offer, with sudo's real output as a test fixture, and the rule that the typed line must begin with `ssh ` and not already carry `-t`.

**Possible split:** if the retry rule or environment capture turns out larger than expected, ho-02.1 (launch and termination) and ho-02.2 (environment and retry), each with its own x.

### ho-02x — Review of Run

The first review of code that ships, and the one that sets the standard for the rest. Run is the component the seed cares most about keeping tight, and it is headless, so the antagonist can read all of it without UI noise. The standing brief applies in full.

**Depends on:** ho-02.

**Ho-specific questions:**
- Is there any process-handling code the spike did not prove? Anything new here that ho-01's findings did not cover is unverified by definition.
- Does the `-tt` rule do exactly one insertion and nothing else? Find any other way the typed line can be altered.
- Does the orphan test actually inspect the process table, or does it trust the component's own report?
- Does Run know anything about Panel, Transcript, or Memory? Any import or type reference across that boundary is a Must fix.

## Phase 2 — The Surface

The app becomes something the practitioner can use. ho-03 builds Panel: the shortcut, the floating window, focus, the three states, the dismiss rules, Stop, and Open in Terminal. ho-04 builds Transcript: output rendered as it arrives, colour and carriage return handled, selection and copy, exit status, and the memory ceiling. Each has its x. At the end of the phase the hotkey brings up a panel, a command runs, the output is readable, and Escape dismisses it. The core interaction works end to end on the practitioner's machines, with default settings and no macros.

*Release on phase complete: v0.2*

### ho-03 — Panel

Build the only visible surface. A non-activating floating panel in AppKit, a global shortcut registered through the system call with failure detection, keyboard focus on appearance, and the Composing, Running, and Done states with their dismiss rules. Stop and `Control-C` route to Run. Open in Terminal opens Terminal.app at the working directory, or the terminal chosen in settings once ho-05 adds the picker. Relaunching the running app shows the panel. No Dock icon.

**Depends on:** ho-02x.

**What's in scope:**
- Hotkey registration, failure detection, the Character Viewer conflict message
- The panel window, focus, states, dismiss rules
- Stop, Control-C, second-Stop force-kill
- Open in Terminal
- The gear reaching a placeholder settings window and Quit

**What "done" means:**
- The core interaction runs end to end with a plain-text transcript area
- Escape and click-out are inert while Running and dismiss when Done, demonstrated
- Quit kills a running command, demonstrated with the process table
- ho-03x passes

**What's out of scope:** Rendering beyond plain text (ho-04). Real settings (ho-05).

**Decisions required:**
- **Hotkey failure presentation**: what the panel and settings show when registration fails, including the Character Viewer case.
- **Transcript carry-over**: whether handing the transcript to the terminal is cheap. If not, dropped without discussion.
- **Opening Terminal.app at a directory**: the mechanism, and how other installed terminals are detected for ho-05's picker.

**Possible split:** if the shortcut recorder or conflict handling grows, ho-03.1 (panel and states) and ho-03.2 (hotkey, recorder, conflicts), with the recorder possibly moving to ho-05 where settings live.

### ho-03x — Review of Panel

Panel is where a state-management framework would have crept in, and where SwiftUI would have been reached for because it is familiar. The antagonist reads for both.

**Depends on:** ho-03.

**Ho-specific questions:**
- How many representations of the Composing, Running, and Done state exist? One is correct. Find the second.
- Is there any SwiftUI in the panel window itself? The System Design allows it only in settings.
- Does the dismiss rule live in one place, or is "can I dismiss right now" computed in several?
- Is the hotkey registration the direct system call, or has a wrapper appeared around it?

### ho-04 — Transcript

Build the output view. Monospaced text in the design system's one monospace zone, streamed as bytes arrive, with colour sequences honoured, carriage-return overwrite handled so progress bars read correctly, and other control sequences stripped per the ho-01 list. Selection, `Command-C` for selection or whole transcript, a Copy control, exit status in the alarm colour for non-zero, and a fixed line ceiling with oldest-first eviction.

**Depends on:** ho-03x.

**What's in scope:**
- Rendering, colour, carriage return, stripping
- Selection and copy
- Status presentation
- The buffer ceiling

**What "done" means:**
- The real command set from ho-01 renders readably
- Fifty megabytes of output keeps the app under the ceiling, measured
- Copy behaves as specified with and without a selection
- ho-04x passes

**What's out of scope:** Any emulator. Search within output. Saved transcripts.

**Decisions required:**
- **Line ceiling**: the retained-line number, chosen from the ho-01 memory measurements.
- **Stripped versus honoured sequences**: the exact set, from the ho-01 list.

### ho-04x — Review of Transcript

Terminal-control handling is where "minimal" quietly becomes a parser for the whole escape-sequence grammar. The antagonist counts.

**Depends on:** ho-04.

**Ho-specific questions:**
- List every escape sequence the code recognises. Compare it to the ho-01 list. Anything not on the list is scope creep.
- Is the memory ceiling enforced by measurement in a test, or asserted in a comment?
- Does Transcript know anything about Run beyond receiving bytes?

**Phase boundary — replan checkpoint.** After ho-04x passes. First real use. The practitioner runs Issoku for a week of actual work before ho-05. Friction found here changes ho-05's scope or inserts a ho-04.5. See Replan checkpoints.

## Phase 3 — Memory

Settings, macros, and history. ho-05 builds the settings window with the shortcut recorder, the working-directory mode, the terminal picker, the history toggle, the menu bar toggle, and the update toggle; the nine macro slots loading into the input on `Command-1` through `Command-9`; and the history file with recall and Clear. ho-05x reviews it. At the end of the phase the app is feature-complete against the seed's first version.

*Release on phase complete: v0.3*

### ho-05 — Memory

Build the Memory component and the settings UI in SwiftUI hosted inside AppKit. Settings and macros live in user defaults; history is a plain text file in Application Support, off by default. The shortcut recorder captures a combination and re-registers the hotkey. The terminal picker lists Terminal.app and any detected terminals. The optional menu bar item appears when its toggle is on. History recall works in the input; Clear deletes the file.

**Depends on:** ho-04x.

**What's in scope:**
- Settings window: shortcut recorder, working-directory mode, terminal picker for Open in Terminal, history on/off, menu bar on/off, update check on/off, Refresh Environment
- Macros: nine slots, name and command, load on key
- History: file, recall, Clear

**What "done" means:**
- Every setting round-trips through relaunch
- A macro loads and does not run until Return
- History off by default; on, the file is readable in a text editor and Clear removes it
- ho-05x passes

**What's out of scope:** The update checker itself (ho-06). Transcript storage.

**Decisions required:**
- **History write timing and duplicates**: write on Return; what counts as a duplicate for recall.
- **Recorder edge cases**: modifier-only combinations and system-reserved combinations are refused with a message.

### ho-05x — Review of Memory

Settings code accumulates configuration surface. The antagonist checks that every setting in the window is one the System Design named, and that the storage is exactly user defaults and one text file.

**Depends on:** ho-05.

**Ho-specific questions:**
- List every persisted key. Match each to a setting the System Design names. Any extra key is a finding.
- Is there a configuration file, a plist of the app's own design, or a cache anywhere besides user defaults and the history file?
- Is the history file written on Return and nowhere else?
- Does any macro path execute without Return?

## Phase 4 — The Ship

The app leaves the practitioner's machine. ho-06 adapts palana's build script for signing, notarisation, and the `.dmg`, ports the update checker, creates the Payhip listing, finalises the README with real installation steps, and ships whatever icon exists. ho-06x reviews the pipeline and the update checker, which is the only code in the app that touches the network. At the end of the phase a stranger can download, install, run, update, and remove Issoku without help.

*Release on phase complete: v1.0*

### ho-06 — The Ship

Adapt `scripts/build_macos.sh` and `RELEASING.md` from palana: release build, bundle assembly, Developer ID signing with hardened runtime, app notarisation and staple, `.dmg` notarisation and staple. Port the 99-line update checker. Publish the first GitHub Release as Latest. Create the Payhip listing. Update the README's Installation and Development sections with the real steps. Package the icon the practitioner has designed by then.

**Depends on:** ho-05x.

**What's in scope:**
- Build and release pipeline
- Update checker
- Payhip listing
- README finalisation
- Icon packaging

**What "done" means:**
- A fresh macOS user account installs from the `.dmg`, runs the core interaction, receives an update notice from a test release, and removes the app cleanly
- Gatekeeper opens the app with no override
- ho-06x passes

**What's out of scope:** App Store. Marketing beyond the README.

**Possible split:** if icon work is still open when the pipeline is ready, ho-06.1 (pipeline and release) ships with a placeholder icon and ho-06.2 (icon) follows as a point release.

### ho-06x — Review of the Ship

The last review before anyone else runs the code. The antagonist reads the update checker as the privacy section of the README promises it, and reads the build script for anything that would publish what should not be published.

**Depends on:** ho-06.

**Ho-specific questions:**
- What exactly does the update request send? Headers, query, body. Compare to the README's Privacy section word for word.
- Is there any other network call in the app?
- Does the build script's bundle contain anything beyond the binary, the icon, and Info.plist? List the bundle.
- Are there credential-shaped strings anywhere in the repo, including the build script and its environment handling?

## What's NOT in this sequence

- A Mac App Store build. Deferred past 1.0.
- Transcript carry-over into the terminal, unless ho-03 finds it free.
- A frontmost-Finder working-directory mode. The setting is an enum; the case can be added later.
- A terminal emulator behind Transcript, unless ho-01's unreadable list is non-empty.
- Saved transcripts, output search, more than nine macros, any plugin or command-library surface.
- An x ho for ho-00. The scaffold writes no application code and is checked by the hooks it installs.

## Replan checkpoints

**After ho-01x.** The spike is first contact with the stack, and its review has confirmed the evidence. Two questions: did the spawn mechanism come in at a cost the seed accepts, and is the terminal-control list empty? If the mechanism is costly, ho-02's shape changes before it starts. If the list is not empty, a ho-01.5 is inserted to choose and wire an emulator, libghostty considered first, and ho-04's scope shrinks to hosting it.

**After ho-04x.** First real use, a week of actual work. The practitioner records friction. Friction that belongs to settings or macros adjusts ho-05's scope. Friction in the core interaction inserts a ho-04.5 before ho-05 begins.

A third, standing checkpoint has no fixed place: **the third Return.** If any single build ho receives three Return verdicts, the problem is not the code. It is the spec, the brief, or the builder's instructions, and the practitioner stops to decide which before a fourth fix pass.

## Numbering and insertion

Hos are numbered in sequence. A ho that splits becomes decimals of itself: ho-03 → ho-03.1, ho-03.2, each followed by its own x (ho-03.1x). Work inserted between hos takes a half number: ho-04.5 between ho-04x and ho-05, with a ho-04.5x. A review ho carries its build ho's number and an x; it is never split and never inserted on its own. A fix pass after a Return is a decimal of the build ho (ho-02.1), and the same x runs again against the new diff. Numbers are never reused; an abandoned number stays dead. Closed hos stay closed; evidence that a closed ho was wrong produces a new ho, not an edit.

## Anticipated splits and insertions

- **ho-02** may split into launch-and-termination and environment-and-retry.
- **ho-03** may split into panel-and-states and hotkey-and-recorder, with the recorder possibly moving to ho-05.
- **ho-01.5** inserts if the spike finds an emulator necessary.
- **ho-04.5** inserts if first real use finds friction in the core interaction.
- **ho-06** may split into pipeline and icon if the icon is not ready.
- **Fix passes** (ho-NN.1) insert after any Return verdict; they are expected, not exceptional.

## Other deferred decisions

- **App icon.** The practitioner is leaning toward a digitised terminal symbol. Designed outside the ho sequence; ho-06 packages what exists.
- **App Store build.** After 1.0, if ever. Run is the boundary a sandboxed build would change entitlements behind.
- **ControlMaster.** An SSH config recommendation in the README's Requirements, not an app feature.
- **The brief itself.** The antagonist brief is a first draft. After ho-02x, the first review of shipping code, the practitioner reads the report against the diff and edits the brief for whatever it missed or over-flagged. The edit is recorded in the build record.

## Dependency summary

```text
Phase 0  Foundation
  ho-00 Orientation ──────────────────────────────────────── v0.0
          │
Phase 1  The Process Model
  ho-01 The Spike ──► ho-01x review of evidence
          │               ◆ replan: spawn cost, emulator list
          │               └─ (ho-01.5 emulator, if needed)
  ho-02 Run ─────────► ho-02x ─────────────────────────────── v0.1
          │               └─ brief revised here
Phase 2  The Surface
  ho-03 Panel ───────► ho-03x
          │
  ho-04 Transcript ──► ho-04x
          │               ◆ replan: a week of real use ────── v0.2
          │               └─ (ho-04.5 friction, if needed)
Phase 3  Memory
  ho-05 Memory ──────► ho-05x ─────────────────────────────── v0.3
          │
Phase 4  The Ship
  ho-06 The Ship ────► ho-06x ─────────────────────────────── v1.0

  Any x ──► Return ──► ho-NN.1 fix pass ──► same x again
  Three Returns on one ho ──► ◆ stop: spec, brief, or builder
```

## What to do with this document

Open it at the start of every session to find the current ho, then author that ho's dandori spec with the Kamae 5 skill. A build ho's session is Claude Code. An x ho's session is Codex, fresh, given the spec, the diff, and the brief. When a ho closes or a checkpoint passes, append an entry to the build record below and edit the plan above as the ruling requires. The plan is edited freely. The record is not.

## Build record

Append-only. One entry per ho close, per x verdict, and per replan checkpoint, each shaped as a state-summary block with the verbatim labels COMPLETED / NEXT / ACTION ITEMS or BLOCKS / PROJECT LIFECYCLE (`kamae | dev | beta | production`), with as much prose around it as the moment warrants. An x entry records the verdict and the count of Must-fix, Should-fix, and Note findings, and links the report. Entries are added, never rewritten.

### ho-00 — Orientation — closed 2026-10-25

Opening hash: none; the repository was initialised in this ho. Closing hash: the first commit, `ho-00: orientation — scaffold the package and the verification stack`. The closing hash of a ho is the commit that carries its build-record entry, so it cannot be written into that entry; it is recorded as the opening hash of the next ho's entry. ho-01's entry carries this one.

Spec: `ho-process/hos/ho-00-orientation.md`. One Opus subagent wrote the scaffold; the orchestrator ran git, the hooks, the refusal check, and the commit. Six decisions landed during execution and are recorded in the spec: pālana's colour digits kept with a 0.002 test tolerance; three SwiftLint rules disabled where they contradict swift-format; `warning_threshold: 1` because 0.65 cannot satisfy 0; per-target `.xctest` bundle collection in the coverage script; empty measured set passes with a message until ho-02; the developer directory moved to Xcode after the Command Line Tools broke SwiftLint and swift-testing.

**STATE-SUMMARY**
- **COMPLETED** — ho-00. Swift package (IssokuCore, Issoku, two test targets), verification stack (swift-format, SwiftLint, pre-commit, coverage floor script), Theme with the eight pālana tokens light and dark, MIT licence, CLAUDE.md, State Memory, roster. Full stack green; hooks refuse a misformatted file.
- **NEXT** — ho-01, the spike.
- **ACTION ITEMS / BLOCKS** — toolchain stays on Xcode; SwiftLint baseline template fix is practitioner-scope; `resources/messages.MD` untracked pending the practitioner's call; deferred items in the spec's Handoff.
- **PROJECT LIFECYCLE** — kamae

### ho-01 — The Spike — closed 2026-10-25

Opening hash: `ee95ee71f25877574df7302f5e88e8908e6458eb`, ho-00's closing commit. Closing hash: the commit `ho-01: the spike — prove the pseudoterminal process model`, recorded as the opening hash of ho-01x's entry, by the convention ho-00's entry states.

Spec: `ho-process/hos/ho-01-the-spike.md`. Findings: `ho-process/hos/ho-01-spike-findings.md`. Harness: `spike/`, its own package, deleted by ho-02. One Opus subagent built the harness and ran the run sheet; the practitioner typed every sudo password and judged readability; the orchestrator verified the stack, inspected every capture it cites, redacted host, address, user, key, pool and machine names to placeholders, and committed. Two Think decisions were amended during execution and both forms are recorded: the line-in-progress is capped at 1 MiB (Decision 6), and the rejected-key case uses `ssh -F /dev/null` so the user's config cannot supply a key (Decision 9).

**STATE-SUMMARY**
- **COMPLETED** — ho-01. `forkpty` from `import Darwin`, no shim, met the criterion on the first attempt; `posix_spawn` was never built. The sudo prompt arrives through the pseudoterminal, nothing typed reaches the capture, and sudo's exit status propagates (0 on success, 1 after three wrong passwords). Interrupt and force-kill are clean locally; with `ssh -tt` an interrupt reaches the remote even when INT is trapped, without `-tt` the remote survives. Return-to-first-byte medians: 14.5 ms local, 202.1 / 383.2 / 602.3 ms for the LAN, LAN and Tailscale hosts. Peak resident 9.7 MB at both one and fifty megabytes of output once the line cap landed. All 24 captures emitted SGR only; the non-SGR list is empty and every plain output is readable. The scrubbed launch loses `SSH_AUTH_SOCK`, `SHELL`, `TERM`, `TMPDIR`; ssh still authenticates from the key on disk.
- **NEXT** — ho-01x: author `ho-process/hos/ho-01x-review-of-the-spike.md` from the x template with the findings document's path on the commit-range line, commit it, hand off to Codex (`gpt-6.1-sol`).
- **ACTION ITEMS / BLOCKS** — for ho-02: set a real window size (the spike leaves 0×0); `forkpty` calls `fork`, so spawn from a place the app process can afford it; ssh status 255 covers both connection failure and interrupt; the 1 MiB line cap makes a 50 MB unbroken line take 1.8 s instead of 0.4 s. Replan checkpoint after ho-01x: spawn cost and the empty terminal-control list. A foreign `sleep 300` runs on the Proxmox host; never `pkill` it.
- **PROJECT LIFECYCLE** — kamae
