# x ho template — the review spec

Repo-local for now. This is the skeleton the Kamae 5 skill fills when a build ho closes and its x ho opens. It produces one file, `ho-process/hos/ho-NNx-review-of-<title>.md`, which the antagonist reads as its whole instruction. If the pattern holds across Issoku it moves into the skill; until then it lives here and the skill is told to read it.

## How an x ho runs

1. The build ho's session ends with its closing commit. Note the hash. Note the hash of the commit the build ho opened on.
2. Author the x ho document from the template below. Fill every `<...>`. Paste the brief from the Ho Overview's "The antagonist brief" section verbatim; do not paraphrase it and do not keep a second copy anywhere else.
3. Open a fresh Codex session in the repo, checked out at the closing commit, with no prior conversation. Give it the x ho document and nothing else.
4. Codex writes its report to the path the document names, and nothing else. It commits only that file.
5. Read the report against the diff yourself. Pass closes the build ho. Return opens a fix pass (`ho-NN.1`), after which this same x ho runs again with a new commit range and a new report number.
6. Append the verdict to the overview's build record.

---

## Template

````markdown
---
created: <YYYY-MM-DD>
status: ready
type: ho-document
project: issoku
ho: <NN>x
kamae: 5
shape: x
phase: <phase number — phase name>
reviews: ho-<NN>
run: <1 on the first run; 2, 3 after each Return>
model: <exact Codex model id in use>
builds-on:
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-<NN>-<title>.md
---

# ho-<NN>x — Review of <build ho title>

You are the antagonist for ho-<NN>. You did not write this code. You review one bounded unit of work against the spec that bounded it, report findings, and give a verdict. You change no source files.

**Goal**

A written report at the path named under Files, answering every question in the brief with file and line references or the word "none", with each finding rated, ending in one verdict: Pass or Return.

**Inputs**

- Build ho spec: `ho-process/hos/ho-<NN>-<title>.md`
- Commit range: `<opening-hash>..<closing-hash>`
- The seed, sections 8 and 12: `ho-process/kamae-1-issoku-seed.md`
- The System Design, for the component boundaries: `ho-process/kamae-2-issoku-system-design.md`

**Files**

- Read-only: everything in the commit range, via `git diff <opening-hash>..<closing-hash>`
- Read-only: the three inputs above
- Create: `ho-process/reviews/ho-<NN>x-report-<run>.md`

No other file is created or modified.

**The brief**

<Paste the Ho Overview's "The antagonist brief" here, verbatim, from "You are reviewing one bounded unit of work" through "Findings and a verdict.">

**Ho-specific questions**

<Paste this x ho's "Ho-specific questions" from the Ho Overview, verbatim.>

**Report format**

```markdown
# ho-<NN>x report, run <run>

Commit range: <opening-hash>..<closing-hash>
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
scripts/coverage-floor.sh
git diff --stat <opening-hash>..<closing-hash>
git status --porcelain      # expect only: ?? ho-process/reviews/ho-<NN>x-report-<run>.md
```

**Do not**

- Modify, format, or lint any file in the diff.
- Add tests, fixtures, or comments to the code under review.
- Propose a redesign, an alternative architecture, or a library.
- Summarise what the code does or praise any part of it.
- Soften a Must-fix to a Should-fix because the fix looks large.
- Trust the build ho's own claims about passing tests; run them.

**Commit**

Commit only the report.

```
ho-<NN>x: review of ho-<NN>, run <run> — <Pass | Return>
```

No trailers, no co-author lines.
````

---

## Notes for the Kamae 5 skill

- `shape: x` is new. It has no Think phase: the thinking happened in the overview and the brief. Authoring an x ho is filling the template, nothing more. If the skill finds itself deciding anything while authoring one, that is a gap in the overview, and the fix goes there.
- The `run` field and the report number advance together. Run 1 reviews the build ho's closing commit. Run 2 reviews the fix pass's closing commit, with the range starting at the build ho's original opening commit, so the whole unit is read again, not just the fix.
- `model` is the exact Codex model id in use at the time, not the word "codex". An unset model is an unmade decision.
- The report directory `ho-process/reviews/` is created by ho-00 and committed with a `.gitkeep`.
- ho-01x is the one exception to "the diff": its input is the spike's findings document, and its Files section reads that document instead of a commit range. The template still applies; the commit range line names the findings document's path.
