---
created: 2026-11-08
status: complete
type: ho-document
project: hitoiki
ho: replan-after-04x
kamae: 5
shape: orientation
phase: 2 — The Surface (boundary)
title: Replan checkpoint — after ho-04x
description: The decision session the overview places between Phase 2 and Phase 3. Six rulings — the virtual Mac for test runs, the Transcript suite, the unbroken-line cost, the input's size, the update check, and ho-05's shape — recorded with their outcomes; no code.
builds-on:
  - kamae-2-hitoiki-system-design
  - kamae-4-hitoiki-ho-overview
  - ho-process/hos/ho-04-transcript.md
  - ho-process/hos/ho-04.6-escape-ladder-and-click-out.md
  - ho-process/hos/ho-04.6.1-fix-pass.md
model: claude-fable-5-1
---

# Replan checkpoint — after ho-04x

The overview's second fixed checkpoint, after Phase 2 and before Phase 3. A decision session with the practitioner, not a build: six rulings, each written here with its outcome, and the documents they change revised in the same session. No code is written. Where a ruling needs code it becomes a ho with its own spec, approved before a builder starts, in a later session.

The ruling order is the State Memory's: the cost of test runs first, because it taxes every ho after this one; then the two limits ho-04 recorded; then the one design departure; then the one outward network call; then the shape of the next ho.

---

## 1. Pre-conditions

Verified at session start, 2026-11-08, on a clean tree at `def1383`.

- Phase 2 is closed and reviewed. ho-04x passed on its fourth run (2026-11-05), ho-04.5x on its first (2026-11-05), ho-04.6x on its second (2026-11-06). The Panel, Run, the Transcript, the rename, the Escape ladder and the click-out rule are built, demonstrated on the practitioner's machine, and reviewed.
- The verification stack at `def1383`: 64 app tests and 71 core tests, 0 failures; coverage HitoikiCore 95.76%, `Sources/Hitoiki` 93.73%; the floor is 90%.
- The items for this checkpoint are recorded where they arose: ho-04's Reflect (the unbroken-line cost; the input at 18), ho-04.6's Reflect (the Panel suite's cost on the practitioner's screen; recall and the history control for ho-05), ho-04.6.1's Results (Open in Terminal's one-shot message, ho-04.6x N3), and the overview's deferred decisions (the update check, 2026-11-04).
- The practitioner's machine, where the stack runs today: Apple silicon, 16 GB of memory, ten cores, 81 GB free on disk, macOS 27.0.1, Xcode 27.1, Swift 6.4, Homebrew present, Tart not installed.

---

## 2. Evaluation

**What was planned.** The overview's Phase 2 was ho-03 Panel and ho-04 Transcript, each with its x, then a week of real use whose friction would adjust ho-05 or insert a ho-04.5. Release on phase complete: v0.2.

**What was built.** ho-03 (three review runs), ho-04 (four review runs, with the standing third-Return checkpoint ruling the fix-pass specs at fault and ho-04.3 stating an invariant and nothing else), then two insertions from first use: ho-04.5, the rename from Issoku to Hitoiki, and ho-04.6, the Escape ladder and the click-out rule, which revised System Design §2.1 by amendment note. Fourteen hos and review runs since ho-03 opened, every one closed with a Pass.

**The gap.** None in the product against the plan: the core interaction works end to end on the practitioner's machines, with default settings and no macros, which is what the phase promised. The friction first use found was in the exits, and ho-04.6 answered it before this checkpoint rather than after, by the practitioner's ruling of 2026-11-04. What remains is six items the build itself raised, none of them a defect: a cost of testing, a cost of one suite, a bounded limit, a design departure, an undecided network call, and a ho that has grown.

**The call.** Continue. The plan's next two phases stand. The rulings below insert one half-number ho, split the next one, settle the update check, and defer one limit past v1.

---

## 3. Decisions and outcomes

Each ruling is the practitioner's, made in the session on 2026-11-08, with the orchestrator's recommendation stated beforehand. Where the recommendation and the ruling agree the entry says so once.

### Ruling 1 — A virtual Mac for test runs: ho-04.7, base image, before ho-05

**The problem.** The Panel suite builds a real floating window and makes it key some sixty times a run. Every run takes the practitioner's screen and keyboard for its duration, and every verification needs one run; ho-04.6 named this the first item of this checkpoint. Parking the windows off every screen needs a hook in production code and still takes the keyboard; it was rejected in ho-04.6's Reflect.

**The ruling.** A macOS guest under Tart, on Apple's virtualisation framework, with its own display inside it, so the suite's windows open there and nowhere else. The guest starts headless; a script in the repo, `scripts/vm-test.sh`, copies the working tree into it over SSH without `.build`, runs the six verification commands inside, and brings the log back. Builders and the orchestrator call the script. Nothing in the app changes.

