# ho-04x report, run 4

Commit range: e08c5ea0be1ed6443a6327869dda6f39ba7cab0a..dd110402e715317a085485b362606d2b0f7108fa

Build: pass — `swift build`, exit 0, `Build complete! (3.22 sec)`.

Tests: 113 passed, 0 failed — `swift test`, exit 0; 70 IssokuCoreTests and 43 IssokuTests. `swift test --enable-code-coverage` also passed all 113, exit 0. The Transcript suite took 91.334 s normally and 89.568 s under coverage, both below ho-04.3's 120 s limit.

Coverage: IssokuCore 95.75% over 5 files; measured Sources/Issoku 91.88% over 4 files — `scripts/coverage-floor.sh`, exit 0; both floors are 90%.

The starting tree was clean at `56e9d84`. Source, tests, Package.swift and the coverage script match the range endpoint; the intervening commit advances the review brief and roster. Supplemental probes evaluated existing source through `swift -O -` using standard input, without adding or changing source, tests or fixtures. No lint, remote command or standalone Issoku launch was run.

## Findings

### Must fix

- none.

### Should fix

- none.

### Note

- N1. `Tests/IssokuCoreTests/TranscriptTests.swift:97–114` — the replacement memory measurement is a sampled allocator peak, not process resident size or a continuous maximum. It samples `mstats().bytes_used` on another thread at requested 1 ms intervals, so a shorter allocation spike is outside its guarantee. The endpoint-reading finding from run 3 is answered; the remaining boundary follows the method recorded at `ho-process/hos/ho-04.3-fix-pass.md:85`, with this review's calibration recorded below.

- N2. `Tests/IssokuTests/PanelTests.swift:400` — the cursor test asserts state and stored text; the wrap test at `:789` checks harness geometry. Colours on screen, cursor drawing, live wrap and jiggle remain witnessed by the practitioner's run sheet at `ho-process/hos/ho-04-transcript.md:299–308`, as the review brief permits. Those observations were not re-run here and are not counted as untested.

## Brief questions

1. none. No added protocol with one conformer, generic with one instantiation or forwarding layer appears in the range. The value types at `Sources/IssokuCore/Transcript/Transcript.swift:20–58` implement Decision 4's representation, and the NSTextView subclass at `Sources/Issoku/TranscriptView.swift:10` is expressly required at `ho-process/hos/ho-04-transcript.md:103`. The private framework initializer at view line 56 has its construction-path reason beside it.

2. none. The requirement trace for the complete changed unit is:

   | Code | Requirement |
   |---|---|
   | `Transcript.swift:20–58`: Style, Span, Line, Change | `ho-04-transcript.md:93–99`: styled runs, byte counts and the reported change |
   | `Transcript.swift:63–129`: limits, parser state, retained storage, head/origin/cursor, counters and construction | `ho-04-transcript.md:61,85–99`; `ho-04.2-fix-pass.md:39–43`; `ho-04.3-fix-pass.md:37–47` |
   | `Transcript.swift:132–151`: feed, reporting, compaction and clear | `ho-04-transcript.md:93,97`; `ho-04.3-fix-pass.md:43,47`: no feed-end check |
   | `Transcript.swift:154–296`: parser dispatch, C0, ESC, intermediate/CSI/string states, SGR and numeric parameters | `ho-04-transcript.md:52–61,99`; `ho-04.1-fix-pass.md:47` adds consumed SGR 58; `ho-04.2-fix-pass.md:41` specifies BEL after ESC |
   | `Transcript.swift:300–387`: overwrite, commit, eviction, origin movement, physical compaction, UTF-8 and span assembly | `ho-04-transcript.md:57–61,85–99`; `ho-04.2-fix-pass.md:39`; `ho-04.3-fix-pass.md:37–47` |
   | `TranscriptView.swift:16–110`: cursor/cap state, font metrics, initialization, keyboard, drawing, paste and copy | `ho-04-transcript.md:103–111,117`; measured layout rulings and Done-key handoff at `:287–308` |
   | `TranscriptView.swift:114–181`: ranged storage edits, growing-line append, clear, leading-range calculation and attributed spans | `ho-04-transcript.md:103–119`; measured append cost at `:287` |
   | `Theme.swift:100–109,151–170`: eight-colour table and derived tokens | `ho-04-transcript.md:69–79` |
   | `Panel.swift:24,59–64,96,134,190,216`: Stop flag, byte handoff, clear and output-card visibility | `ho-04-transcript.md:105–129`; accepted rulings at `:289,295` |
   | `PanelWindow.swift:34–36,94–95,113–204,259–327`: input metrics, copy/key routing, terminal size, fit, cards and strip | `ho-04-transcript.md:109–135`; input 18, width/rounding and gear rulings at `:286–295` |
   | `TranscriptTests.swift:14–145`: rendering/feeding helpers, Partition, equivalence, allocation sampler and periodic stream | `ho-04-transcript.md:182–192`; `ho-04.3-fix-pass.md:49–54,71,83,85`: named partitions, runtime limit, tiled input and sampled peak |
   | Model, Panel and Theme test additions, including `PanelTests.swift:75–119,894–917` | `ho-04-transcript.md:180–206`; `ho-04.1-fix-pass.md:45–49`; `ho-04.2-fix-pass.md:39–45`; `ho-04.3-fix-pass.md:49–56` |
   | `scripts/coverage-floor.sh:64–68`: renamed view exclusion | `ho-04-transcript.md:146,206` |

   The five mutation/reporting paths were checked against the current invariant. `feed` at `Transcript.swift:132–146` only reads, removes empty eviction placeholders, compacts and reports. `put` at `:300–315` advances the origin and evicts after writing a byte, and the continuation join at `:196–201` does the same after inserting one. `commit` at `:319–327` checks the line count at LF; `evict` at `:335–345` reads the retained byte count and the logical line count excluding `head`. Compaction at `:362–366` subtracts the same origin from storage and cursor, so it changes no reported text or count.

