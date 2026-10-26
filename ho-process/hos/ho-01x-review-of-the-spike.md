---
created: 2026-10-25
status: ready
type: ho-document
project: issoku
ho: 01x
kamae: 5
shape: x
phase: 1 — The Process Model
reviews: ho-01
run: 2
model: gpt-6.1-sol
builds-on:
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-01-the-spike.md
---

# ho-01x — Review of The Spike — prove the pseudoterminal process model

You are the antagonist for ho-01. You did not write this code. You review one bounded unit of work against the spec that bounded it, report findings, and give a verdict. You change no source files.

ho-01 is the one x ho whose input is not a diff. The spike's code under `spike/` is discarded at ho-02, so the unit under review is the findings document: for each of the six decisions, whether the recorded answer is supported by something you can see. The commit-range line below names that document in place of a range; the commits are given so you can read the spike's harness and spec as they were closed.

**Run 2.** Run 1 (`ho-process/reviews/ho-01x-report-1.md`) returned ho-01 with five Must-fix findings. The fix pass `ho-process/hos/ho-01.1-fix-pass.md` answers them, and its closing commit ends the range below. The whole unit is read again, not just the fix; the findings document carries a "Corrected in ho-01.1" section naming what changed and why, and the ho-01 spec marks its two corrected sentences in place. Rate any finding from run 1 that you judge unanswered as you would any other.

**Goal**

A written report at the path named under Files, answering every question in the brief with file and line references or the word "none", with each finding rated, ending in one verdict: Pass or Return.

**Inputs**

- Build ho spec: `ho-process/hos/ho-01-the-spike.md`
- Commit range: `ho-process/hos/ho-01-spike-findings.md` (the findings document; ho-01 opened on `ee95ee71f25877574df7302f5e88e8908e6458eb` and closed on `8e0b8d1a96bf1647b279aa6cdc036338e51cb4f6`, the closing commit of the fix pass ho-01.1)
- The seed, sections 8 and 12: `ho-process/kamae-1-issoku-seed.md`
- The System Design, for the component boundaries: `ho-process/kamae-2-issoku-system-design.md`

**Files**

- Read-only: `ho-process/hos/ho-01-spike-findings.md`, and everything in `git diff ee95ee71f25877574df7302f5e88e8908e6458eb..8e0b8d1a96bf1647b279aa6cdc036338e51cb4f6` (the harness under `spike/`, the spec, the overview's build record) as context for whether the findings are reproducible
- Read-only: the three other inputs above
- Create: `ho-process/reviews/ho-01x-report-2.md`

No other file is created or modified. The findings name hosts, addresses, the ssh user, the key file, a pool and the machine by placeholder (`host-a`, `<lan-ip-a>`, `<user>`, `<key>`, `pool-a`, `<mac>`); that is deliberate redaction, not missing evidence, and the real values are not available to you. Do not run the spike against any host.

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

- For each decision, is the evidence reproducible from what is recorded? Could the practitioner rerun it?
- Is the terminal-control list the result of running the real command set, or an assertion?
- Do the latency and memory numbers name the machine, the host, and the conditions?
- Does the findings document recommend anything the decisions did not ask for? If so, flag it as scope the spike is trying to smuggle into ho-02.

**Report format**

```markdown
# ho-01x report, run 2

Commit range: ho-process/hos/ho-01-spike-findings.md (ee95ee71f25877574df7302f5e88e8908e6458eb..8e0b8d1a96bf1647b279aa6cdc036338e51cb4f6)
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
- [ ] `swift build -c release --package-path spike` was run by you and its result is recorded in the report.
- [ ] All seven brief questions are answered.
- [ ] All ho-specific questions are answered.
- [ ] Every finding has a file and line and a rating.
- [ ] The verdict is Pass if and only if there are zero Must-fix findings.
- [ ] `git status` shows exactly one new file, the report, and no modified files.

**Verification**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -5
scripts/coverage-floor.sh
swift build -c release --package-path spike 2>&1 | tail -3
git diff --stat ee95ee71f25877574df7302f5e88e8908e6458eb..8e0b8d1a96bf1647b279aa6cdc036338e51cb4f6
git status --porcelain      # expect only: ?? ho-process/reviews/ho-01x-report-2.md
```

**Do not**

- Modify, format, or lint any file in the diff.
- Add tests, fixtures, or comments to the code under review.
- Propose a redesign, an alternative architecture, or a library.
- Summarise what the code does or praise any part of it.
- Soften a Must-fix to a Should-fix because the fix looks large.
- Trust the build ho's own claims about passing tests; run them.
- Run any command from the findings against a real host.

**Commit**

Commit only the report.

```
ho-01x: review of ho-01, run 2 — <Pass | Return>
```

No trailers, no co-author lines.
