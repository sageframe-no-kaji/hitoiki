# ho-04x report, run 3

Commit range: e08c5ea0be1ed6443a6327869dda6f39ba7cab0a..4028969c97e7d4154c590693e5d1eb3d8863d0ac

Build: pass — `swift build`, exit 0.

Tests: 107 passed, 0 failed — `swift test`, exit 0; 65 in IssokuCoreTests and 42 in IssokuTests. `swift test --enable-code-coverage` also passed all 107, exit 0.

Coverage: IssokuCore 95.75%; measured Sources/Issoku 91.88% — `scripts/coverage-floor.sh`, exit 0; both floors are 90%.

The starting tree was clean at `ce63bad`. Source, tests, package and coverage script match the range endpoint; the intervening changes advance the review brief and its status. Supplemental probes evaluated the existing model source through Swift's standard input without writing source or test files. No lint, remote command or standalone Issoku launch was run.

## Findings

### Must fix

- M1. `Sources/IssokuCore/Transcript/Transcript.swift:139` — the aggregate byte ceiling still evicts at feed-dependent moments, so overwriting a multibyte character with a shorter character can permanently delete different history for different partitions of the same bytes. `commit()` checks at line completion (`:326`), but an intermediate feed also checks before that completion; `put()` can subsequently shrink the line when it replaces a whole UTF-8 character (`:302–308`). This violates `ho-process/hos/ho-04-transcript.md:61` (the result must be the same as one feed) and `ho-process/hos/ho-04.2-fix-pass.md:24` (nothing reported may depend on where feeds end). It also contradicts the byte-stream-determined eviction promised at `ho-04.2-fix-pass.md:43`.

  Local probe, exit 0: first commit nine repeated-letter lines, A through I, of 1,048,576 ASCII bytes each, then a repeated-J line of 1,048,575 bytes; feed this prefix in chunks of at most 16,384 bytes. The model holds ten lines and 10,485,759 text bytes, one byte below the aggregate ceiling. Then feed the five UTF-8 bytes of `é\rZ\n` with these partitions:

  | Tail feeds | Final committed lines | First retained line | Retained text bytes | Sum of reported evictions |
  |---|---:|---|---:|---:|
  | `é\rZ\n` | 11 | A | 10,485,760 | 0 |
  | `é` then `\rZ\n` | 10 | B | 9,437,184 | 1 |
  | `é\r` then `Z\n` | 10 | B | 9,437,184 | 1 |
  | One byte per feed | 10 | B | 9,437,184 | 1 |

  The complete tail briefly exceeds the ceiling while it holds `é`, then shrinks to one byte at the overwrite before the commit checks it. A feed ending after `é` evicts A before that shrink. These are caller-valid partitions even under Run's 16 KiB read limit. `ho-04.2-fix-pass.md:43` explicitly prescribes the final feed check implemented here, so its timing and its stated invariant remain in conflict; this is not an implementation deviation from that recipe. The ceiling-equivalence cases at `Tests/IssokuCoreTests/TranscriptTests.swift:368–394` contain only ASCII overwrites and miss this interaction.

### Should fix

- none.

### Note

- N1. `Tests/IssokuCoreTests/TranscriptTests.swift:422–429` — the resident-size assertion measures current process memory before and after the feed, not the peak during it. In this review's ordinary run it read 208,535,552 → 197,083,136 bytes (growth −11,452,416); under coverage it read 210,583,552 → 192,987,136 (growth −17,596,416). Both satisfy the specified bound, and both demonstrate why the result must be reported as an endpoint difference rather than proof of peak allocation. This is the measurement method required by `ho-process/hos/ho-04.2-fix-pass.md:43`, not another Must-fix.

- N2. `Tests/IssokuCoreTests/TranscriptTests.swift:123–163` — explicit foreground expectations cover 31, 32 and 34, not every authorized code in 30–37. The CR table at `:107–120` does not combine overwrite with changing styles, and the copy/ceiling tests at `Tests/IssokuTests/PanelTests.swift:639–713` do not select text across an eviction. These remain coverage gaps for the style, overwrite and selectable-storage contracts at `ho-process/hos/ho-04-transcript.md:55,61,95,103`, rather than additional reproduced failures.

## Brief questions

1. none. The range adds no protocol, generic abstraction or forwarding layer with one implementation. `TranscriptView` is the `NSTextView` subclass required by `ho-process/hos/ho-04-transcript.md:103`; its framework initializer at `Sources/Issoku/TranscriptView.swift:56` serves NSTextView's construction path, explained beside it.