The image is a base macOS image, about 25 GB, with the Command Line Tools and the matching Swift 6.4 toolchain installed inside it, about 35 GB in all, leaving around 45 GB free. The ready-made image with Xcode inside, about 70 GB, was declined: it would leave under 10 GB on this disk. If the Command Line Tools do not give `swift test` everything the Panel suite needs, which is the first thing ho-04.7 verifies, the fallback is Xcode inside the guest after the practitioner clears disk. The guest gets 6 GB of memory and four cores and runs only during a test run.

**Who and when.** Its own half-number ho, ho-04.7, by the overview's rule that friction from the replan week takes the next half number. Ri shape. One Opus subagent runs the setup commands on the host and writes the script. Done means the whole stack green inside the guest with the same numbers as the host, 64 and 71 tests, no window on the practitioner's screen while it runs, and the practitioner typing nothing but his approval. No review ho: it writes no application code, the same reasoning the overview gives for ho-00. It runs before ho-05.1 so ho-05's builders use it from the start.

**Until it exists.** The standing rule: one stack run per verification, asked for before it runs, the pointer parked on the screen the practitioner wants the windows on.

**Also noted.** The guest is an ordinary Mac. A throwaway clone of the base image is the honest way to run ho-06's "a fresh macOS user installs from the `.dmg`" test, and palana's and m4bmaker's tests can run there too. One base image serves every project.

### Ruling 2 — The Transcript suite stays whole

**The problem.** The Transcript suite runs about 89 seconds, almost all of it in three tests that push 50 MB through the model to prove the ceilings under real volume.

**The options.** Keep it whole; tag the three heavy tests and skip them in the everyday run; move them to a CI-only run, for which there is no CI until the practitioner opens a remote. The cost to the floor of skipping them is probably small, since the 2 MiB and 16 KiB tests walk the same ceiling code, but was not measured.

**The ruling.** Whole, nothing changes. Ruling 1 moves every run off the practitioner's screen, and once a run is waited for rather than endured, 89 seconds is a cheap price for ceiling proofs that run every time. A tag, a skip flag and a second way to run the tests would be surface for ho-05x and ho-06x to read. Revisit only if a run in the guest passes three or four minutes.

### Ruling 3 — The unbroken-line cost: deferred past v1, named in the README

**The problem.** One line past 1 MiB streams at about 5 KB/s while it runs (ho-04 Reflect, defect 4). The model keeps only the newest megabyte of a line in progress; the view does not, and every chunk drops the oldest characters from the head of a megabyte-long paragraph and lays the whole paragraph out again. The panel stays responsive, Stop and Escape act at once and draw nothing after, but Run's read-ahead fills and the command slows to the panel's pace. Lines that end stream at full speed; progress bars with carriage returns are not this case.

**The cure.** Decision 5 of ho-04 showing only the tail of a line that has grown past a size: a change to `TranscriptView`, with a run sheet on the practitioner's screen and a review.

**The ruling.** Deferred past v1. The case needs more than a megabyte of output with not one newline in it, which the seed's profile of commands does not produce and none of the ho-01 list or the run sheets produced; the realistic ways to hit it are curling a minified file, `jq -c` on a large document, or macOS's `base64`, which does not wrap, and what the user gets is a slow drip they can Stop, not a hang or a crash. The README names it in one sentence as a known limit; ho-06, which finalises the README, writes the sentence. The cure is recorded in the overview's deferred decisions so the fix can return at v2 without reopening ho-04.

### Ruling 4 — The input stays at 18

**The problem.** The command line is set at 18 points over a transcript at 12. The practitioner chose 18 by eye on 2026-11-03 after rebuilds at 12, 14, 16 and 18. The inherited pālana scale runs 10 to 15 and says emphasis comes from weight or the accent, never from a size jump.

**The ruling.** 18 stays, as a recorded departure from the inherited system. pālana's scale was written for a dense multi-pane surface where every size competes with its neighbours; Hitoiki's input is one line that is the whole interface when the panel appears, and the precedent for that is Spotlight, whose field is larger still. The judgement was made in the live app, the only place it can be. The record is a comment on `inputSize` in `PanelWindow.swift` naming the departure and this ruling, written by ho-05.1's builder when it next touches the file, and this entry.

### Ruling 5 — The update check: ho-06 builds it, ho-05.1 carries the switch, the request is fixed

**What K2 had decided.** §6: an optional check against GitHub's latest-release endpoint, on by default, disclosed in settings, with a manual Check for Updates; palana's 99-line checker ported; no telemetry, no identifiers, no command text leaves the machine. §2.4: the on/off toggle among the settings. Open at this checkpoint: what is sent, how often, and where it is built.

**The ruling.**

