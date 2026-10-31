---
created: 2026-10-26
status: complete
type: ho-document
project: issoku
ho: 02x
kamae: 5
shape: x
phase: 1 — The Process Model
title: Review of Run — the production process model
description: Rechecks the full Run implementation and its ho-02.1 fix pass against the standing brief, with a report and a Pass or Return verdict.
reviews: ho-02
run: 2
model: gpt-6.1-sol
builds-on:
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-02-run.md
  - ho-process/hos/ho-02.1-fix-pass.md
---

# ho-02x — Review of Run — the production process model

You are the antagonist for ho-02. You did not write this code. You review one bounded unit of work against the spec that bounded it, report findings, and give a verdict. You change no source files.

This is the first review of code that ships. The unit is `Sources/IssokuCore/Run/` with its tests and fixture, plus the driver `Sources/IssokuRunCLI/`, which the spec's Decision 8 says exists for ho-02 only and is deleted at ho-03's first commit; review the driver for what it does to the terminal and to Run, not for its own test coverage, which the spec excludes. The spec's Reflect records what execution surfaced, including two facts for you: in one process, two concurrent `forkpty` calls intermittently fail with errno −6, so the Run test suite is `.serialized`; and the child closes descriptors 3 up to `getdtablesize()` before `execve`, which costs about 8 ms per spawn under a terminal launch. The practitioner's run-sheet transcript in Reflect is redacted and is evidence, not a claim for you to re-run against a host; nothing you run touches a live host.

**Run 2.** Run 1 (`ho-process/reviews/ho-02x-report-1.md`) returned ho-02 with four Must-fix findings and one Should-fix. The fix pass `ho-process/hos/ho-02.1-fix-pass.md` answers them and ends the range below. Read the whole unit again, not just the fixes, against both specs. Rate any run-1 finding you judge unanswered as you would any other. The builder's verification is evidence to check, not a verdict.

**Goal**

A written report at the path named under Files, answering every question in the brief with file and line references or the word "none", with each finding rated, ending in one verdict: Pass or Return.

**Inputs**

- Build ho spec: `ho-process/hos/ho-02-run.md`
- Fix-pass spec: `ho-process/hos/ho-02.1-fix-pass.md`
- Previous report: `ho-process/reviews/ho-02x-report-1.md`
- Commit range: `0f2630b7ee6a2e820de43276b921d3afa8c81745..46f78c9b233da6e0029911ca5d44d15e43205553`
- The seed, sections 8 and 12: `ho-process/kamae-1-issoku-seed.md`
- The System Design, for the component boundaries: `ho-process/kamae-2-issoku-system-design.md`

**Files**

- Read-only: everything in the commit range, via `git diff 0f2630b7ee6a2e820de43276b921d3afa8c81745..46f78c9b233da6e0029911ca5d44d15e43205553`
- Read-only: the inputs above
- Create: `ho-process/reviews/ho-02x-report-2.md`

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

- Is there any process-handling code the spike did not prove? Anything new here that ho-01's findings did not cover is unverified by definition.
- Does the `-tt` rule do exactly one insertion and nothing else? Find any other way the typed line can be altered.
- Does the orphan test actually inspect the process table, or does it trust the component's own report?
- Does Run know anything about Panel, Transcript, or Memory? Any import or type reference across that boundary is a Must fix.

**Report format**

```markdown
# ho-02x report, run 2

Commit range: 0f2630b7ee6a2e820de43276b921d3afa8c81745..46f78c9b233da6e0029911ca5d44d15e43205553
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

- [ ] `swift build` was run by you and its result is recorded in the report.
- [ ] `swift test` was run by you and its result is recorded in the report.
- [ ] The coverage script was run by you and its number is recorded.
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
git diff --stat 0f2630b7ee6a2e820de43276b921d3afa8c81745..46f78c9b233da6e0029911ca5d44d15e43205553
git status --porcelain      # expect only: ?? ho-process/reviews/ho-02x-report-2.md
```

**Do not**

- Modify, format, or lint any file in the diff.
- Add tests, fixtures, or comments to the code under review.
- Propose a redesign, an alternative architecture, or a library.
- Summarise what the code does or praise any part of it.
- Soften a Must-fix to a Should-fix because the fix looks large.
- Trust the build ho's own claims about passing tests; run them.
- Run any command against a remote host. The run sheet was the practitioner's; the tests are local.

**Commit**

Commit only the report.

```
ho-02x: review of ho-02, run 2 — <Pass | Return>
```

No trailers, no co-author lines.