2. M1 is the remaining requirement violation; no additional unrequired code found. The requirement trace for the added types, helpers and branches is:

   | Code | Requirement |
   |---|---|
   | `Transcript.swift:20–58`: Style, Span, Line, Change | `ho-04-transcript.md:95–99`: styled runs, byte counts, change value and carried style |
   | `Transcript.swift:63–121`: limits, parser states, retained storage, origin, cursor and eviction accounting | `ho-04-transcript.md:61,85–99`; `ho-04.2-fix-pass.md:39–43`: bounded sequences, whole-character window and incremental eviction |
   | `Transcript.swift:129–151`: retained count, feed and clear | `ho-04-transcript.md:89,93,97`; `ho-04.2-fix-pass.md:43`: count and Change contract |
   | `Transcript.swift:155–296`: parser dispatch, escape/string/CSI handling, SGR selection and parameter decoding | `ho-04-transcript.md:52–61,99`; `ho-04.1-fix-pass.md:47`; `ho-04.2-fix-pass.md:41` |
   | `Transcript.swift:300–384`: overwrite, commit, eviction, origin movement, compaction, UTF-8 and span assembly | `ho-04-transcript.md:57–61,85–99`; `ho-04.2-fix-pass.md:39–43`, with M1 above |
   | `TranscriptView.swift:16–110`: cursor/cap state, shared metrics, construction, key forwarding, drawing and copy | `ho-04-transcript.md:103–111,117`; measured layout rulings at `:287–293` |
   | `TranscriptView.swift:114–181`: storage edits, append-only fast path, clear, leading-range calculation and attributed spans | `ho-04-transcript.md:103–109,118`; measured append cost recorded at `:287` |
   | `Theme.swift:100–109,151–170`: colour table and derived tokens | `ho-04-transcript.md:69–79` |
   | `Panel.swift:59–64,134,190,216`: byte delivery, Stop flag, reset and output-card visibility | `ho-04-transcript.md:115,129`; accepted rulings at `:289,295` |
   | `PanelWindow.swift:34–36,94–95,113–204,259–327`: input metrics, copy routing, input forwarding, fit and card/strip construction | `ho-04-transcript.md:109–111,117,125–135`; run-sheet corrections and retained input size at `:287–295` |
   | Model, Panel and Theme test additions; coverage exclusion rename | `ho-04-transcript.md:180–206`; `ho-04.1-fix-pass.md:45–49`; `ho-04.2-fix-pass.md:39–45` |

3. M1: the ceiling-equivalence tests at `Tests/IssokuCoreTests/TranscriptTests.swift:368–410` exercise CR overwrites without a change in UTF-8 byte width. The separate `é\rx\n` case at `:113` does not approach the aggregate ceiling, so all pass while the combined requirement fails. The earlier literal-limit gap is answered at `:222–240,252–300,332–350`: expectations use 256, 10,000, 1,048,576 and 10,485,760, and the oversized-line cases include the committing LF.

   The former ASCII feed-boundary probe is now pinned at `:398–410`. The removed-sequence table at `:178–190` and supplemental byte-by-byte probes cover embedded ESC and ESC-then-BEL for all five control-string introducers without payload leakage. Real Panel/Run tests cover colour, bold, progress, copy, layout and line eviction at `Tests/IssokuTests/PanelTests.swift:603–713`; scroll-follow and copy while Running are covered at `:846–892`.

   N1 limits the resident-size evidence, and N2 records the remaining isolated coverage gaps. The colours on screen, cursor drawing, wrap and jiggle are witnessed by the practitioner's run sheet at `ho-04-transcript.md:299–308`. They were not re-run here and are not counted as untested.

4. none. Runtime/test files match Decision 8's list (`ho-04-transcript.md:139–149`); process records and the two fix passes are authorized by `:169–176`, `ho-04.1-fix-pass.md:55–63` and `ho-04.2-fix-pass.md:49–55`. `Run/` and `Package.swift` are unchanged, and no dependency or setting is added. The input size of 18, Stop flag, failed-start output card and measured layout changes follow the recorded rulings (`ho-04-transcript.md:287–295`). Theme's SwiftUI accessors remain restored (`Sources/Issoku/Theme.swift:75–97`; `ho-04.1-fix-pass.md:43`), superseding the original no-SwiftUI instruction. The later Escape ladder at `ho-04-transcript.md:318` is explicitly a future ho, not a missing feature here.