- **What is sent.** One GET to GitHub's releases-latest endpoint for the Hitoiki repository. No body, no query, no account, no identifier. The User-Agent is set explicitly to `Hitoiki/<version>` and nothing more; the system's default string, which palana lets through, names the networking library and OS versions, and GitHub requires a user agent so it cannot be empty. The README's Privacy section quotes the request in full, and ho-06x reads the code against it word for word.
- **How often.** At launch and then once a day while the app is running. The last-checked time is held in memory only, so no persisted key appears beyond the ones K2 §2.4 names and ho-05x questions. palana's launch-only cadence suits an app opened daily; Hitoiki is resident for weeks.
- **The default.** On, as K2 says, reading as on when the key is absent, palana's pattern. The switch lives in ho-05.1's settings window.
- **Where.** ho-06, The Ship, since the check needs a release to compare against.
- **What the user sees.** Nothing, nearly always. When a newer release exists, a quiet line under the gear, "1.1 available", opens the download page. The gear's Check for Updates asks on demand. In settings, the toggle and a line saying what the check does.

The practitioner declared this shape his standard for every project. K2 §2.4 and §6 each take a dated amendment note pointing here, forward-only.

### Ruling 6 — ho-05 splits at the storage boundary: ho-05.1 Settings and macros, ho-05.2 History

**The scope carried in.** Everything the overview's ho-05 entry names, plus: up-arrow recall of the commands run since launch, session memory first and the history file's commands when it is on; a control on the bar that drops that list (both ruled 2026-11-05); the list carried from ho-03 (`Panel.init(directory:)`, validating a stored directory, `Hotkey.combination` and `displayName` for the recorder, the terminal bundle-id list in ho-03 Decision 12, Refresh Environment with ho-02x's N2 test); Open in Terminal's one-shot message (ho-04.6x N3), since the terminal picker makes this the next ho to touch that path; the comment on the 18 from Ruling 4; the update toggle from Ruling 5. Out: the checker itself, transcript storage, output history by scrolling, a Clear button on the panel.

**A distinction kept.** What the practitioner refused on 2026-11-05 was a Clear button on the panel, Escape being the panel's clear, and keeping earlier commands' output on the panel to scroll back through. Command history was never refused: recall, the bar control and the file all stand. The Clear in settings that deletes the history file is K2 §2.4's and stands.

**The ruling.** ho-05 was the largest ho since ho-03 and is split now rather than at its Think, into two hos cut at the boundary ho-05x already reviews on, each with its own review:

- **ho-05.1 — Settings and macros.** Everything that lives in user defaults: the settings window with the shortcut recorder, the working-directory mode, the terminal picker, the three toggles (history, menu bar item, update check), Refresh Environment, and the nine macro slots loading on `Command-1` through `Command-9`. Carries the ho-03 list, N3, and the comment on the 18. Then ho-05.1x.
- **ho-05.2 — History.** Everything that lives in the text file, and recall: the file written on Return, up-arrow recall from session memory and from the file when it is on, the control on the bar, Clear in settings, and the toggle's effect. Then ho-05.2x.

Three sub-hos were considered and declined: macros alone are nine slots in user defaults, a thin ho with a review attached.

---

## 4. Handoff

**Next session: ho-04.7, the virtual Mac.** Author its spec with the Kamae 5 skill, ri shape, from Ruling 1. Its Think has one discovery to settle first: which Tart image for macOS 27 exists and whether the Command Line Tools alone carry what `swift test` needs for a package importing AppKit. The builder's acceptance is the whole stack green inside the guest with the host's numbers and nothing on the practitioner's screen.

**Then ho-05.1, ho-05.1x, ho-05.2, ho-05.2x, ho-06, ho-06x.** The app is feature-complete against the seed's first version after ho-05.2x and publishable after ho-06x. The icon is the one artefact ho-06 needs that no ho produces.

**Documents this session changes.** The overview: the Phase 2 checkpoint paragraph, a ho-04.7 entry, the Phase 3 paragraph and entries, the Phase 4 ho-06 entry, the phase table, the checkpoint and splits sections, the deferred decisions, the dependency summary, and a build-record entry. K2: amendment notes under §2.4 and §6. The State Memory block and the roster.

**Standing rules carried forward.** Answer the practitioner's questions before acting, in prose. No test run on his screen without his word, and one run per verification, until ho-04.7 closes. No builder launches the app. Redact hosts and users in anything committed under `ho-process/`.

### Closing this ho

Closed in the session. `status: complete` in the frontmatter; the state-summary block written to `ho-process/kamae-6-hitoiki-state-memory.md`; the build-record entry appended to the overview; the roster refreshed. The block, verbatim labels and order:

**STATE-SUMMARY**
- **COMPLETED** — The replan checkpoint after ho-04x: six rulings recorded, the overview and K2 revised to match.
- **NEXT** — ho-04.7, the virtual Mac for test runs: author its spec with the Kamae 5 skill in a fresh session.
- **ACTION ITEMS / BLOCKS** — None blocking. Until ho-04.7 closes, one stack run per verification, asked for first.
- **PROJECT LIFECYCLE** — kamae

---

_Authored: 2026-11-08 (orchestrator, with the practitioner, in the session)._
_Execution: N/A — a decision session; no code._
