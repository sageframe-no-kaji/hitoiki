---
created: 2026-11-03
status: complete
type: ho-document
project: issoku
ho: "04"
kamae: 5
shape: ha
phase: 2 — The Surface
title: Transcript — the one monospace zone
description: The Transcript model in IssokuCore (lines, bold and the eight colours, carriage-return overwrite, every other sequence removed, a fixed ceiling) and the view in the app that draws it beneath a collapsed input bar, with selection, Command-C and a Copy control.
builds-on:
  - kamae-1-issoku-seed
  - kamae-2-issoku-system-design
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-01-spike-findings.md
  - ho-process/hos/ho-03-panel.md
  - ho-process/hos/ho-03.1-fix-pass.md
  - ho-process/hos/ho-03.2-fix-pass.md
  - ho-process/reviews/ho-03x-report-3.md
model: claude-opus-5-5
opening-hash: e08c5ea0be1ed6443a6327869dda6f39ba7cab0a
---

# ho-04 — Transcript

This session builds Transcript, the one monospace zone: output rendered as it arrives, bold and the eight basic colours honoured, carriage-return overwrite so a progress line rewrites itself in place, every other control sequence removed, a fixed ceiling with the oldest lines dropped, selection, `Command-C` for the selection or the whole transcript, a Copy control, and the exit status where ho-03 left it. The model lives in `IssokuCore` beside Run and takes bytes and nothing else; the view in the app draws it. The panel's layout changes with it, per the practitioner's ruling at the ho-03 run sheet: Composing is the input bar alone, and the transcript appears beneath it as its own card once a command starts. `TranscriptPlaceholder.swift` is deleted whole.

**Out of scope:** any emulator, cursor movement, scrollback search, saved transcripts (overview, "ho-04 — Transcript"); any SGR parameter beyond the ho-01 list (Decision 1); settings, history, up-arrow recall, macros, the working-directory setting (ho-05); the app bundle, icon, signing (ho-06); any change to `Sources/IssokuCore/Run/`; any dependency.

