# Issoku 一息

Run one shell command from a floating panel. Read the result. Dismiss it.

## Languages

@~/.claude/modules/languages-swift.md

## Reading order for a fresh session

1. `ho-process/kamae-6-issoku-state-memory.md`, when present — current operational state (Kamae 6); it is gitignored, so a fresh clone has none
2. `README.md` — what the project is (Kamae 3)
3. `ho-process/kamae-2-issoku-system-design.md` — committed architecture and stack (Kamae 2)
4. `ho-process/kamae-4-issoku-ho-overview.md` — build sequence (Kamae 4)
5. The current ho in `ho-process/hos/` — the bounded scope for this session (Kamae 5)

## Verification rhythm

Run after every implementation, before every commit:

- `swift-format lint --recursive --strict Sources Tests`
- `swiftlint lint --strict`
- `swift build`
- `swift test`
- `swift test --enable-code-coverage && scripts/coverage-floor.sh`

Coverage floor: **≥90% line coverage on IssokuCore**, enforced by `scripts/coverage-floor.sh`.

## Kokoroe

- **The spec is the authorization.** The ho document bounds the session; work outside it is not authorized by momentum.
- **Verify by command, not by assertion.** A claim that the build passes is a `swift build` transcript, not a sentence.
- **Halt on surprise.** Unexpected state, failing assumptions, or off-spec discoveries stop the work and surface to the practitioner.
- **Propose, don't decide.** Architectural questions the documents don't answer go back to the practitioner. The coding session does not silently make the call.

## Hard rules (Issoku-specific)

- The System Design's decisions are closed. A question it does not answer stops the work.
- Every build ho from ho-01 is reviewed by an x ho. The reviewer is Codex, in a fresh session, from `ho-process/hos/ho-NNx-review-of-<title>.md`. No reviewer subagents run inside Claude Code.
- The Kamae 5 skill authors `shape: x` documents from `ho-process/x-ho-template.md`; the template is the authority until it moves into the skill.
- Tests never touch live hosts. The ho-01 spike runs against real hosts only the commands its spec lists, every one read-only; the sudo password is typed by the practitioner and by no one else.
- No AI attribution in commits, PRs, or code. No `Co-Authored-By`, no "Generated with". Strip any template that adds one.
- No dependencies in `Package.swift` at v1. A dependency is an architectural question for the practitioner.
- No secrets in the repository. `ho-process/` is public; only the State Memory (`kamae-6-issoku-state-memory.md`) is gitignored.

## Project structure

- Multi-product Swift package: `IssokuCore` (library, headless — Run and the Transcript model), `Issoku` (executable — Panel, Transcript view, Theme, Memory UI).
- SwiftPM only. The app bundle is assembled by script at ho-06.
- Private prompts in `prompts/` (gitignored).

## Ho process

Canonical Ho documents for this project:

- `ho-process/kamae-1-issoku-seed.md` — Kamae 1 (parti)
- `ho-process/kamae-2-issoku-system-design.md` — Kamae 2 (architecture)
- `README.md` (repo root) — Kamae 3 (canonical public document)
- `ho-process/kamae-4-issoku-ho-overview.md` — Kamae 4 (build sequence)
- `ho-process/hos/` — per-ho documents (Kamae 5)
- `ho-process/kamae-6-issoku-state-memory.md` — Kamae 6 (State Memory, gitignored)
- `ho-process/agent-tasks/` — child agent task specs (dandori format)
- `ho-process/reviews/` — x ho review reports
- `ho-process/x-ho-template.md` — the template x ho documents are filled from

## References

- Design system: `../palana/design/palana-design-system.md`
- pālana (layout and pipeline lineage): https://github.com/sageframe-no-kaji/palana
- Ho System framework: https://github.com/sageframe-no-kaji/ho-system