3. none of the earlier reproduced failures remains unanswered. The run-3 probe is pinned at `Tests/IssokuCoreTests/TranscriptTests.swift:498–508` with the invariant's explicit result: ten lines, B first, Z last and 9,437,184 bytes. The helper at `:57–87` checks the specified 16 KiB/1 KiB whole-input partitions, each tail split point and bytewise tails; the line-window and line-count cases at `:512–525` and the multibyte ceiling-crossing case at `:436–462` cover the other ceilings. A separate inline probe checked all 16 nonempty-chunk partitions of the five-byte tail `é\rZ\n`, plus the prefix and tail in one feed; every result agreed. It also applied every Change's evictions and committed lines to a separate list and checked that it reconstructed the model's retained lines after every feed, with exactly one pre-existing line evicted across the tail.

   Earlier cap/terminator regressions remain explicit rather than importing expected limits from model constants: `TranscriptTests.swift:290–307,319–367,399–415` assert literal limits and committing LFs. The removed-sequence cases at `:246–258` cover the prior embedded-ESC and ESC-then-BEL defects; supplemental whole/bytewise probes of all five string introducers with three embedded-ESC/terminator patterns each also yielded only `ab`. Run-3 N2 is answered by all eight foreground indices at `:528–530`, styled overwrite at `:533–539` and selection across eviction at `PanelTests.swift:894–917`.

   Panel's real Run/window tests still cover output-before-Done (`PanelTests.swift:516`), colours, bold, progress, copy, layout and the line ceiling (`:603–713`), Stop and subsequent output (`:816`), scroll-follow (`:842`) and Command-C while Running (`:871`). The negative memory calibration below distinguishes the current implementation from the earlier unbounded one. N1 and N2 state the remaining measurement and visual-evidence limits; no other specified test case is missing.

4. none. The runtime/test/script paths are those authorized by `ho-04-transcript.md:139–149` and the three fix-pass tables (`ho-04.1-fix-pass.md:55–63`, `ho-04.2-fix-pass.md:49–55`, `ho-04.3-fix-pass.md:60–67`). The specs, prior reports, overview and roster are closing records authorized at `ho-04-transcript.md:169–176,328` and the fix-pass closing instructions. Run, Package.swift, App, Hotkey, Keystrokes, SettingsWindow and RunTests are unchanged; the dependency list remains empty at `Package.swift:20`.

   Input 18, suppression of drawing after Stop, the failed-start output card and measured layout adjustments follow the rulings at `ho-04-transcript.md:287–295`. Theme's SwiftUI accessors are restored at `Theme.swift:75–97` as required by `ho-04.1-fix-pass.md:43`; the later Escape ladder at `ho-04-transcript.md:318` remains outside this ho. The allocator sampler's Foundation/os imports and thread are test-only and recorded at `ho-04.3-fix-pass.md:85`.

5. none beyond the specified representations and caches. Model lines and AppKit storage are the required source/rendered pair (`ho-04-transcript.md:103`); `TranscriptView.swift:36` holds a trailing UTF-16 length, not another line. `Transcript.swift:100–121` separates physical storage positions from eviction accounting, retained-byte totals and the uniform-style cache; the head/origin distinctions are required by `ho-04.2-fix-pass.md:39–43`. The two byte-writing paths both call origin advancement and eviction (`Transcript.swift:200–201,314–315`) because both change retained bytes under `ho-04.3-fix-pass.md:47`; feed-end compaction does not repeat a ceiling rule. Transcript metrics have one definition at `TranscriptView.swift:25–29`, used by `PanelWindow.swift:150–155,171–204`, and the separate input font is required at `ho-04-transcript.md:109,131`. The colour map exists once at `Theme.swift:100–109`.

