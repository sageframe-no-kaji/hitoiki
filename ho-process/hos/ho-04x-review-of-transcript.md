---
created: 2026-11-04
status: ready
type: ho-document
project: issoku
ho: 04x
kamae: 5
shape: x
phase: 2 — The Surface
title: Review of Transcript — the one monospace zone
description: Rechecks the Transcript build and its ho-04.1 fix pass against the standing brief and the three ho-04x questions, with a report and a Pass or Return verdict.
reviews: ho-04
run: 2
model: gpt-6.1-sol
builds-on:
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-04-transcript.md
  - ho-process/hos/ho-04.1-fix-pass.md
---

# ho-04x — Review of Transcript — the one monospace zone

You are the antagonist for ho-04. You did not write this code. You review one bounded unit of work against the spec that bounded it, report findings, and give a verdict. You change no source files.

The unit is `Sources/IssokuCore/Transcript/Transcript.swift` (the model: bytes in, a change out), `Sources/Issoku/TranscriptView.swift` (the view, replacing `TranscriptPlaceholder.swift`, which the range deletes), the three derived colours and the colour table in `Sources/Issoku/Theme.swift`, the two-card layout and the strip in `Sources/Issoku/PanelWindow.swift`, the bytes task and the Stop flag in `Sources/Issoku/Panel.swift`, the renamed exclusion in `scripts/coverage-floor.sh`, and the tests in `Tests/IssokuCoreTests/TranscriptTests.swift`, `Tests/IssokuTests/PanelTests.swift` and `Tests/IssokuTests/ThemeTests.swift`. `Sources/IssokuCore/Run/` does not change in this range. The spec's Reflect records what execution surfaced, including facts for you: the range holds five commits because the practitioner's run sheet found four defects the test harness could not show and produced three rulings (the input at 18; after Stop nothing more is drawn, which is the `stopped` flag in Panel; the Escape ladder, which is a later ho and not in this code); the view uses non-contiguous layout and appends to a line that only grew, both for measured cost; the practitioner ruled that `Theme.swift` keeps its SwiftUI accessors though the panel does not use them. The practitioner's run sheet in Reflect is redacted and is evidence, not a claim for you to re-run against a host; nothing you run touches a live host. The colours on screen, the cursor's drawing, the wrap and the jiggle are witnessed only by the run sheet; say so rather than counting them untested. The builder's verification is evidence to check, not a verdict.

**Run 2.** Run 1 (`ho-process/reviews/ho-04x-report-1.md`) returned ho-04 with three Must-fix findings, one Should-fix and three Notes. The fix pass `ho-process/hos/ho-04.1-fix-pass.md` answers the four and takes all three Notes: the per-line cap is enforced as bytes arrive, through a 16 KiB slack in `put` and a trim in `commit()`, so an LF commits at most 1 MiB however the bytes were chunked; a control string ends only at BEL or `ESC \`, through a control-string-escape state; `Theme.swift` has its SwiftUI accessors back as at the range start; SGR 58 is consumed with its arguments, by the practitioner's ruling, added to the consumed-and-ignored set of Decision 1; the ceiling and bound tests assert the specified literals and the large lines commit; scroll-follow and Command-C-while-Running have tests; the reversed counts are corrected with marks. Its Results record three facts for you: the feed-end trim stays beside the mid-feed trim, so a carriage-return overwrite in the instant after an end trim could still differ by chunking, untested; Decision 1's terminator rule differs from the DEC parser, which ends a control string at any ESC, a difference only for malformed streams, and the fix implements Decision 1; `Theme.swift` reads 84.21% with the accessors unused by the panel, which the practitioner ruled. Read the whole unit again, not just the fixes, against both specs. Rate any earlier finding you judge unanswered as you would any other.

**Goal**

A written report at the path named under Files, answering every question in the brief with file and line references or the word "none", with each finding rated, ending in one verdict: Pass or Return.

**Inputs**

- Build ho spec: `ho-process/hos/ho-04-transcript.md`
- Fix-pass spec: `ho-process/hos/ho-04.1-fix-pass.md`
- Commit range: `e08c5ea0be1ed6443a6327869dda6f39ba7cab0a..1b42564a4e50cde41dede933e2186eae189c24ff`
- The seed, sections 8 and 12: `ho-process/kamae-1-issoku-seed.md`
- The System Design, for the component boundaries: `ho-process/kamae-2-issoku-system-design.md`

**Files**

- Read-only: everything in the commit range, via `git diff e08c5ea0be1ed6443a6327869dda6f39ba7cab0a..1b42564a4e50cde41dede933e2186eae189c24ff`
- Read-only: the three inputs above
- Create: `ho-process/reviews/ho-04x-report-2.md`

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

- List every escape sequence the code recognises. Compare it to the ho-01 list. Anything not on the list is scope creep.
- Is the memory ceiling enforced by measurement in a test, or asserted in a comment?
- Does Transcript know anything about Run beyond receiving bytes?

**Report format**

```markdown
# ho-04x report, run 2

Commit range: e08c5ea0be1ed6443a6327869dda6f39ba7cab0a..1b42564a4e50cde41dede933e2186eae189c24ff
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
git diff --stat e08c5ea0be1ed6443a6327869dda6f39ba7cab0a..1b42564a4e50cde41dede933e2186eae189c24ff
git status --porcelain      # expect only: ?? ho-process/reviews/ho-04x-report-2.md
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
ho-04x: review of ho-04, run 2 — <Pass | Return>
```

No trailers, no co-author lines.
