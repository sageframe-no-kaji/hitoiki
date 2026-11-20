---
created: 2026-11-19
status: ready
type: ho-document
project: hitoiki
ho: 08x
kamae: 5
shape: x
phase: 4 — The Ship
title: Review of The First Launch
description: A scoped review of ho-08's pull request — the welcome window, the menu bar default and the documents that follow them — read against ho-08's spec, ending in a report and a Pass or Return verdict.
reviews: ho-08
run: 1
model: gpt-6-astra
builds-on:
  - kamae-4-hitoiki-ho-overview
  - ho-process/hos/ho-08-the-first-launch.md
---

# ho-08x — Review of The First Launch

You are the antagonist for ho-08. You did not write this code or these documents. You review one bounded unit of work against the spec that bounded it, report findings, and give a verdict. You change no source files.

**Use the `$ho-antagonist-review` skill**, reviewer role, ho-review mode (`references/standards.md`, `references/ho-review.md`, `references/cycle.md`). Pin it at Ho System commit `552fb4a`, subdirectory `skills/ho-antagonist-review`, and record that in the report. This document is the review context: it names the unit, the revisions, the requirements, the pass (1 of 2; a third only by ruling), the verification and the report's path and format. Where this document and the skill differ, this document binds: the report goes to the path under Files, in the format below, and is the only file you commit.

**This is a scoped review.** Read only the branch's diff, `3b0c944..45c10a1`, against `ho-process/hos/ho-08-the-first-launch.md`. The rest of the codebase passed earlier reviews; read it only where the diff depends on it. Rate nothing outside the diff.

The unit:

1. **The welcome window** (Decisions 1–3): `Sources/Hitoiki/WelcomeWindow.swift` (new), `Sources/Hitoiki/App.swift`, the `welcomeShown` key in `Sources/Hitoiki/Settings.swift`, tests in `Tests/HitoikiTests/WelcomeWindowTests.swift` (new).
2. **The menu bar default** (Decision 4): `Sources/Hitoiki/Settings.swift`, `Tests/HitoikiTests/SettingsTests.swift`, `Tests/HitoikiTests/MenuBarItemTests.swift`.
3. **The documents** (Decision 5): `README.md`, `TECHNICAL.md`, `packaging/release-notes-1.0.1.md` (new).
4. **Two additions by the orchestrator, outside the spec's file list and accounted for here:** a dated amendment in `ho-process/kamae-2-hitoiki-system-design.md` (§2.4, 2026-11-19) recording the menu bar default and the welcome window, and one test title in `Tests/HitoikiTests/SettingsWindowTests.swift` changed from "ten" to "eleven" settings keys. Rate them only where they are false.

The welcome window's face is built with AppKit labels and buttons, where About uses SwiftUI; the builder chose this so tests can read each line and press each button. The spec's "built like About" names the window's size, colours, title bar, movability, centring and activation. Rate the choice only if a behaviour or appearance the spec states differs.

Decision 3 is unverified by ruling: whether macOS sets the login-item mark for an `SMAppService` login item is not tested, and there is no run-sheet test for it. Rate only whether the code reads the mark as Decision 3 describes.

`.keisaku.json` is modified in the working tree by another tool; it is not in the range. Leave it.

Tests run through `scripts/vm-test.sh`, which starts the Tart guest `hitoiki-test`, copies the tree in, runs the six verification commands inside and brings the log back to `.build/vm-test/`. Run that script, once, from the repository root, and read its log; do not run `swift test` or `swift build` on this machine, and do not pass `--skip`. A run takes about eight minutes. Do not launch the app. Do not run `scripts/build_macos.sh` in any form, and do not open `scripts/.env`.

**Goal**

A written report at the path named under Files, answering every question in the brief with file and line references or the word "none", with each finding rated, ending in one verdict: Pass or Return.

**Inputs**

- Build ho spec: `ho-process/hos/ho-08-the-first-launch.md` (Decisions 1–5, What the tests establish)
- Commit range: `3b0c944..45c10a1`
- The seed, sections 8 and 12: `ho-process/kamae-1-hitoiki-seed.md`
- The System Design, for the component boundaries: `ho-process/kamae-2-hitoiki-system-design.md`