**Resolves deferred decisions** (from the System Design and the overview's ho-04 entry):
- The line ceiling for the buffer (Decision 3).
- Which control sequences are stripped versus honoured, from the ho-01 list (Decision 1).
- From ho-03's Reflect: the placeholder's replacement, the collapsed Composing layout, the cursor's carry-over, the bytes task, the terminal size, the measurement in `fit()`, and the per-chunk whole-document layout (Decisions 4–8).

**Every command this ho runs against a host reads. None writes.** Automated tests never touch a live host. The practitioner's run sheet in Execute, part H, runs against one real host; every command on it is read-only and the sudo password is typed by the practitioner and by no one else.

**Tight.** The seed's constraint applies in full and the subagent's brief carries it: the parser recognises the ho-01 list and nothing more; no protocol with one conformer; no renderer abstraction; no second copy of a line held by the view; no configuration surface. ho-04x counts the sequences (overview, "ho-04x — Review of Transcript").

---

## Phase 1 — Think

Eight decisions, settled 2026-11-02 and 2026-11-03 between the practitioner and the orchestrator. Decisions 1 to 3 are the practitioner's rulings; 4 to 8 fix the shape of the work so the subagent has nothing architectural left to decide. The ho-01 evidence this rests on: across 25 captures of the practitioner's command set, the only escape sequences were SGR, the only C0 controls were CR, LF and TAB, no CR overwrote a line, and every capture was judged readable (`ho-01-spike-findings.md` §6 and "For ho-04"). The SGR parameters seen were `0`, empty, `1`, `31`, `34`, `35` and `39;49`. The spike's plain model (`spike/Sources/IssokuSpike/PlainModel.swift` at `8e0b8d1`, deleted at ho-02, readable with `git show 8e0b8d1:spike/Sources/IssokuSpike/PlainModel.swift`) is the grammar's reference, not its code: it worked over bytes with SGR carried as pending bytes, and this model carries style as state instead.

### Decision 1 — The honoured set is the ho-01 list; everything else is removed

Practitioner's ruling 2026-11-02: show colours. The model honours exactly:

| Input | Effect |
|---|---|
| SGR `0`, SGR with no parameter | reset: regular weight, default colour |
| SGR `1` | bold |
| SGR `22` | regular weight (the pair of `1`; not seen, included so bold can end without a reset) |
| SGR `30`–`37` | foreground colour 0–7 |
| SGR `39` | default foreground |
| CR | the column returns to zero; following characters overwrite the line from there |
| LF | the line in progress is committed |
| TAB | kept as a character; the text view renders it |

Every other SGR parameter is consumed and ignored: `2`–`9`, `23`–`29`, `40`–`49`, `90`–`107`, and the extended forms `38;5;n`, `48;5;n`, `38;2;r;g;b`, `48;2;r;g;b`, whose following parameters are consumed with them so that `38;5;31` does not read as red. Parameters are split on `;` and applied in order, so `1;34` is bold blue. The parser recognises every other escape sequence only far enough to remove it, as the spike's grammar did: CSI sequences with any final other than `m` (cursor movement, erase, mode), OSC and the DCS, SOS, PM and APC strings up to BEL or `ESC \`, and single-character ESC sequences with their intermediate bytes. A sequence longer than 256 bytes, ESC included, is abandoned and the parser returns to ground, so an unterminated string reads as text again. C0 controls other than CR, LF and TAB (BEL, BS, FF, VT, and the rest) are dropped. UTF-8 continuation bytes join the character before them, so a multi-byte character is one column and overwrite by CR is by character, not by byte. A chunk may end inside a sequence or inside a UTF-8 character; the parser's state carries across `feed` calls and the result is the same as for one feed.

Nothing is rendered that is not on this list. ho-04x's first question is answered by this table.

### Decision 2 — The eight colours are pālana's, with three derived

Practitioner's ruling 2026-11-02: a set designed in pālana's register, from the pālana palette, with no further design round. Five of the eight are the tokens Issoku already has:

| SGR colour | Token |
|---|---|
| 0 black | `ink` |
| 1 red | `alarm` (rust) |
| 2 green | `accent` (moss) |
| 3 yellow | `plugin` (umber) |
| 7 white | `inkFaint` |

pālana has no blue, magenta or cyan, and `ls -G` and `git` use the first two. The subagent derives the three in the same register: muted, warm-shifted, in the lightness band of moss, rust and umber on the light ground, with dark siblings by the same lift toward warm and bright that `Theme.swift`'s comment describes for `plugin`. They are three new `Palette` values in `Theme.Token`, named `transcriptBlue`, `transcriptMagenta`, `transcriptCyan`, each with a comment giving the derivation. The mapping from colour index to token is one eight-element table in `Theme`, read by the view. `ThemeTests` covers the three new tokens as it covers the eight. The practitioner sees them at the run sheet and may retune them at the replan week; a retune is a value change, not a ho.

Bold is the monospace font at `.bold` weight, same size. Default colour is `ink`.

### Decision 3 — The ceiling: 10,000 lines, 1 MiB per line in progress, 10 MiB in all

Practitioner's ruling 2026-11-03, from ho-01's measurement (`ho-01-spike-findings.md` §4: 10,000 lines with the line in progress capped at 1 MiB held 50 MB at 9.7 MB peak resident; a line count alone held a 66 MB single line whole at 174.5 MB). The model keeps:

- at most 10,000 committed lines, oldest dropped first;
- at most 1 MiB of the line in progress, oldest columns dropped first, whole characters at a time;
- at most 10 MiB of text across every retained line, oldest whole lines dropped first.

The three constants are `static let` on the model with the measurement cited beside them. The model exposes its retained byte count so a test can measure it. Eviction is reported to the view (Decision 5) so the view deletes exactly the lines the model dropped; the view never holds a line the model has released. ho-04x's second question: the ceiling is enforced by a test that streams 50 MB and reads the count after every feed, and by the run sheet's reading of the process's resident size.

### Decision 4 — The model: `Transcript` in IssokuCore, bytes in, a change out

`Sources/IssokuCore/Transcript/Transcript.swift` holds a `public struct Transcript` with one entry point, `public mutating func feed(_ bytes: [UInt8]) -> Change`, and one `public mutating func clear()`. It takes bytes from `Run.Output` and knows nothing of Run, the window, or AppKit: `Foundation` is its only import, and it has no reference to any other type in the package. ho-04x's third question is answered by that import list.

A line is a sequence of runs; a run is text with a style; a style is a weight (regular or bold) and a colour (default or an index 0–7). Adjacent characters of one style form one run. The representation inside the model is the subagent's (the spike kept columns as byte arrays; this model needs a style per column for overwrite), under two constraints: overwrite by CR replaces by character, and a line's bytes are counted toward the ceiling.

`Change` is a value with three fields: the number of lines evicted from the top since the last feed, the lines committed since the last feed, and the line in progress as it now stands. The line in progress is reported on every feed, so a prompt that ends without LF (`[sudo] password for <user>: `) is on screen before anything is typed, as ho-01.1 required. The parser's grammar is Decision 1; its state (ground, escape, intermediate, control sequence, control string, the current style, the current column) is private.

Style is carried as state, not as pending bytes: an SGR changes the current style, and the next character takes it. The spike's 4,096-byte pending-SGR bound has nothing to bound and does not exist here.

### Decision 5 — The view: an `NSTextView` that edits by the change, selectable, with the cursor

`Sources/Issoku/TranscriptView.swift` replaces `TranscriptPlaceholder.swift`, which is deleted. `TranscriptView` is an `NSTextView` subclass, non-editable and selectable, in the scroll view as before. It owns one `Transcript` model. `append(_ chunk: [UInt8])` feeds the model and applies the change to its text storage in three edits: delete the leading range covering the evicted lines, append the committed lines as attributed strings, and replace the trailing range that held the previous line in progress with the new one. Each run becomes one attributed range: the monospace font at the run's weight, the foreground colour from Decision 2's table. The text storage is the rendered form of the model's lines and holds nothing else; the model is the source, and the view keeps no second copy of a line beyond the storage AppKit needs to draw. `clear()` resets the model and empties the storage. `string` therefore still reads as the plain rendered text, which the Panel tests use.

The decoding suppression in `Panel.swift` goes: Panel hands the chunk's bytes to the view and decoding is the model's. `keyDown`, `paste(_:)` and `acceptsFirstResponder` carry over unchanged from the placeholder, as does the block cursor: `showsCursor`, drawn after the last glyph of the line in progress or at the extra line fragment, in ink. The cursor is drawn, never stored.

**Scrolling.** After each change the view scrolls to the end if the end was in view before the change; if the user has scrolled up to read, the view leaves them there. One comparison of the visible rect against the document's end before the edit.

**Measurement.** `TranscriptView.font` and `.lineHeight` are the one definition of the transcript's font, read by `PanelWindow.terminalSize` and the height cap as they are now. The input's font is its own constant in `PanelWindow` (Decision 7), no longer shared with the transcript.

**Copy.** `copy(_:)` is overridden: with a selection, the selected plain text; with none, the whole of `string`. The pasteboard receives `.string` only, no attributes, so what is pasted into a terminal or an editor is the text as the command printed it, colour sequences already removed. The Copy button in the strip and `Command-C` through `PanelWindow.performKeyEquivalent` both reach this override, so the button needs no Panel method. `Command-C` while Running already reaches the transcript (Keystrokes maps it to `.ignore` and the window routes it to the first responder's `copy:`), so copying works in all three states.

### Decision 6 — The bytes task and the layout cost

Panel's bytes task stays as ho-03.1 left it: one task for the app's life, each chunk appended on the main actor before the next is pulled, so Done follows the last draw. What changes is the cost per chunk. The placeholder called `fit()` after every chunk and `fit()` laid out the whole document to measure it. Now:

- `fit()` measures the transcript's used height only while the transcript card is below its cap. Once the card has reached the cap, its height is fixed until a clear, and `fit()` does not ask the layout manager for the document's height. The view tells the window whether it is at the cap with one `Bool`.
- The view's edits are ranged (Decision 5), so the layout manager invalidates the edited ranges, not the document.
- The scroll to the end (Decision 5) lays out to the end, which is the newest lines; that is the cost of showing them.

The run sheet's 50 MB item (part H, item 8) is where this is seen: the panel must stay responsive and Stop must act while the output streams. No coalescing timer, no off-main parsing, no second queue: the model is fed on the main actor, chunk by chunk, as before.

### Decision 7 — The layout: the bar, and the output card beneath it

Practitioner's ruling 2026-10-31 (the collapse) and 2026-11-03 (the strip at the foot; the input at 12 with the size one constant). `PanelWindow` keeps one window, 640 wide, placed as before, and lays out two cards in its clear content view, with an 8-point gap:

**The bar.** Always shown while the panel is visible. One `NSBox` card, corner radius 10, ground, hairline border, holding the input and the gear at its right end on one row. The notice line (hotkey failure, environment failure) sits beneath the input inside the bar, hidden when empty. Nothing else. In Composing the panel is this bar.

**The output card.** A second `NSBox` card, same style, beneath the bar. Hidden in Composing; shown from `.running` until the dismissal clears it (Decision 17 of ho-03 stands: every summons starts with the bar alone). It holds the scroll view with `TranscriptView`, and beneath it, separated by a hairline, the strip: the status label, then Retry, Stop, Open in Terminal, Copy, right-aligned. Visibility of each control is derived from `state` in Panel's `apply` as now, with Copy visible whenever the card is. The transcript area shows while the cursor shows or the transcript has text, as now, so a running command that has printed nothing shows the empty area with the cursor and the strip reading `running`.

**The input's size.** `PanelWindow.inputFont` is `NSFont.monospacedSystemFont(ofSize: inputSize, weight: .regular)` with `private static let inputSize: CGFloat = 12`, and the input's line height comes from that font. The practitioner looks at 12 at the run sheet and may change the constant to 14 and rebuild to compare; whichever is kept is recorded in Reflect. Not a setting.

**Height.** The window's height is the bar, the gap, and the output card (transcript area up to the cap, the hairline, the strip). The cap stays half the screen's visible height less the rest. The window keeps its top edge as it grows.

The status text is unchanged from ho-03 (`running`, `exit N`, `signal N`, the offer appended), in `inkFaint` or `alarm` as now. The System Design places status with Transcript; it is on the output card, which is where Transcript is.

### Decision 8 — Files, tests, coverage, one subagent, no split

```text
Sources/IssokuCore/Transcript/Transcript.swift   the model: grammar, style, lines, the ceiling, Change     (create)
Sources/Issoku/TranscriptView.swift              the view: storage edits, cursor, keys, copy, scrolling     (create)
Sources/Issoku/TranscriptPlaceholder.swift       deleted
Sources/Issoku/Theme.swift                       three transcript tokens and the eight-colour table          (modify)
Sources/Issoku/Panel.swift                       bytes to the view; clear; Copy needs nothing here           (modify)
Sources/Issoku/PanelWindow.swift                 two cards, the strip at the foot, Copy, inputFont, fit()    (modify)
scripts/coverage-floor.sh                        TranscriptPlaceholder → TranscriptView in the exclusion     (modify)
Tests/IssokuCoreTests/TranscriptTests.swift      the model                                                   (create)
Tests/IssokuTests/PanelTests.swift               bytes-in, colours through the storage, copy, the layout     (modify)
Tests/IssokuTests/ThemeTests.swift               the three tokens                                            (modify)
```

The subagent may split `Transcript.swift` into `Transcript.swift` and `Sequences.swift` (the escape grammar) if the first passes 300 nonblank lines; both under `Sources/IssokuCore/Transcript/`. `Package.swift`, `Run/`, `App.swift`, `Hotkey.swift`, `Keystrokes.swift`, `SettingsWindow.swift` and `Tests/IssokuCoreTests/RunTests.swift` do not change. The core floor measures `Transcript.swift` with Run; the app floor excludes `TranscriptView.swift` by name as it excluded the placeholder, with the comment updated. The width is fixed at 640, so `Run.resize` is not called; the terminal size is computed at submit as now, from `TranscriptView.font`.

One Opus subagent builds it in this order, test first for the model: the model and its tests; the theme tokens and their tests; the view; the window and Panel; the Panel tests. The seams are real but share one window and one test suite, and the model is the only piece that stands alone; one conversation, no agent-task files. If the subagent halts on a question this document does not answer, the orchestrator stops and the practitioner rules.

### Discovery (deferred to execution) — two things only the build can show

- **The three derived colours.** The subagent records the values and the derivation; the practitioner judges them on screen at the run sheet, light and dark.
- **The input at 12 against 14.** Run-sheet item 1; the constant is changed by hand and the binary rebuilt for the comparison.

---

## Phase 2 — Execute

One subagent, in the order of Decision 8, test first for `Transcript.swift`.

### Files

The subagent creates, modifies or deletes only the files in Decision 8's table. The orchestrator, not the subagent, does:

| Path | Change |
|---|---|
| `ho-process/hos/ho-04-transcript.md` | this document in the opening commit; Reflect, status, frontmatter at close |
| `ho-process/kamae-4-issoku-ho-overview.md` | build-record entry |
| `ho-process/kamae-6-issoku-state-memory.md` | state-summary block |
| `metadata/ho-status.md`, `metadata/ho-status.json` | roster |

### Tests

Every test runs local processes only. The Panel suite stays `@MainActor` and `.serialized`.

**Transcript** (the model, no window, no process; every case feeds bytes and reads the `Change` and the lines):

- *Lines.* `a\nb\n` commits two lines; `a\nb` commits one and reports `b` in progress; a second feed of `\n` commits it. `[sudo] password for user: ` with no LF is reported in progress after the feed.
- *Carriage return.* `abc\rXY\n` commits `XYc`; `1%\r2%\r100%\n` commits `100%`; `CR CR LF` after text commits the text and no blank line (ssh's line ending, ho-01 "For ho-04"); `é\rx\n` commits `x` (overwrite by character).
- *Style.* `ESC[31m` + `red` + `ESC[0m` + ` plain` gives two runs, red bold-off then default; `ESC[1;34m` gives one bold blue run; `ESC[22m` ends bold with colour kept; `ESC[39m` returns to default with weight kept; `ESC[m` resets; the style persists across LF into the next line until changed.
- *Ignored SGR.* `ESC[38;5;31m`, `ESC[38;2;255;0;0m`, `ESC[48;5;196m`, `ESC[4m`, `ESC[2m`, `ESC[91m`, `ESC[44m` each leave the style unchanged and the text in default style.
- *Removed sequences.* `ESC[2J`, `ESC[3A`, `ESC[K`, `ESC]0;title BEL`, `ESC]0;title ESC \`, `ESC P … ESC \`, `ESC(B`, `ESC 7` each vanish and the surrounding text joins; BEL, BS and FF alone vanish; TAB is kept.
- *Split chunks.* For `ESC[1;34mblue ESC[0m\n` and for `●\n`, feeding one byte at a time, and feeding split at every boundary, each produce the same lines as one feed. A 300-byte CSI with no final is abandoned and the following text reads as text; the bound is exactly 256 bytes, ESC included.
- *UTF-8.* `├─ ●\n` commits intact; a chunk ending inside the three-byte `●` followed by its remainder commits intact.
- *The ceiling, measured.* 10,001 one-character lines leave 10,000 and the change after the last reports one evicted. A 2 MiB line with no LF keeps the newest 1 MiB and the retained count never exceeds the per-line bound. 50 MB of 76-column lines fed in 16 KiB chunks: after every feed the retained byte count is at or under 10 MiB, and the sum of evictions plus retained lines equals the lines fed. A 50 MB single line fed the same way: retained at or under the per-line bound after every feed.
- *Clear.* After `clear()` the lines are empty, the style is default and the next feed starts a fresh line.

**Theme:** `resolved(dark:)` for the three transcript tokens, light and dark, as the eight are tested; the colour table has eight entries and index 1 is `alarm`, index 2 is `accent`.

**Panel**, against a real `Run` and a real `PanelWindow` as before; existing tests adapt to the view taking bytes and the placeholder's name changing, with no assertion weakened:

- *Colours through the storage.* `printf '\033[31mred\033[0m plain\n'` reaches Done; the text storage has `red` in `transcriptColor(1)`'s resolved colour and `plain` in `ink`; `string` is `red plain` with no escape bytes.
- *Bold.* `printf '\033[1mbold\033[22m\n'`: `bold` carries the bold monospace font, the rest the regular.
- *Progress line.* `printf '1%%\r2%%\r3%%\n'`: `string` ends `3%`.
- *Copy.* After a command prints two lines, `transcript.copy(nil)` with no selection puts the whole string on the general pasteboard as `.string`; with the first word selected, only that word. The pasteboard is restored afterwards, as the paste test does.
- *Layout.* In Composing the output card is hidden and the window's height is the bar's; at `.running` the card is visible with the Copy button; after dismissal the card is hidden again and the transcript empty.
- *Output before Done* (ho-03.1's test) and *dismissal clears* hold unchanged against the new view.
- *Ceiling through the panel.* `yes | head -n 12000` reaches Done; `string` has 10,000 lines.

**Coverage.** `IssokuCore` at or above 90% with `Transcript.swift` measured beside Run; `Sources/Issoku` at or above 90% with `TranscriptView.swift` excluded by name. If the floor cannot be reached without a test that exists only to execute lines, the subagent halts and reports which lines.

### Rules for the subagent

- No commits. The orchestrator commits.
- No files outside Decision 8's table. Nothing under `Sources/IssokuCore/Run/`, nothing in `Package.swift`.
- No dependencies. `AppKit` and `Foundation` are the only imports beyond IssokuCore; `Transcript.swift` imports `Foundation` only.
- No SwiftUI in any file this ho touches.
- No architectural decisions. If this document and the System Design do not answer a question, halt and report the question. Do not pick.
- The parser recognises the sequences in Decision 1 and no others. No table of CSI finals beyond what removal needs, no cursor state, no screen model.
- No test touches a live host or the network. No test changes system settings. No test or source logs, stores, or echoes anything written through `Run.write`.
- Never `pkill` or `killall` by pattern. Tests kill by pid or pgid they own.
- Strict concurrency, language mode 6. `Transcript` is a `Sendable` value type. The view, the window and Panel are `@MainActor`. No `@unchecked Sendable`, no `nonisolated(unsafe)`, no force unwrap without a `// FORCE:` comment, no lint suppression without a comment naming why.
- Tight: one model, one view, one change value; no protocol; no generic over one type; no configuration struct; no helper that wraps one call; no comment that says what the next line does; no second copy of a line outside the text storage.
- Report back with: every file written, every command in Verification with its full output, both coverage numbers, the three derived colour values with their derivation, and the retained byte counts the ceiling tests observed.

### Verification

Run from the repository root, in this order, all green before reporting:

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
swift test --enable-code-coverage && scripts/coverage-floor.sh
swift build -c release
```

The orchestrator then reads the whole diff, runs the stack again, runs `pre-commit run` with the ho-04 paths staged, sweeps for secrets and real names, and commits.

### H. The practitioner's run sheet (after the orchestrator's verification, before close)

From the repository root with `swift build` done, launch `.build/debug/Issoku`. Every command reads. Record what the panel shows and the status of each.

1. Press the hotkey: the bar alone, input and gear, nothing beneath. Judge the input at 12. Then, in a terminal, change `inputSize` to 14 in `PanelWindow.swift`, `swift build`, relaunch, and look again. Say which stays.
2. `ls -G ~` — folders in the derived blue, the rest in ink; `exit 0`. The output card beneath the bar with the strip at its foot. Judge the colours in light appearance, then switch the system to dark and run it again.
3. `git -C ~/Vaults/sageframe-no-kaji-dev/issoku status` — the branch line and any changed paths coloured as `git` colours them.
4. `for i in $(seq 1 100); do printf '\r%3d%%' $i; sleep 0.02; done; echo` — one line counting up in place; `100%` at the end.
5. `ssh host-a 'ls --color=always /'` — remote colours; `exit 0`.
6. `ssh host-a 'sudo true'` — the refusal, `exit 1` in rust, the offer. Return in the empty input: the prompt appears before anything is typed, the block cursor after it; type the password; nothing is drawn; `exit 0`.
7. `yes | head -n 20000` — scroll back: the top of the transcript is the 10,001st `y` from the end. Press Copy, paste into a text editor, count the lines.
8. `head -c 50000000 /dev/urandom | base64` — the panel stays responsive while it streams; in a terminal while it runs, `ps -o rss= -p $(pgrep -x Issoku)` once at the start and once near the end; record both in KB. Press Stop halfway through a second run: it stops.
9. After item 8, select a few characters with the mouse, press `Command-C`, paste into a text editor: only the selection. Press `Command-C` with nothing selected, paste: everything retained.
10. `uptime` then Escape: the panel goes. Press the hotkey: the bar alone again. Repeat Escape in Done five times across items 2–7, watching for the once-seen case where Escape did not dismiss (ho-03 run sheet item 3).

The practitioner pastes the observations; the orchestrator records them in Reflect with host names redacted per the project's map.

### Done means

- The ho-01 command set renders readably through the real view, demonstrated by items 2–6 and the tests' use of the same sequences.
- 50 MB of output keeps the process under the ceiling, measured: the model's retained count in the test, the process's resident size at item 8.
- Copy behaves as specified with and without a selection, demonstrated (items 7 and 9) and tested.
- Composing is the bar alone; the output card appears at Running and goes at dismissal, demonstrated (items 1 and 10) and tested.
- The parser's recognised set is Decision 1's table, by inspection of the diff; the three derived colours and the kept input size are recorded in Reflect.
- `IssokuCore` and the measured `Sources/Issoku` set both at or above 90%.
- The six verification commands pass with output recorded; no warning suppressed; no force unwrap without `// FORCE:`; no SwiftUI in the panel.
- Commits on `main`: `ho-04: transcript — open` (this document), `ho-04: transcript — build verified; run sheet pending` (the build), and the closing `ho-04: transcript — the one monospace zone` (Reflect, the build-record entry), with any run-sheet change between. No trailers.
- The closing hash is recorded; ho-04x is authored from the x template over `e08c5ea0be1ed6443a6327869dda6f39ba7cab0a..<closing hash>` with the overview's ho-04x questions pasted verbatim, and the replan checkpoint that follows ho-04x is named in the State Memory.

---

## Phase 3 — Reflect

Filled 2026-11-04 after the practitioner's two run-sheet passes (2026-11-03 and 2026-11-04), the orchestrator's verification at every commit, and the two fix rounds the run sheet produced.

**Commits.** Done means named three; there are five, because the run sheet found four defects and produced two rulings:

| Commit | Message |
|---|---|
| `63067da0d10ce6e0ed3bd54c160e99f797c79348` | `ho-04: transcript — open` |
| `dd89260` | `ho-04: transcript — build verified; run sheet pending` |
| `199d9ab` | `ho-04: transcript — run-sheet fixes; input at 18, lines wrap, no jiggle, nothing drawn after Stop` |
| `5f814df` | `ho-04: transcript — the gear stays at the bar's trailing edge, centred` |
| the closing commit | `ho-04: transcript — the one monospace zone` (this Reflect, the build-record entry) |

ho-04x reads the whole range from `e08c5ea0be1ed6443a6327869dda6f39ba7cab0a`, the commit before the first of these.

**Did the design hold?** The model did, whole: every sequence the run sheet met was handled by Decision 1's table, nothing outside the ho-01 list needed honouring, and `Transcript` knows nothing of Run beyond receiving bytes. The view's layout cost did not hold as Decision 6 assumed, and the bar had two layout faults the Think phase's "input and gear in one row" did not foresee. Everything below was seen only in the running app; the test harness showed none of it, which is the lesson of this ho.

1. **Lines did not wrap.** The scroll view was created with no width, so the transcript's width mask became a constraint reading "clip width plus 616": the transcript was 1,232 points wide inside a 616-point clip and an 84-character line ran off the card. The harness sizes the view by a different path and wrapped correctly, so my own diagnostic test, run under both scroll-bar styles, could not reproduce it. Fixed by creating the scroll view at the transcript's width; a test now constructs a bare `PanelWindow` and checks the clip view has the transcript's width before any layout, then runs a 120-character line and counts two fragments.
2. **The cost per chunk grew with the transcript.** Three causes, all measured in the live app with a temporary driver: contiguous layout re-laid the whole document after every eviction from the top (194 ms per 1 KB chunk at 10,000 rows; 2.4 ms with `allowsNonContiguousLayout`); a growing line in progress was replaced whole, which laid the whole line out again (0.2 ms per KB of line per chunk; a line that only grew now has its new characters appended, the storage identical); and the cursor's `draw` laid out the whole container on every redraw (it lays out the last character now). Panel no longer calls `fit()` per chunk once the transcript is at the cap. All inside Decisions 5 and 6: one bytes task, one chunk per main-actor turn, no timer, no second queue. The pseudoterminal delivers 1,024-byte chunks; a drain of 1 MiB read ahead is about 1,000 main-actor turns at about 11 ms each with a display pass between, whatever the append costs.
3. **The window jiggled.** A fractional height set again on every chunk came back from the window server alternately a point taller and shorter (543 chunks at each of 474 and 475). The height is now rounded up to whole points: one value across 1,482 chunks.
4. **Stop did not seem to act.** It always did: the process group was gone within a second of every press. What the practitioner saw was the panel still drawing the up-to-1 MiB Run had read ahead: about 15 s for line output, minutes for one unbroken line, because each chunk drops the oldest characters from the head of a 1 MiB paragraph and the text system lays the whole paragraph out again (135–206 ms per chunk; non-contiguous layout and character wrapping do not help). The builder halted there, since any shorter drain changes a decision. **Practitioner's ruling (2026-11-03): after Stop, nothing more is drawn.** Panel sets a flag at Stop and Control-C; the bytes task still takes every chunk, so Run's contract holds and Done arrives, but appends nothing; the flag clears when the next command enters Running. The test gets from Stop to Done in about half a second and the next command draws again. The unbroken-line case is now a known limit, not a defect: one line past 1 MiB streams at roughly 5 KB/s while it runs, responsive, bounded, slow; curing it means Decision 5 showing only the tail of a huge line, and it goes to the replan week.

Two more from the second pass, both in the bar: the gear jumped to the left edge while a command ran, because the row's default distribution packed an input with nothing to edit at its own width (now `.fill`, the input stretching, the gear hugging); and it sat high, because the row aligned `.top` (now `.centerY`, centred on the whole row for a multi-line input, the practitioner's call). The harness showed the input at full width in both states, so only the centring has a test that fails without the fix; the practitioner confirmed both by eye.

**Decision review.** 1 (the honoured set) holds exactly; the parser's recognised set is the table and the diff shows nothing more. 2 (the colours) passed on screen in light and dark at items 2, 3 and 5; the derived values are below. 3 (the ceiling) holds and is measured, not asserted: the retained counts are below, and the process measurement is in Numbers. 4 (the model) holds; `Transcript` imports Foundation only. 5 (the view) holds as specified, with the three layout-cost changes above; copy with and without a selection passed at item 9; the cursor, redrawn by a cheaper path, was confirmed after the sudo prompt at item 6. 6 (the bytes task and the layout cost) kept its constraints but its premise was wrong: ranged edits do not confine the text system's work under contiguous layout, and `fit()` at the cap still cost a display pass per chunk. 7 (the layout) holds, with the two bar fixes; `inputSize` is one constant and the practitioner's ruling is **18**, after rebuilds at 12, 14, 16 and 18 ("it looks nice"), which is past the design system's text scale (it tops out at 15) and is recorded as his choice for the replan week to confirm. 8 (files, tests, one subagent, no split) held; the subagent returned three times more than planned, each time to a defect the run sheet found.

**Choices the subagent made beyond the spec, for ho-04x.** It removed `import SwiftUI` and the `Color` accessors from `Theme.swift` as unused by the panel; the practitioner ruled "keep" and they were restored. It shows the output card when a start fails, so the failure's notice and `exit` line have somewhere to sit; accepted. SGR 58 (underline colour) is not consumed with its arguments, since it is not on the ho-01 list; a `58;2;r;g;b` whose components land on 0, 1, 22, 30–37 or 39 would be read as those parameters. The selection colour is the system's and the input's caret is the system blue, not the accent. A 4,095-column variant of the lines ceiling test was added. The transcript tests `print` their retained counts so the numbers are in the transcript; `PanelTests.swift` carries a `file_length` suppression with its reason (one suite, one file, by Decision 8). `fit()` still calls `setFrame(display: true)` on every call below the cap: the builder tried skipping the call when the height was unchanged and two `isKeyWindow` assertions failed when the whole suite ran, so it was taken out. The `stopped` flag in Panel comes from the practitioner's ruling at item 8, not from the spec text; this Reflect is its record.

**Run sheet, practitioner's two passes.** Hosts are redacted; `host-d` is the one he used, not the spec's `host-a`.

1. 12, then 14, 16 and 18 by hand rebuilds; **18 stays**.
2. Pass, light and dark.
3. Pass.
4. Pass; `100%` at the end.
5. As written, no colours: the remote's coreutils 9.7 sends none when TERM is unset even under `--color=always`, and plain `ssh` sends no TERM; verified by capturing the bytes. Rerun as `ssh -t host-d 'ls --color=always /'`: pass, folders in the derived blue, links in cyan bold, a sticky directory's background code dropped and its text in ink. His first attempt typed the placeholder `host-a` literally; that error line, 84 characters, is what exposed the wrap defect.
6. Pass, both passes: the prompt before anything is typed, the block cursor after it, nothing drawn while the password is typed, `exit 0`.
7. Pass. On the first pass item 7 also found that Spotlight dismissed the panel; see Rulings.
8. First pass: fail, defects 2–4 above. Second pass with `base64 -b 76`: pass, a still window while it streams, Done within a second of Stop.
9. Pass, both ways.
10. Pass; Escape in Done five times across the items, never inert. The transcript now hands a key pressed in Done to the input, which is the likely explanation of ho-03's once-seen case.

**Numbers.** Resident size: the practitioner did not record `ps` at item 8, so the orchestrator measured the same path in the test process on 2026-11-04: 50 MB of 76-column lines in 16 KiB chunks through the real `TranscriptView` and `fit()`, 87,520 KB before, 97,728 KB after, 14.8 s. Retained counts from the model tests: one 50 MB line, largest 1,048,576; 50 MB of 76-column lines, largest 760,076, final 760,000; 50 MB of 4,095-column lines, largest and final 10,483,200; a 2 MiB line, 1,048,576. Lines, nonblank: `Transcript.swift` 307, `TranscriptView.swift` 166, `Theme.swift` 117, `Panel.swift` 238, `PanelWindow.swift` 303; `TranscriptTests.swift` 270, `PanelTests.swift` 764, `ThemeTests.swift` 76. Tests: 61 in IssokuCoreTests (21 Transcript), 40 in IssokuTests (33 Panel) [corrected 2026-11-04, ho-04.1: the two targets' totals were reversed; ho-04x N3]. Coverage at close: IssokuCore 95.85%, `Sources/Issoku` 92.79% over the measured set. The three derived colours, sRGB, light then dark: blue (0.3698, 0.4046, 0.5558) and (0.5184, 0.5515, 0.7259); magenta (0.5081, 0.3599, 0.4623) and (0.6758, 0.5015, 0.6135); cyan (0.2346, 0.4604, 0.4316) and (0.3649, 0.6170, 0.5895); derived in OKLCH from the five pālana tokens' mean lightness and chroma with the hue turned toward the warm axis, the dark set lifted as the tokens are. Input size kept: 18.

**Verification, orchestrator's runs.** At `dd89260`, `199d9ab`, `5f814df` and on the unchanged tree before the closing commit: `swift-format lint --recursive --strict Sources Tests` exit 0; `swiftlint lint --strict` 0 violations in 23 files; `swift build` complete, 0 warnings; `swift test` 40 tests in 4 suites and 61 in 5 suites, 0 failures; `scripts/coverage-floor.sh` 95.85% and 92.79% at close; `swift build -c release` complete, 0 warnings (builder's run, recorded). The subagent's transcripts of the same commands matched at every round; the Panel suite was run three extra times after each fix without a failure.

**What broke that the tests didn't catch?** All four defects and both bar faults. The harness creates and sizes the window by a path that is not the app's: the scroll view gets its width before the transcript's constraint is made, the input reports full width in every state, and nothing times a chunk. One test now pins the window's construction (the bare clip width); the timing stays unmeasured by test, since a timing assertion would be flaky, and is recorded here instead. The habit to keep: a run sheet that streams real output through the real window is not optional, and the first thing a defect report needs is a measurement in the live app, which the builder took with a temporary driver and removed.

**Rulings from this ho for later hos.**

- **The Escape ladder (practitioner, 2026-11-04), replacing the click-out ruling of 2026-11-03.** While Running, the first Escape stops the command, as Stop and Control-C do; the second Escape, or the first once the command is stopped or Done, dismisses, killing the command if it is somehow still alive, so nothing ever runs hidden. In Composing, Escape dismisses. Click-out dismisses only when nothing was typed and nothing ran; with text in the input the panel stays so the practitioner can open another app and come back to paste; in Done, click-out dismisses. The hotkey then becomes: hidden, show; visible without the keyboard, take the keyboard; visible with the keyboard, dismiss. This revises System Design 2.1 and ho-03's `resignKey` rule, so it is its own ho after ho-04x, and Escape no longer reaches the command as a key.
- **Replan week:** the unbroken-line streaming cost (above); the input at 18 against the design system's scale; the Escape ladder's priority against ho-05.
- **ho-05:** up-arrow history recall in the input, as already listed.

*Added 2026-11-04: ho-04x run 1 returned this ho; the answer is `ho-process/hos/ho-04.1-fix-pass.md`. The sentence above saying Theme's accessors "were restored" was wrong when written: nothing restored them, and ho-04.1 does.*

---

### Closing this ho

Closing = fill this Reflect + flip `status: complete` in the frontmatter + write the state-summary block to the top of `ho-process/kamae-6-issoku-state-memory.md` + append a build-record entry to `ho-process/kamae-4-issoku-ho-overview.md` with the closing hash recorded by the convention ho-00's entry states + regenerate `metadata/ho-status.md` and `metadata/ho-status.json`. Then author `ho-process/hos/ho-04x-review-of-transcript.md` from `ho-process/x-ho-template.md`, commit it, and hand off to Codex. The block, verbatim labels and order:

**STATE-SUMMARY**
- **COMPLETED** — <what this ho finished>
- **NEXT** — <the single pointer to what comes next>
- **ACTION ITEMS / BLOCKS** — <open items; blocks loudly, or `none`>
- **PROJECT LIFECYCLE** — kamae

---

_Authored: 2026-11-03 (Think phase, practitioner and orchestrator)._
_Execution: 2026-11-03 (one Opus subagent, three returns). Run sheet: 2026-11-03 and 2026-11-04. Reflect: 2026-11-04._
