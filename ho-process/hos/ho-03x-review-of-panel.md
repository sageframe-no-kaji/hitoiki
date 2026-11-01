---
created: 2026-10-31
status: ready
type: ho-document
project: issoku
ho: 03x
kamae: 5
shape: x
phase: 2 — The Surface
title: Review of Panel — the only visible surface
description: Checks the Panel build against the standing brief and the four ho-03x questions, with a report and a Pass or Return verdict.
reviews: ho-03
run: 1
model: gpt-6.1-sol
builds-on:
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-03-panel.md
---

# ho-03x — Review of Panel — the only visible surface

You are the antagonist for ho-03. You did not write this code. You review one bounded unit of work against the spec that bounded it, report findings, and give a verdict. You change no source files.

The unit is `Sources/Issoku/` as ho-03 left it (App, Panel, Keystrokes, Hotkey, PanelWindow, TranscriptPlaceholder, SettingsWindow), its three test files under `Tests/IssokuTests/`, and the second measured set in `scripts/coverage-floor.sh`. The range also deletes `Sources/IssokuRunCLI/` and its product, which ho-02 ruled; that deletion is not under review. `Sources/IssokuCore/` does not change in this range. The spec's Reflect records what execution surfaced, including facts for you: the range holds five commits because the practitioner's run sheet produced Decisions 17 and 18 after the build commit; the Panel tests construct a real `PanelWindow` in the test process and are `.serialized`; the subagent read a whitespace-only Return as the empty Return that takes the `-tt` offer, and the spec's Decision 9 says both. The practitioner's run sheet in Reflect is redacted and is evidence, not a claim for you to re-run against a host; nothing you run touches a live host. The hotkey firing and the Dock icon's absence are witnessed only by the run sheet; say so rather than counting them untested.

**Goal**

A written report at the path named under Files, answering every question in the brief with file and line references or the word "none", with each finding rated, ending in one verdict: Pass or Return.

**Inputs**

- Build ho spec: `ho-process/hos/ho-03-panel.md`
- Commit range: `f371d87b18d101c5c9ea46bcace9ed3102939067..ed9ee98d83920ccb8df345206f19372eb7185f68`
- The seed, sections 8 and 12: `ho-process/kamae-1-issoku-seed.md`
- The System Design, for the component boundaries: `ho-process/kamae-2-issoku-system-design.md`

**Files**

- Read-only: everything in the commit range, via `git diff f371d87b18d101c5c9ea46bcace9ed3102939067..ed9ee98d83920ccb8df345206f19372eb7185f68`
- Read-only: the three inputs above
- Create: `ho-process/reviews/ho-03x-report-1.md`

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

- How many representations of the Composing, Running, and Done state exist? One is correct. Find the second.
- Is there any SwiftUI in the panel window itself? The System Design allows it only in settings.
- Does the dismiss rule live in one place, or is "can I dismiss right now" computed in several?
- Is the hotkey registration the direct system call, or has a wrapper appeared around it?

**Report format**

```markdown
# ho-03x report, run 1

Commit range: f371d87b18d101c5c9ea46bcace9ed3102939067..ed9ee98d83920ccb8df345206f19372eb7185f68
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

Every finding carries a `file:line`. A question with no finding is answered "none", not omitted. No section is skipped. The coverage script prints two numbers; record both.

**Acceptance**

- [ ] `swift build` was run by you and its result is recorded in the report.
- [ ] `swift test` was run by you and its result is recorded in the report.
- [ ] The coverage script was run by you and both its numbers are recorded.
- [ ] All seven brief questions are answered.
- [ ] All ho-specific questions are answered.
- [ ] Every finding has a file and line and a rating.
- [ ] The verdict is Pass if and only if there are zero Must-fix findings.
- [ ] `git status` shows exactly one new file, the report, and no modified files.

**Verification**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -5
swift test --enable-code-coverage >/dev/null 2>&1 && scripts/coverage-floor.sh
git diff --stat f371d87b18d101c5c9ea46bcace9ed3102939067..ed9ee98d83920ccb8df345206f19372eb7185f68
git status --porcelain      # expect only: ?? ho-process/reviews/ho-03x-report-1.md
```

**Do not**

- Modify, format, or lint any file in the diff.
- Add tests, fixtures, or comments to the code under review.
- Propose a redesign, an alternative architecture, or a library.
- Summarise what the code does or praise any part of it.
- Soften a Must-fix to a Should-fix because the fix looks large.
- Trust the build ho's own claims about passing tests; run them.
- Run any command against a remote host. The run sheet was the practitioner's; the tests are local.
- Launch `.build/debug/Issoku` with the practitioner's instance running, or leave one running; the tests spawn their own processes and the review needs no window on screen.

**Commit**

Commit only the report.

```
ho-03x: review of ho-03, run 1 — <Pass | Return>
```

No trailers, no co-author lines.