5. none beyond the representations explicitly required by the spec. Model lines and AppKit text storage are the source and rendered form authorized at `ho-04-transcript.md:103`; the view holds only the trailing UTF-16 length at `TranscriptView.swift:36`, not another line copy. `Transcript.swift:100–121` separates the physical head/origin/cursor from feed eviction accounting and cached byte/style information; these serve the compaction and change contracts at `ho-04.2-fix-pass.md:39–43`. Transcript metrics have one definition at `TranscriptView.swift:25–29`, read by `PanelWindow.swift:150–155,171–204`; the input's separate font is required at `ho-04-transcript.md:109,131`. The colour map exists once at `Theme.swift:100–109`.

6. none. The model's decoding suppression has its lossy-decoding reason at `Transcript.swift:377–379`; PanelTests' file-length suppression has the one-file scope reason at `Tests/IssokuTests/PanelTests.swift:1–3`. The changed source introduces no unexplained force unwrap, `@unchecked Sendable` or `nonisolated(unsafe)`. The UI's `@MainActor` isolation follows `ho-04-transcript.md:218`; the Transcript suite's serialization at `TranscriptTests.swift:82–83` isolates the resident-size reading as required at `ho-04.2-fix-pass.md:59`. The non-contiguous layout, cursor-layout and append-only comments at `TranscriptView.swift:50–52,81–84,124–129` record measured reasons, not just the operations.

7. `TranscriptView.swift` requires `Transcript.swift` for the Change contract (`:115–143`), `Theme.swift` for colours (`:30–31,175–177`), and `Panel.swift`/`PanelWindow.swift`/`Keystrokes.swift` for keyboard routing and the cap (`:11,22,68–75`). Understanding Stop's continued drain also requires `Panel.swift:59–64,134` and Run's output-consumption contract; `ho-04-transcript.md:289` records why drawing stops while draining continues. These dependencies follow Decisions 4–7. The model itself requires none of those files.

## Ho-specific questions

- Escape sequences: `Transcript.swift:155–287` recognizes `ESC [` as CSI. A numeric/semicolon SGR ending in `m` applies only empty/0 reset, 1 bold, 22 regular, 30–37 foreground and 39 default; 38/48/58 consume their `5;n` or `2;r;g;b` arguments without applying them. Other SGR parameters, colon forms, private/intermediate CSI and other CSI finals are removed without an added effect. `ESC ]`, `ESC P`, `ESC X`, `ESC ^` and `ESC _` introduce OSC, DCS, SOS, PM and APC, removed through BEL or `ESC \`; embedded ESC stays within the string unless it starts the terminator, and BEL also terminates after ESC. Other ESC sequences consume intermediate bytes 0x20–0x2F and a final 0x30–0x7E; a repeated ESC restarts an ordinary escape. All sequence states abandon input past 256 bytes including ESC. CR, LF and TAB are the only preserved C0 controls (`:188–206`). Against the ho-01 grammar and observations (`ho-01-spike-findings.md:554,699–704`; the parameter inventory at `ho-04-transcript.md:44`), no added rendered effect is unauthorized: 22 and the full eight-colour range are explicit at `ho-04-transcript.md:54–55`, while consuming 58 is the later ruling at `ho-04.1-fix-pass.md:47`. The old 4,096-byte pending-SGR buffer is expressly absent because style is state (`ho-04-transcript.md:99`).

- Memory ceiling: measured in tests, with N1's boundary. `TranscriptTests.swift:306–329` streams 50 MB in 16 KiB feeds and reads retained counts after each feed for ordinary lines, wide lines and an unbroken line; `:252–300,332–350` pin line counts and committed/per-line byte limits independently. `:414–433` adds a 50 MB single feed, real kernel resident-size readings and the less-than-32-MiB endpoint-growth assertion; both review runs passed with the readings recorded in N1. The model releases evicted line payloads during commits at `Transcript.swift:326,331–340`, rather than retaining the entire feed until return. The real-view 50 MB reading of 87,520 → 97,728 KB at `ho-04-transcript.md:310` is the builder's recorded measurement, not a new live-app measurement by this review. The counters and measurements do not establish chunk independence; M1 is a separate failure of what history is retained.

- Transcript's knowledge of Run: none. `Sources/IssokuCore/Transcript/Transcript.swift:1` imports Foundation only; its values and `feed(_:)` at `:18–58,132` reference no other package type. The comment beside the 16 KiB slack at `:75–77` cites Run's read size as a sizing reason without introducing a runtime dependency. Panel supplies the bytes at `Sources/Issoku/Panel.swift:59–64`.

The third Return invokes the standing checkpoint in `ho-process/hos/ho-04x-review-of-transcript.md:30` and `ho-process/hos/ho-04.2-fix-pass.md:24`; this report does not open another fix pass or alter build status.

## Verdict

Return
