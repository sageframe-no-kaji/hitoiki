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

A spike is a short, throwaway experiment built to answer specific technical questions. This one is a command-line program, not part of the app target, that opens a pseudoterminal, spawns the user's shell with a command line and a captured environment in a new process group, streams output to stdout, forwards stdin keystrokes, and responds to a signal by interrupting and then killing the group. It runs against the practitioner's real hosts: host-a, host-b, host-c. Its code is not kept. Its findings are written into a findings document in the ho's folder and into ho-02's spec.

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
- **Spawn mechanism**: which POSIX path gives a PTY that is the child's controlling terminal, in a new process group, with the captured environment, callable from Swift 6 with strict concurrency. Criterion: `ssh -tt host-a 'sudo true'` prompts, a keystroke-typed password is accepted, nothing echoes, the command completes with status zero.
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

### ho-01x — run 1 — Return — 2026-10-25

Opening hash: `1e532c22d1a9012948670d4140a511d5dd96e382` (ho-01's closing commit). The x document was committed as `c8b20a15c97d0eec0ad510b395c1822618073ec1`; Codex (`gpt-6.1-sol`) committed the report as `20777a1adcf85e8bf888f623785fbb3cb482c989`. Report: `ho-process/reviews/ho-01x-report-1.md`. Verdict **Return**: 5 Must-fix, 0 Should-fix, 6 Notes. The orchestrator checked each Must-fix against the spike code and the findings and confirms all five. M1: the plain model emits only at LF, so a sudo prompt is invisible under `--plain` until the password is typed, and the findings' claim that the raw captures settle the prompt question is wrong. M2: a remote command exiting 255 is indistinguishable from ssh's own 255. M3: the reproduction commands need `spike/captures/`, which nothing creates. M4 and M5: the fresh-connection and key-from-disk claims rest on inference, not a recorded `ssh -G`. Note N6 is also right: the capture count in ho-01's entry above is 23, not 24. ho-01.1 answers all five; ho-01x then runs again as run 2 over the whole range.

**STATE-SUMMARY**
- **COMPLETED** — ho-01x run 1, Return.
- **NEXT** — ho-01.1, the fix pass: `ho-process/hos/ho-01.1-fix-pass.md`.
- **ACTION ITEMS / BLOCKS** — the practitioner reruns run 10 under `--plain` after `sudo -k` with the amended harness. Codex's efficiency audit (`ho-process/reviews/ho-01-efficiency-audit.md`, uncommitted) is input to ho-02 and ho-04 Think, not a decision; its one spike-level finding, unbounded SGR and control-sequence buffers, is folded into ho-01.1.
- **PROJECT LIFECYCLE** — kamae

### ho-01.1 — Fix pass for the spike — closed 2026-10-25

Opening hash: `20777a1adcf85e8bf888f623785fbb3cb482c989` (the run-1 report commit). Closing hash: the commit `ho-01.1: fix pass for the spike — answer ho-01x run 1`, recorded as the range end of ho-01x run 2. Spec: `ho-process/hos/ho-01.1-fix-pass.md`. One Opus subagent amended the plain model and the findings; the practitioner ran `sudo true` under `--plain`; the orchestrator corrected the ho-01 spec's two wrong sentences with the corrections marked, verified the stack and every transcript it cites, and committed.

Found on the way: `smartctl` is permitted without a password on the Proxmox host, so ho-01's run 10 could never prompt and its "credential cache" explanation was wrong; sudo's timestamp there lasts 60 minutes. ho-01's entry above says 24 captures; the count was 23, and is 25 after this ho.

**STATE-SUMMARY**
- **COMPLETED** — ho-01.1. M1: the plain model renders the line in progress, proven with a visible sudo prompt under `--plain`; parser bounds of 256 bytes per sequence and 4,096 bytes of pending SGR. M2–M5 and N6: the findings corrected with recorded `ssh -G` configuration, the right status-255 rule, `mkdir -p` in every reproduction, and the capture count.
- **NEXT** — ho-01x run 2 over `ee95ee71f25877574df7302f5e88e8908e6458eb..<ho-01.1 closing hash>`, report `ho-process/reviews/ho-01x-report-2.md`.
- **ACTION ITEMS / BLOCKS** — none blocking. For ho-02: a remote sudo prompt is not guaranteed (NOPASSWD rules, 60-minute timestamps); a prompt without LF must render as it arrives. For ho-04: the 256-byte sequence bound covers OSC and DCS; the plain model's column store is a byte array per character (audit). The README rewrite and the efficiency audit stay uncommitted pending the practitioner.
- **PROJECT LIFECYCLE** — kamae

### ho-01x — run 2 — Pass — 2026-10-26

Opening hash: `8e0b8d1a96bf1647b279aa6cdc036338e51cb4f6` (ho-01.1's closing commit, the end of the run-2 range). The run-2 x document was committed as `139d04dfae3967e20e6e1e4652ee6f354c6b024d`; Codex (`gpt-6.1-sol`) committed the report as `e10a46e6c069b51f1e13d8bd6d74da7f070ccb6d`. Report: `ho-process/reviews/ho-01x-report-2.md`. Verdict **Pass**: 0 Must-fix, 0 Should-fix, 7 Notes. Codex judged all five run-1 Must-fix findings answered, ran the build, the tests, the coverage script and the spike release build itself with the results the orchestrator had recorded, and evaluated the parser bounds and the line echo offline, getting the same bytes the orchestrator saw in ho-01.1. The orchestrator read the report against the range and accepts the verdict.

The Notes record limits, not defects. N1: remote force-kill was never exercised, ho-01's own stated limitation. N2: the memory numbers do not cover large output through the amended plain renderer. N3: two unconsumed members in the throwaway harness. N4: the escape grammar and the line cap each exist in two places, both required by the spec. N5: descriptive comments. N6: five companion files are needed to follow `main.swift`. N7: ho-01's Reflect still carries three superseded sentences (the key read from disk, 24 captures, the status-255 rule); they stay as the historical record under the forward-only rule, and the findings' "Corrected in ho-01.1" section with ho-01.1's entry above is the supersession. ho-01 is closed for good. Its closing commit is the one that carries this entry.

**STATE-SUMMARY**
- **COMPLETED** — ho-01x run 2, Pass. ho-01 closed: the pseudoterminal process model is proven and reviewed.
- **NEXT** — the replan checkpoint after ho-01x. The practitioner rules on the two questions under Replan checkpoints, spawn cost against the seed and the terminal-control list; the ruling is appended here as a checkpoint entry before ho-02 opens.
- **ACTION ITEMS / BLOCKS** — Checkpoint inputs: `forkpty` through `import Darwin` with no shim and no dependency, 14.5 ms median from spawn to first byte locally, 26 ms to exit for the probe; the terminal-control list is empty across 25 captures, so no ho-01.5 on that ground. N2 is a measurement for ho-02's tests to make, not a defect. The README rewrite and `ho-process/reviews/ho-01-efficiency-audit.md` stay uncommitted pending the practitioner.
- **PROJECT LIFECYCLE** — kamae

### Replan checkpoint — after ho-01x — passed 2026-10-26

The practitioner ruled on the two questions under Replan checkpoints. Spawn cost: accepted as found; `forkpty` through `import Darwin` with no shim and no dependency, 14.5 ms median from spawn to first byte locally, is a cost the seed accepts, and ho-02 keeps the shape planned above. Terminal-control list: empty across the 25 captures, and the practitioner rules cursor movement a stated limit of the product rather than a case to support; Issoku is not for full-screen programs, and the README says to use a terminal for those. No ho-01.5, no emulator, no dependency; ho-04 builds the plain model. The cost of an emulator was weighed and recorded in the session: a dependency against the System Design, an inserted ho, and a panel that stops being a panel. Deferring costs nothing, because Run's pseudoterminal and keystroke forwarding are what an emulator would sit on, so the question can return at v2 without reopening ho-02.

**STATE-SUMMARY**
- **COMPLETED** — the Phase 1 midpoint checkpoint. Both questions ruled; the plan above is unchanged.
- **NEXT** — ho-02, Run: author `ho-process/hos/ho-02-run.md` with the Kamae 5 skill, Think phase first.
- **ACTION ITEMS / BLOCKS** — Think inputs for ho-02: the findings' followups, ho-01.1's facts (a remote sudo prompt is not guaranteed; a prompt without LF must render as it arrives), ho-01x run 2's N1 and N2 (remote force-kill unexercised; large output through the incremental renderer unmeasured), and `ho-process/audits/ho-01-efficiency-audit.md`.
- **PROJECT LIFECYCLE** — kamae

### ho-02 — Run — closed 2026-10-26

Opening hash: `0f2630b7ee6a2e820de43276b921d3afa8c81745`, the commit that carried the spec and deleted the spike. Closing hash: the commit `ho-02: run — the production process model`, recorded as the opening hash of ho-02x's entry, by the convention ho-00's entry states.

Spec: `ho-process/hos/ho-02-run.md`. One Opus subagent built `Sources/IssokuCore/Run/` (Run, PTY, LoginEnvironment, Retry), the tests and the sudo fixture, and the driver `Sources/IssokuRunCLI/`; the practitioner ran the ten-item run sheet against the Proxmox host and typed every sudo password; the orchestrator read the whole diff, ran the stack, redacted the transcript, and committed. Two rulings landed during execution and are recorded in the spec: the driver is built for the run sheet and deleted at ho-03's first commit (Decision 8), and the child closes every inherited descriptor before `execve` (Decision 3). The grandchild hang-up was recorded as Discovery and nothing built for it.

**STATE-SUMMARY**
- **COMPLETED** — ho-02. Run is an actor on a serial queue: `forkpty` with a real window size, a read source on the primary and a process source for the exit, `waitpid`, `bytes` and `states` streams, `interrupt`, `kill`, `write`, `resize`, `refreshEnvironment`. The login environment is captured once from `<shell> -l -c 'env -0'` with a five-second limit. The `-tt` offer is one insertion under four guards, with sudo's real 164-byte refusal as the fixture. 31 tests in 4 suites pass; IssokuCore line coverage 92.10%; the orphan tests read the process table; 392 nonblank lines against the spike's 432. The run sheet's ten items passed on the first run, including sudo refused, sudo with the right and the wrong password, the interrupt reaching the remote through `-tt`, the trapped-interrupt force-kill, and the timeout with no offer.
- **NEXT** — ho-02x: author `ho-process/hos/ho-02x-review-of-run.md` from the x template over `0f2630b7ee6a2e820de43276b921d3afa8c81745..<this entry's commit>`, report `ho-process/reviews/ho-02x-report-1.md`, commit it, hand off to Codex (`gpt-6.1-sol`).
- **ACTION ITEMS / BLOCKS** — For ho-02x: concurrent spawns in one process intermittently fail `forkpty` with errno −6, so the Run suite is serialized; the descriptor close loop costs about 8 ms per spawn under a terminal launch and nothing under the GUI launch path. For ho-03: delete `Sources/IssokuRunCLI/`, the `issoku-run` product, and its coverage-ignore entry in the first commit; the call order and the stream rules are in the spec's Reflect. For ho-04: `bytes` chunks carry no line framing and can end inside an escape sequence; call `resize` when the width is known. For ho-05: a working directory that cannot be entered exits 127 silently, so validate it when stored. After ho-02x the practitioner edits the antagonist brief, per Open questions.
- **PROJECT LIFECYCLE** — kamae

### ho-02x — run 1 — Return — 2026-10-26

Opening hash: `6eae8a8b46a1d6a515d8ed32d8f4631d643697bd` (ho-02's closing commit). The review document was committed as `f504511e5a569bdf0ba868f973b2719d794fe02e`; the report as `dfc94d90d604db3b2923a2fbf6522430767b69df`. Report: `ho-process/reviews/ho-02x-report-1.md`. Verdict **Return**: 4 Must-fix, 1 Should-fix, 3 Notes. Build, 34 tests, and 92.10% core coverage passed, but the review's local probes found a timeout bypass after stdout closes, blocked cancellation during terminal writes, unbounded unread output, and terminal restoration bypassed by signals. Releasing an active Run also left its child alive. The fix-pass spec records the practitioner's ruling to fix all five and retain pending input and output without dropping bytes.

**STATE-SUMMARY**
- **COMPLETED** — ho-02x run 1, Return.
- **NEXT** — ho-02.1: `ho-process/hos/ho-02.1-fix-pass.md`.
- **ACTION ITEMS / BLOCKS** — Answer M1–M4 and S1; take N2's redundant comments and N3's refresh tests. N1's driver duplication remains bounded by the driver's deletion at ho-03. Run 2 reads the whole original range through the fix pass, not just its changes.
- **PROJECT LIFECYCLE** — kamae

### ho-02.1 — Fix pass for Run — closed 2026-10-31

Opening hash: `dfc94d90d604db3b2923a2fbf6522430767b69df` (the run-1 report commit). The fix-pass document opened in `f6a9034`; its closing commit is `ho-02.1: fix pass for run — answer ho-02x run 1`, recorded as the range end of ho-02x run 2. Spec: `ho-process/hos/ho-02.1-fix-pass.md`. A builder agent completed the existing changes; the orchestrator read the diff and independently ran all six checks and the terminal demonstrations.

Verification found one error in the proposed M3 mechanism: an unbounded drain after reap could accumulate unread output across completed commands. The drain now respects the same 1 MiB ceiling as normal reads, including across starts. A regression failed before correction, then retained all 1,064,704 bytes across 65 commands. This changes the draft mechanism, not the bounded-output requirement or the public surface beyond `bytes` becoming `Run.Output`.

**STATE-SUMMARY**
- **COMPLETED** — ho-02.1. The deadline covers EOF and exit; pending input does not block interrupt or kill; output backpressure survives reap and subsequent commands; release kills and reaps the owned child even while reading is paused. TERM and HUP restore the driver's terminal and exit 143 and 129; normal completion also returns promptly. Refresh replacement and failure preservation are tested. Both verification runs pass: 39 core tests plus 3 Theme tests, 93.65% core coverage, 478 nonblank Run-source lines against a 480 limit.
- **NEXT** — Fresh-session ho-02x run 2 from `ho-process/hos/ho-02x-review-of-run.md`, over the original opening commit `0f2630b7ee6a2e820de43276b921d3afa8c81745` through this fix pass's closing commit. Report: `ho-process/reviews/ho-02x-report-2.md`.
- **ACTION ITEMS / BLOCKS** — Formal review pending; no Pass is claimed. After Pass the practitioner revises the antagonist brief before ho-03. The driver and its product/target/coverage exclusion are deleted at ho-03's first commit. `Run.Output` is for one consumer and finishes after queued chunks when Run is released; Done follows reaping and bounded terminal draining, so the consumer must keep taking output while a command completes. N1's driver duplication remains until deletion. No live-host commands were run during this fix pass.
- **PROJECT LIFECYCLE** — kamae

### ho-02x — run 2 — Pass — 2026-10-31

Opening hash: `46f78c9b233da6e0029911ca5d44d15e43205553` (ho-02.1's closing commit, the end of the run-2 range). The run-2 x document was committed as `6e4a8da89ae206551c958a8fc357a65fd9593e3e`; Codex (`gpt-6.1-sol`) committed the report as `79c1c233b7414fdd46412e071b1612c8fa478f67`. Report: `ho-process/reviews/ho-02x-report-2.md`. Verdict **Pass**: 0 Must-fix, 0 Should-fix, 3 Notes. Codex read the whole unit over the original range through the fix pass, judged every run-1 finding answered, ran the build, the 42 tests and the coverage script itself with the results the orchestrator had recorded (93.65%, 478 nonblank Run-source lines against 480), and ran its own outer-pseudoterminal probes: TERM and HUP restore echo and canonical mode and exit 143 and 129. No command was run against a remote host. The orchestrator read the report against the range and accepts the verdict.

The Notes record limits, not defects. N1: the driver's write loop duplicates Run's, retained on purpose until the driver's deletion at ho-03's first commit. N2: the refresh test observes that capture finishes after Done, not that it never overlaps the running command; the one-at-a-time rule has no independent witness. N3: one comment in Retry restates its type's comment. Between the run-2 hand-off and the report, the orchestrator redacted the host names in the System Design's walkthrough and the ho-01 entry above (`52456f99e67fcab4479a4a5351a3f61bd3c9f9b6`), outside the review range. ho-02 is closed for good. Its closing commit is the one that carries this entry.

**STATE-SUMMARY**
- **COMPLETED** — ho-02x run 2, Pass. ho-02 closed: Run, the production process model, is built and reviewed.
- **NEXT** — the practitioner edits the antagonist brief (Open questions, "The brief itself") from the two ho-02x reports against the diff; the edit is recorded here. Then ho-03, Panel: author its spec with the Kamae 5 skill, Think phase first, in a fresh session.
- **ACTION ITEMS / BLOCKS** — ho-03's first commit deletes `Sources/IssokuRunCLI/`, the `issoku-run` product and target, and its coverage-ignore entry. Think inputs for ho-03: ho-02's Reflect (call order, stream rules, exit mapping, public surface) and ho-02.1's Results (`bytes` is `Run.Output`, one consumer, which keeps taking output while a command completes). N2 above is a test to make wherever a consumer can call refresh mid-command. For ho-04: chunks carry no line framing and can end inside an escape sequence; call `resize` when the width is known. For ho-05: validate a stored working directory when it is stored.
- **PROJECT LIFECYCLE** — kamae

### Antagonist brief — reviewed after ho-02x — stands 2026-10-31

The practitioner read the brief against both ho-02x reports and the range. Run 1 found four defects and a leak, none spurious; run 2 found nothing to fix and three fair Notes. The brief stands unchanged. The deferred decision "The brief itself" under Other deferred decisions is resolved.

**STATE-SUMMARY**
- **COMPLETED** — the brief review. No edit.
- **NEXT** — ho-03, Panel: author its spec with the Kamae 5 skill, Think phase first, in a fresh session.
- **ACTION ITEMS / BLOCKS** — as the ho-02x run 2 entry above.
- **PROJECT LIFECYCLE** — kamae

### ho-03 — Panel — closed 2026-10-31

Opening hash: `f371d87b18d101c5c9ea46bcace9ed3102939067`, the brief-review commit above. Five commits: `dec68946185e57ddea39672794dc66b2a884ae27` (the spec; `Sources/IssokuRunCLI/`, the `issoku-run` product and its coverage ignore deleted), `7775d8dfb45e7cdb18563599411a36597badf7a3` (the build), `489eaf5b117ace05737183629e2c091e994a31b9` (Reflect drafted before the run sheet), `205f618d6e15b8a2cf889694c206f5a45df0223e` (clear on dismiss and the block cursor, from the run sheet), and the closing commit `ho-03: panel — the only visible surface`, recorded as the opening hash of ho-03x's entry, by the convention ho-00's entry states.

Spec: `ho-process/hos/ho-03-panel.md`. The practitioner and the orchestrator settled sixteen decisions in the Think phase, then the practitioner lifted the spec-approval gate before leaving ("lift for now, do as much as you can"). One Opus subagent built `Sources/Issoku/` (the AppKit delegate, Panel, Keystrokes, Hotkey, PanelWindow, TranscriptPlaceholder, SettingsWindow) and three test files; the orchestrator read every diff, ran the stack, and committed. The practitioner ran the ten-item run sheet and added two decisions from it, built the same day: dismissing clears the panel (17) and a block cursor shows while Running (18). Three deferred decisions resolved: hotkey failure is a notice line and the Settings window's one line; transcript carry-over into the terminal is dropped; Open in Terminal is `NSWorkspace` opening the directory in Terminal.app, with ho-05's detection list recorded in the spec.

**STATE-SUMMARY**
- **COMPLETED** — ho-03. The core interaction runs end to end on the practitioner's machine with a plain-text transcript area: hotkey, non-activating panel placed like Spotlight, Composing/Running/Done derived from one stored `RunState?`, one dismiss rule reached by Escape, click-out and the hotkey, Stop and Control-C through one counter (interrupt, then kill), keystrokes and paste forwarded to the command with nothing drawn, the `-tt` offer by button or empty Return, Open in Terminal, the gear with Settings and Quit, Quit killing a running command. Run sheet: items 1–9 passed; item 10's Character Viewer shortcut does not exist on this macOS, so the conflict case is unobserved. 21 app tests and 39 core tests; IssokuCore 93.65%; `Sources/Issoku` 92.28% under a new floor that excludes four view files by name.
- **NEXT** — ho-03x: author `ho-process/hos/ho-03x-review-of-panel.md` from the x template over `f371d87b18d101c5c9ea46bcace9ed3102939067..<this entry's commit>`, report `ho-process/reviews/ho-03x-report-1.md`, commit it, hand off to Codex (`gpt-6.1-sol`).
- **ACTION ITEMS / BLOCKS** — For ho-03x: whitespace-only Return takes the offer (subagent's reading, not reversed); the click-out is `resignKey()`, not the notification; `collectionBehavior` on the window is commented; `fit()` lays out the whole placeholder per chunk (ho-04 deletes the file). For ho-04 Think: Composing collapses to the input alone with the transcript beneath (practitioner's ruling 2026-10-31, one style, no setting); replace `TranscriptPlaceholder.swift`, take over the `bytes` task and `terminalSize`, call `resize` on width change, carry the cursor over; chunks can split escape sequences. For ho-05: history (asked for at the run sheet); `Panel.init(directory:)`; validate a stored directory; `Hotkey.combination` is the recorder's constant; the terminal bundle-id list in the spec's Decision 12; Refresh Environment with ho-02x's N2 test. For ho-06: demonstrate reopen with the bundle. Unreproduced: Escape once failed to dismiss in Done at run-sheet item 3.
- **PROJECT LIFECYCLE** — kamae

### ho-03x — run 1 — Return — 2026-11-02

Opening hash: `ed9ee98d83920ccb8df345206f19372eb7185f68` (ho-03's closing commit). The review document was committed as `fd813b4c5c50b77707e7910485916a6e97ce9c1a`; Codex (`gpt-6.1-sol`) committed the report as `29adb365f1fb409ff0645d95e75eab725e544b9a`. Report: `ho-process/reviews/ho-03x-report-1.md`. Verdict **Return**: 3 Must-fix, 3 Should-fix, 3 Notes. Build, 60 tests and both coverage floors passed; the review's local probes found a submission that survives dismissal while it waits for the environment capture and then starts hidden, and output that reaches the panel after Done and after the dismissal clear because Panel's two consumers are independent. The third Must-fix, four doc comments that summarise their methods, the orchestrator reads as a Note; the practitioner ruled it trimmed without a wider audit. The orchestrator read the report against the range and accepts the verdict on M1 and M2.

**STATE-SUMMARY**
- **COMPLETED** — ho-03x run 1, Return.
- **NEXT** — ho-03.1: `ho-process/hos/ho-03.1-fix-pass.md`.
- **ACTION ITEMS / BLOCKS** — Answer M1–M3 and S1–S3; take N2. M2's fix is in Run (Done held until the consumer has taken every chunk), which opens `Sources/IssokuCore/` in the fix pass and is read by run 2. Run 2 reads the whole original range through the fix pass, not just its changes. N1 and N3 stay as recorded.
- **PROJECT LIFECYCLE** — kamae

### ho-03.1 — Fix pass for Panel — closed 2026-11-02

Opening hash: `29adb365f1fb409ff0645d95e75eab725e544b9a` (the run-1 report commit). The fix-pass document opened in `fece43530271cef974f20b5230a481305f81eb4c`; its closing commit is `ho-03.1: fix pass for panel — answer ho-03x run 1`, recorded as the range end of ho-03x run 2. Spec: `ho-process/hos/ho-03.1-fix-pass.md`. The practitioner approved the spec before the subagent started; one Opus subagent built it test first; the orchestrator read the diff twice, settled two questions the subagent raised under the System Design's one-command rule (a second Return while the launch capture is pending does nothing; the line in Run's `start` that the held Done made unreachable is deleted), ran the six checks with the Panel suite three times, and committed.

**STATE-SUMMARY**
- **COMPLETED** — ho-03.1. A dismissal cancels a submission still waiting for the login-environment capture, and a second submission while one waits does nothing. Run yields Done only once the consumer has taken every chunk, with a chunk counted as taken when the consumer returns for the next; the ended child keeps Run occupied until then. The four narrating comments are gone; the launch-wait, state-trace and offer tests hold the command at a readiness point; the transcript font has one definition; the shortcut's display name has one. 24 app tests and 40 core tests pass three times; IssokuCore 93.73%, `Sources/Issoku` 92.46%; Run's sources 478 → 484 nonblank lines.
- **NEXT** — ho-03x run 2 from `ho-process/hos/ho-03x-review-of-panel.md`, over `f371d87b18d101c5c9ea46bcace9ed3102939067` through this fix pass's closing commit. Report: `ho-process/reviews/ho-03x-report-2.md`.
- **ACTION ITEMS / BLOCKS** — Formal review pending; no Pass is claimed. For run 2: the submission handle is a Task, not a second state value; Run's public surface is unchanged, its Done contract is stronger. For every consumer of `Run.Output`: a consumer that stops pulling never sees Done for a command whose output it has not taken; Panel's iterator lives for the app's life. N1 and N3 of run 1 stand as recorded. The ho-04 and ho-05 items of ho-03's entry stand.
- **PROJECT LIFECYCLE** — kamae

### ho-03x — run 2 — Return — 2026-11-02

Opening hash: `bf42a7dacc01f1369bf9308997060a6ece2ead35` (ho-03.1's closing commit, the end of the run-2 range). The run-2 x document was committed as `08ff66c50ae5827c0e42a83a910bceadb51e7cf8`; Codex (`gpt-6.1-sol`) committed the report as `3e9a3be160999776dd080206eeb01d1094aabff1`. Report: `ho-process/reviews/ho-03x-report-2.md`. Verdict **Return**: 1 Must-fix, 0 Should-fix, 2 Notes. Build, 64 tests and both coverage floors passed; every run-1 finding but M1 is judged answered, and the two run-1 duplications are gone. The remaining M1: ho-03.1's cancellation covers only the wait on the capture; between the cancellation check and Run's `start`, and between `start` returning and Panel applying Running, a dismissal is still accepted and the command runs hidden. Codex reproduced the second gap without changing the reviewed code. The orchestrator read the report against the range and accepts the verdict. The practitioner ruled the fix: a submission in flight is undismissable, in the one dismiss rule; cancellation goes.

**STATE-SUMMARY**
- **COMPLETED** — ho-03x run 2, Return.
- **NEXT** — ho-03.2: `ho-process/hos/ho-03.2-fix-pass.md`.
- **ACTION ITEMS / BLOCKS** — Answer M1 only. The fix reverses ho-03.1's cancellation: `canDismiss` reads the submission handle, cleared at Running or on a start failure; `killForQuit` awaits an in-flight submission. Run 3 reads the whole original range through both fix passes. N1 and N2 stay as recorded.
- **PROJECT LIFECYCLE** — kamae

### ho-03.2 — Second fix pass for Panel — closed 2026-11-02

Opening hash: `3e9a3be160999776dd080206eeb01d1094aabff1` (the run-2 report commit). The fix-pass document opened in `3a66fbbe881fbf745cdfc30fd9b68cc8f496e334`; its closing commit is `ho-03.2: second fix pass for panel — answer ho-03x run 2`, recorded as the range end of ho-03x run 3. Spec: `ho-process/hos/ho-03.2-fix-pass.md`. The practitioner approved the spec; one Opus subagent built it test first; the orchestrator read the diff three times, settled three execution points (the delegate's Quit guard reads `canDismiss`, one line in `App.swift` added to the table; the Quit-in-flight test witnesses "no living child" rather than a pid the killed command never gets to write; `ps` drops its own row), ran the six checks with the suite three times, and committed.

**STATE-SUMMARY**
- **COMPLETED** — ho-03.2. A submission in flight is undismissable: the one dismiss rule reads the submission handle alongside `state`, the handle clears at Running or on a start failure, dismissal cancels nothing, and Quit awaits an in-flight submission before killing. Codex's run-2 reproduction is a test and passes. 26 app tests and 40 core tests pass three times; IssokuCore 93.73%, `Sources/Issoku` 91.78%.
- **NEXT** — ho-03x run 3 from `ho-process/hos/ho-03x-review-of-panel.md`, over `f371d87b18d101c5c9ea46bcace9ed3102939067` through this fix pass's closing commit. Report: `ho-process/reviews/ho-03x-report-3.md`.
- **ACTION ITEMS / BLOCKS** — Formal review pending; no Pass is claimed. Cost recorded for the practitioner: on the first command after launch, Escape, click-out and the hotkey do nothing for up to five seconds while the login environment is captured. N1 and N2 of run 2 stand. The ho-04 and ho-05 items of ho-03's entry stand.
- **PROJECT LIFECYCLE** — kamae