**Files**

- Read-only: everything in the commit range, via `git diff 3b0c944..45c10a1`
- Read-only: the inputs above, and the code the diff calls into
- Create: `ho-process/reviews/ho-08x-report-1.md`

No other file is created or modified.

**The brief**

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

**Ho-specific questions**

- **Is each decision built as written?** For Decisions 1–4, name each departure in text, layout, button, default key, or behaviour, with the spec's line and the code's line. Check the exact strings of Decision 1 against `WelcomeWindow.swift`.
- **Does the window show exactly once?** Trace every path: key absent and not at login, key absent at login, key true at login or not, a quit with the window open, reopen, settings, About, Check for Updates. Is there any path that shows it twice, or never on a first launch by hand?
- **Do the tests establish the spec's invariants?** For each item under "What the tests establish", name the test that would fail if the behaviour were wrong, and name any listed partition with no test. Which of these tests fail on the code at `3b0c944`?
- **Does any document claim more than the code does?** Read the changed lines of `README.md` and `TECHNICAL.md`, all of `packaging/release-notes-1.0.1.md`, and the K2 amendment against the code at `45c10a1`. Name each false or unsupported claim with both lines.
- **Does anything else change?** Any change under `Sources/`, `Tests/`, `Package.swift` or `scripts/` outside the unit listed above; any new dependency; anything in the diff that should not be published (credentials, host names, home paths, addresses, attribution lines).

**Report format**

```markdown
# ho-08x report, run 1

Commit range: 3b0c944..45c10a1
Build: <pass | fail, with the command's last lines if fail>
Tests: <N passed, M failed>
Coverage: <percent, from the coverage script>

## Findings

### Must fix
- <file:line> — <one sentence stating the defect>. <Which brief question or spec line it violates.>

### Should fix
- ...

### Note
- ...

## Brief questions
1. <answer or "none">
2. ...
7. ...

## Ho-specific questions
- <answer or "none">

## Verdict
<Pass | Return>
```

Every finding carries a `file:line`. A question with no finding is answered "none", not omitted. No section is skipped.

**Acceptance**

- [ ] `scripts/vm-test.sh` was run by you, once, and each of its six commands' exit status, both "Test run with" lines of each test step, and both coverage numbers are recorded in the report from its log.
- [ ] All seven brief questions are answered.
- [ ] All five ho-specific questions are answered.
- [ ] Every finding has a file and line and a rating.
- [ ] The verdict is Pass if and only if there are zero Must-fix findings.
- [ ] `git status` shows exactly one new file, the report, and no other change beyond the pre-existing `.keisaku.json`.

**Verification**

```bash
scripts/vm-test.sh                     # the six commands in the guest; read the log it names last
git diff --stat 3b0c944..45c10a1
git diff 3b0c944..45c10a1 -- Sources Tests Package.swift scripts
git diff 3b0c944..45c10a1 -- README.md TECHNICAL.md packaging ho-process/kamae-2-hitoiki-system-design.md
git log --format=%B 3b0c944..45c10a1
git status --porcelain                 # expect only: ?? ho-process/reviews/ho-08x-report-1.md and  M .keisaku.json
```

**Do not**

- Modify, format, or lint any file in the diff.
- Add tests, fixtures, or comments to the code under review.
- Propose a redesign, an alternative architecture, or a library.
- Re-rate the rulings in the spec, or rate wording where every claim is true.
- Rate code outside the diff.
- Summarise what the code does or praise any part of it.
- Soften a Must-fix to a Should-fix because the fix looks large.
- Trust the build ho's own claims about passing tests; run them, through the script.
- Launch the app, or run `swift test` or `swift build` outside the script, or run `scripts/build_macos.sh`, or push, tag, or touch any remote.

**Commit**

Commit only the report.

```
ho-08x: review of ho-08, run 1 — <Pass | Return>
```

No trailers, no co-author lines.
