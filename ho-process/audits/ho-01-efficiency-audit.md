# ho-01 efficiency audit

The architecture is lean, but the spike's buffer handling needs changes before production reuse. The current app has 71 nonblank, noncomment Swift lines, mostly palette data, and no implemented command runner or panel. There is no application workload yet from which to establish runtime efficiency.

Date: 2026-10-25. Source baseline: `1e532c22d1a9012948670d4140a511d5dd96e382`; subsequent commits at audit time contain the review instructions and report. The practitioner selected audit and README work now, with optimization applied when production code is written.

## Scope and size

| Source | Swift files | Total lines | Nonblank, noncomment lines |
|---|---:|---:|---:|
| `Sources/` | 3 | 146 | 71 |
| `Tests/` | 2 | 65 | 54 |
| `spike/Sources/` | 6 | 573 | 432 |

Counts exclude package manifests and the Python/shell scripts. Both Swift packages declare zero third-party dependencies. This audit used source inspection and two offline evaluations of the unchanged plain model; it ran no spike invocation or host command.

## Production priorities

1. Bound parser state as well as visible text. `spike/Sources/IssokuSpike/PlainModel.swift:124` grows an incomplete control sequence, while line 129 accumulates SGR color sequences separately from the capped `lineBytes`. With `lineByteLimit: 32`, the offline evaluation fed 4,096 bytes of repeated `ESC [ 0 m` and recovered all 4,096 bytes from `finish()`; a separate unfinished CSI sequence retained 4,098 parser bytes. The existing line cap therefore leaves these buffers unbounded, which must be addressed in the production Transcript under the seed's memory constraint (`ho-process/kamae-1-issoku-seed.md:322`).

2. Choose a total retained-byte budget. `spike/Sources/IssokuSpike/main.swift:135` sets a 1 MiB line limit and line 136 allows 10,000 completed lines, so the raw ring can retain roughly 9.77 GiB of completed-line payload plus its active line and storage overhead. The recorded roughly 10 MB resident measurements exercised an unbroken local line and short wrapped remote lines; they do not establish that footprint for many long lines (`ho-process/hos/ho-01-spike-findings.md:326`). Ho-04 should set the actual byte and line limits together, rather than inheriting the spike's constants as a practical memory budget.

3. Avoid moving the retained line on each overflow. `spike/Sources/IssokuSpike/LineRing.swift:51` removes a prefix from an `Array`, shifting its retained bytes, and the plain model removes leading columns at `spike/Sources/IssokuSpike/PlainModel.swift:159`. The original recorded 50-million-byte input took 394.3 ms before the byte-cap amendment and 1,755.9 ms afterwards (`ho-process/hos/ho-01-spike-findings.md:335` and line 353); those are historical spike measurements, not a new controlled benchmark. Production buffering should discard old data without repeatedly shifting the full retained window; the storage choice belongs with ho-04's ceiling decision.

4. Avoid an extra owned output array. `spike/Sources/IssokuSpike/main.swift:43` converts the supplied collection to an `Array` before each write, and line 148 constructs another array to append LF to a rendered line. The main read loop already owns a fixed buffer at line 133, so the production write path can use that storage with an offset for partial writes. Measure this path with capture disabled, because raw capture is a spike facility and should not become production machinery.

5. Avoid a byte array per displayed character. `spike/Sources/IssokuSpike/PlainModel.swift:35` stores columns as `[[UInt8]]`, and line 97 constructs a column for each ordinary character before flattening the line at line 164. That representation adds allocation and collection overhead beyond the text's byte count. Ho-04 should keep ordinary text in contiguous storage and add only the cursor/color information its required rendering behavior needs; an emulator remains contingent on unreadable real-command output.

6. Verify the launch path in its actual process. The single-threaded CLI experiment does not establish that its `forkpty` path is appropriate inside the multithreaded app, a distinction already recorded at `ho-process/hos/ho-01-the-spike.md:49`. Environment capture is outside the recorded latency interval (`ho-process/hos/ho-01-spike-findings.md:376`), and the design calls for capturing once at app launch rather than once per command. Ho-02 needs evidence from that intended lifecycle before its launch mechanism can be treated as settled.

## Keep and omit

Keep the existing native process boundary and installed OpenSSH client; this audit found no requirement for an additional execution engine or dependency. The palette already caches dynamic colors in static values (`Sources/Issoku/Theme.swift:73`), so its current data representation is not an identified hot path. The process model and Transcript are the implementation targets for the allocation and retention changes above.

`LineRing.count` at `spike/Sources/IssokuSpike/LineRing.swift:23` and the stored `LoginEnvironment.invocation` at `spike/Sources/IssokuSpike/LoginEnvironment.swift:12` have no consumers in the spike. They should not be copied into production without a caller or an observable requirement. The spike's capture files, terminal adapter, sequence-tabulation script, and benchmark status text likewise remain experiment facilities rather than app subsystems.

## Verification of the optimization work

Compare allocations, peak resident memory, and elapsed time on the same machine and command set when the production paths exist. Include long unterminated text, many long completed lines, repeated color sequences, an unfinished control sequence, carriage-return updates, and partial output before a newline; the last case also covers the prompt defect in the [first review](ho-01x-report-1.md). Report the measured tradeoff alongside the diff, and add an abstraction or dependency only when an observed requirement needs it.