6. none. The decoding suppression has its replacement-character reason at `Transcript.swift:381–383`, and PanelTests' length suppression has the one-file scope reason at `PanelTests.swift:1–3`. Changed code introduces no unexplained force unwrap, `@unchecked Sendable` or `nonisolated(unsafe)`; UI isolation follows `ho-04-transcript.md:218`. The sampler's locks protect state shared with its thread (`TranscriptTests.swift:98–114`), and the suite remains serialized at `:149–150` as required. Public documentation states contracts; the private layout/append comments at `TranscriptView.swift:50–52,81–84,124–129` and `PanelWindow.swift:45–47,201–203` give measured causes. The old reversed test counts remain corrected and marked at `ho-04-transcript.md:310` and `ho-process/kamae-4-issoku-ho-overview.md:605`.

7. `TranscriptView.swift` requires the Change contract in `Transcript.swift` (`view:115–143`), Theme's mapping (`view:30–31,175–177`) and PanelWindow's cap/keyboard behavior (`view:11,22,68–75`). The keyboard path also crosses Panel and Keystrokes; understanding Stop's continued drain requires `Panel.swift:59–64,134` and Run's unchanged output-consumption contract (`Sources/IssokuCore/Run/Run.swift:279–301`). These are the seams specified by Decisions 4–7, with the Stop rationale at `ho-04-transcript.md:289`. The model itself requires no other package file.

## Ho-specific questions

- Escape sequences: `Transcript.swift:154–287` recognizes `ESC [` as CSI; numeric/semicolon/colon parameters with final `m` enter SGR selection. Honoured effects are empty/0 reset, 1 bold, 22 regular, 30–37 foreground indices 0–7 and 39 default. Extended 38/48/58 consume `5;n` or `2;r;g;b` without applying them; other parameters and colon-containing parameters are ignored. Private/intermediate CSI and other finals 0x40–0x7E are removed.

  `ESC ]`, `ESC P`, `ESC X`, `ESC ^` and `ESC _` introduce OSC, DCS, SOS, PM and APC, removed through BEL or `ESC \`; embedded ESC stays in the string unless it starts the terminator, and BEL terminates after ESC too. Other ESC forms consume zero or more intermediates 0x20–0x2F and a final 0x30–0x7E; repeated ESC restarts ordinary escape parsing. Sequences past 256 bytes including ESC are abandoned, and ground handling preserves only CR, LF and TAB among C0 controls (`:187–206`). Against the ho-01 grammar and observations at `ho-01-spike-findings.md:554,699–704` and the observed parameter inventory at `ho-04-transcript.md:44`, extra honoured effects: none. SGR 22 and all eight foreground indices are authorized at `ho-04-transcript.md:54–55`, consumed SGR 58 at `ho-04.1-fix-pass.md:47`; the old pending-SGR buffer is intentionally absent under `ho-04-transcript.md:99`.

- Memory ceiling: measured in tests, with N1's sampling boundary. `TranscriptTests.swift:342–395` reads retained counts after every 16 KiB feed: maxima were 1,048,576 for the 2 MiB and 50 MB single lines, 760,076 for 76-column lines and 10,483,200 for 4,095-column lines. Final counts were respectively 1,048,576, 1,048,576, 760,000 and 10,483,200; LF assertions also check committed line sizes.

  The single-feed test at `:482–494` measured sampled allocator growth of 2,771,168 bytes normally and 2,767,504 under coverage, both below 33,554,432. In a separate stdin calibration using that same sampling function and 50 MB input allocated before the baseline, the current model grew by 2,673,072 bytes; the unchanged ho-04.1 model read from commit `1b42564` grew by 124,512,176, exceeding the same bound. Both calibration processes exited 0; the old model was never restored into the working tree. The real-view reading of 87,520 → 97,728 KB at `ho-04-transcript.md:310` remains the builder's recorded evidence, not a new app measurement by this review.

- Transcript's knowledge of Run: none. `Sources/IssokuCore/Transcript/Transcript.swift:1` imports Foundation alone; the values and byte-taking entry point at `:18–58,132` reference no other package type. The slack comment at `:75–77` cites Run's read size as a sizing reason without depending on Run. Panel supplies bytes at `Sources/Issoku/Panel.swift:59–64`.

## Verdict

Pass
