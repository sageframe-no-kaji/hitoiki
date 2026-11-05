import Darwin
import Foundation
import Testing
import os

@testable import IssokuCore

internal typealias Span = Transcript.Span
internal typealias Style = Transcript.Style

private let escape = "\u{1B}"

/// Every line the feeds committed, then the line in progress after the last.
private func render(_ chunks: [[UInt8]]) -> (lines: [Transcript.Line], inProgress: Transcript.Line) {
    var transcript = Transcript()
    var inProgress = Transcript.Line(spans: [], byteCount: 0)
    for chunk in chunks {
        inProgress = transcript.feed(chunk).inProgress
    }
    return (transcript.lines, inProgress)
}

/// The committed lines' text after one feed of `text`.
private func committed(_ text: String) -> [String] {
    var transcript = Transcript()
    return transcript.feed(Array(text.utf8)).committed.map(\.text)
}

/// The one committed line's spans after one feed of `text`.
private func spans(_ text: String) -> [Span] {
    var transcript = Transcript()
    return transcript.feed(Array(text.utf8)).committed.first?.spans ?? []
}

/// `input` in feeds of `size` bytes: the transcript after the last, and the last change.
private func fed(_ input: [UInt8], by size: Int) -> (transcript: Transcript, last: Transcript.Change?) {
    var transcript = Transcript()
    var last: Transcript.Change?
    for start in stride(from: 0, to: input.count, by: size) {
        last = transcript.feed(Array(input[start..<min(start + size, input.count)]))
    }
    return (transcript, last)
}

/// One way of feeding the same bytes, and the transcript it left.
private struct Partition {
    let name: String
    let transcript: Transcript
    let last: Transcript.Change?
}

/// `prefix` then `tail` fed whole, and under every partition the tests name; the one-feed transcript.
///
/// The partitions: the whole input in 16,384- and 1,024-byte feeds, and the prefix in 16 KiB feeds
/// with the tail split at every point and one byte per feed. Each must leave the lines, the line in
/// progress and the retained count of one feed.
private func equivalent(
    _ prefix: [UInt8], _ tail: [UInt8], sourceLocation: SourceLocation = #_sourceLocation
) -> Transcript {
    var whole = Transcript()
    let all = whole.feed(prefix + tail)
    var partitions: [Partition] = []
    for size in [16_384, 1_024] {
        let (transcript, last) = fed(prefix + tail, by: size)
        partitions.append(Partition(name: "\(size)-byte feeds", transcript: transcript, last: last))
    }
    let (start, _) = fed(prefix, by: 16_384)
    var tails = (0...tail.count).map { split in
        (name: "tail split at \(split)", feeds: [Array(tail[..<split]), Array(tail[split...])])
    }
    tails.append((name: "tail one byte per feed", feeds: tail.map { [$0] }))
    for (name, feeds) in tails {
        var transcript = start
        var last: Transcript.Change?
        for feed in feeds {
            last = transcript.feed(feed)
        }
        partitions.append(Partition(name: name, transcript: transcript, last: last))
    }
    for partition in partitions {
        #expect(partition.transcript.lines == whole.lines, "\(partition.name)", sourceLocation: sourceLocation)
        #expect(partition.last?.inProgress == all.inProgress, "\(partition.name)", sourceLocation: sourceLocation)
        #expect(
            partition.transcript.retainedBytes == whole.retainedBytes, "\(partition.name)",
            sourceLocation: sourceLocation)
    }
    return whole
}

/// The most bytes the allocator had in use at any sampled instant while `work` ran, less what it
/// had before: the peak, not an endpoint difference.
///
/// The allocator's own count, not the kernel's resident size, which is reclaimed lazily: a resident
/// reading fell by tens of MB during the feed as earlier tests' pages went back, hiding any growth.
/// A thread samples every millisecond; a feed that holds its lines until it returns is seen at its
/// largest. An endpoint reading would not see it at all.
private func peakAllocatedGrowth(during work: () -> Void) -> Int {
    let peak = OSAllocatedUnfairLock(initialState: mstats().bytes_used)
    let before = peak.withLock { $0 }
    let sampling = OSAllocatedUnfairLock(initialState: true)
    let sampler = Thread {
        while sampling.withLock({ $0 }) {
            let used = mstats().bytes_used
            peak.withLock { $0 = max($0, used) }
            usleep(1_000)
        }
    }
    sampler.start()
    work()
    sampling.withLock { $0 = false }
    while !sampler.isFinished {
        usleep(1_000)
    }
    return peak.withLock { $0 } - before
}

/// What one feed reported, and what the transcript held after it.
private struct Feed {
    let evicted: Int
    let retainedBytes: Int
    let lines: Int
}

/// `count` bytes, byte `index` being `byte(index)` and repeating every `period`, in 16 KiB feeds;
/// every feed read, and the last change.
private func stream(
    _ transcript: inout Transcript,
    count: Int,
    period: Int,
    byte: (Int) -> UInt8
) -> (feeds: [Feed], last: Transcript.Change?) {
    // One period, tiled past a feed's length, so each feed is a slice rather than a call per byte.
    let tile = Array(repeating: (0..<period).map(byte), count: 16_384 / period + 2).flatMap(\.self)
    var feeds: [Feed] = []
    var last: Transcript.Change?
    var offset = 0
    while offset < count {
        let end = min(offset + 16_384, count)
        let phase = offset % period
        let change = transcript.feed(Array(tile[phase..<phase + end - offset]))
        feeds.append(
            Feed(evicted: change.evicted, retainedBytes: transcript.retainedBytes, lines: transcript.lines.count))
        last = change
        offset = end
    }
    return (feeds, last)
}

// Serialized: the resident-size reading must not see another test's allocations.
@Suite("Transcript", .serialized)
internal struct TranscriptTests {
    @Test("LF commits a line; the line in progress is reported on every feed")
    internal func lines() {
        #expect(committed("a\nb\n") == ["a", "b"])

        var transcript = Transcript()
        let first = transcript.feed(Array("a\nb".utf8))
        #expect(first.committed.map(\.text) == ["a"])
        #expect(first.inProgress.text == "b")
        let second = transcript.feed(Array("\n".utf8))
        #expect(second.committed.map(\.text) == ["b"])
        #expect(second.inProgress.text.isEmpty)
        #expect(transcript.lines.map(\.text) == ["a", "b"])
    }

    @Test("A prompt with no LF is on screen after its feed")
    internal func prompt() {
        var transcript = Transcript()
        let change = transcript.feed(Array("[sudo] password for user: ".utf8))
        #expect(change.committed.isEmpty)
        #expect(change.inProgress.text == "[sudo] password for user: ")
    }

    @Test(
        "CR returns to column zero and the following characters overwrite",
        arguments: [
            ("abc\rXY\n", ["XYc"]),
            ("1%\r2%\r100%\n", ["100%"]),
            ("text\r\r\n", ["text"]),
            ("é\rx\n", ["x"]),
            ("abc\ré\n", ["ébc"]),
        ])
    internal func carriageReturn(input: String, expected: [String]) {
        var transcript = Transcript()
        let change = transcript.feed(Array(input.utf8))
        #expect(change.committed.map(\.text) == expected)
        #expect(change.inProgress.spans.isEmpty)
    }

    @Test("SGR 31 then 0: red, then the default style")
    internal func redThenReset() {
        #expect(
            spans("\(escape)[31mred\(escape)[0m plain\n") == [
                Span(text: "red", style: Style(color: 1)),
                Span(text: " plain", style: Style()),
            ])
    }

    @Test("SGR 1;34 is applied in order: one bold blue span")
    internal func boldBlue() {
        #expect(spans("\(escape)[1;34mblue\n") == [Span(text: "blue", style: Style(bold: true, color: 4))])
    }

    @Test(
        "22 ends bold and keeps the colour; 39 ends the colour and keeps bold; an empty SGR resets",
        arguments: [
            ("22", Style(color: 1)),
            ("39", Style(bold: true)),
            ("", Style()),
            ("0", Style()),
            (";", Style()),
        ])
    internal func styleEnds(parameters: String, after: Style) {
        #expect(
            spans("\(escape)[1;31mab\(escape)[\(parameters)mcd\n") == [
                Span(text: "ab", style: Style(bold: true, color: 1)),
                Span(text: "cd", style: after),
            ])
    }

    @Test("The style persists across LF until it is changed")
    internal func stylePersists() {
        var transcript = Transcript()
        let change = transcript.feed(Array("\(escape)[32ma\nb\n\(escape)[mc\n".utf8))
        #expect(
            change.committed.map(\.spans) == [
                [Span(text: "a", style: Style(color: 2))],
                [Span(text: "b", style: Style(color: 2))],
                [Span(text: "c", style: Style())],
            ])
    }

    @Test(
        "Parameters outside the list change nothing; extended colours take their arguments with them",
        arguments: [
            "[38;5;31m", "[38;2;255;0;0m", "[48;5;196m", "[48;2;1;34;1m", "[4m", "[2m", "[91m", "[44m",
            "[38:5:31m", "[>4;1m", "[?1m", "[38m", "[58;2;1;34;1m", "[58;5;1m",
        ])
    internal func ignoredParameters(sequence: String) {
        #expect(spans("\(escape)\(sequence)x\n") == [Span(text: "x", style: Style())])
        #expect(
            spans("\(escape)[1;31m\(escape)\(sequence)x\n") == [Span(text: "x", style: Style(bold: true, color: 1))])
    }

    @Test(
        "Every other sequence and control is removed and the text around it joins",
        arguments: [
            "\(escape)[2J", "\(escape)[3A", "\(escape)[K", "\(escape)]0;title\u{07}", "\(escape)]0;title\(escape)\\",
            "\(escape)P1$r0m\(escape)\\", "\(escape)X sos \u{07}", "\(escape)^pm\u{07}", "\(escape)_apc\u{07}",
            "\(escape)(B", "\(escape)7", "\(escape)\(escape)7", "\u{07}", "\u{08}", "\u{0C}", "\u{0B}", "\u{00}",
            "\(escape)]0;before\(escape)7LEAK\u{07}", "\(escape)Pbefore\(escape)7LEAK\(escape)\\",
            "\(escape)]0;t\(escape)\(escape)\\",
            "\(escape)]before\(escape)\u{07}", "\(escape)Pbefore\(escape)\u{07}", "\(escape)Xbefore\(escape)\u{07}",
            "\(escape)^before\(escape)\u{07}", "\(escape)_before\(escape)\u{07}",
        ])
    internal func removed(sequence: String) {
        #expect(spans("a\(sequence)b\n") == [Span(text: "ab", style: Style())])
    }

    @Test("A control byte inside a sequence ends it and is itself handled")
    internal func interrupted() {
        #expect(committed("a\(escape)[1\nb\n") == ["a", "b"])
        #expect(committed("a\(escape)(\nb\n") == ["a", "b"])
        #expect(committed("a\(escape)\nb\n") == ["a", "b"])
    }

    @Test("TAB is kept as a character")
    internal func tab() {
        #expect(committed("a\tb\n") == ["a\tb"])
    }

    @Test(
        "Fed one byte at a time, or split at any boundary, the lines are those of one feed",
        arguments: ["\(escape)[1;34mblue\(escape)[0m\n", "●\n", "a\(escape)]0;t\(escape)\\b\r\(escape)[31mc\n"])
    internal func splitChunks(input: String) {
        let bytes = Array(input.utf8)
        let whole = render([bytes])
        #expect(!whole.lines.isEmpty)
        let single = render(bytes.map { [$0] })
        #expect(single.lines == whole.lines)
        #expect(single.inProgress == whole.inProgress)
        for split in 0...bytes.count {
            let halves = render([Array(bytes[..<split]), Array(bytes[split...])])
            #expect(halves.lines == whole.lines, "split at \(split)")
            #expect(halves.inProgress == whole.inProgress, "split at \(split)")
        }
    }

    @Test("A sequence is abandoned past exactly 256 bytes, ESC included, and the rest reads as text")
    internal func sequenceBound() {
        let fits = "\(escape)[" + String(repeating: ";", count: 252) + "1m"
        #expect(fits.utf8.count == 256)
        #expect(spans(fits + "x\n") == [Span(text: "x", style: Style(bold: true))])

        let over = "\(escape)[" + String(repeating: ";", count: 253) + "1m"
        #expect(spans(over + "x\n") == [Span(text: "x", style: Style())])

        let unterminated = "\(escape)[" + String(repeating: "1", count: 298)
        #expect(unterminated.utf8.count == 300)
        #expect(committed(unterminated + "after\n") == [String(repeating: "1", count: 43) + "after"])

        let string = "\(escape)]" + String(repeating: "x", count: 298)
        #expect(committed("a" + string + "b\n") == ["a" + String(repeating: "x", count: 43) + "b"])
        let escaped = "\(escape)]\(escape)7" + String(repeating: "x", count: 296)
        #expect(escaped.utf8.count == 300)
        #expect(committed("a" + escaped + "b\n") == ["a" + String(repeating: "x", count: 43) + "b"])
    }

    @Test("Multi-byte characters stay whole, across a chunk boundary too")
    internal func utf8() {
        #expect(committed("├─ ●\n") == ["├─ ●"])
        let dot = Array("●\n".utf8)
        var transcript = Transcript()
        _ = transcript.feed(Array(dot[..<2]))
        #expect(transcript.feed(Array(dot[2...])).committed.map(\.text) == ["●"])
    }

    @Test("10,001 lines leave 10,000; the change after the last reports one evicted")
    internal func lineCeiling() {
        var transcript = Transcript()
        let first = transcript.feed(Array(String(repeating: "x\n", count: 10_000).utf8))
        #expect(first.evicted == 0)
        #expect(first.committed.count == 10_000)
        let last = transcript.feed(Array("y\n".utf8))
        #expect(last.evicted == 1)
        #expect(last.committed.map(\.text) == ["y"])
        #expect(transcript.lines.count == 10_000)
        #expect(transcript.lines.last?.text == "y")
    }

    @Test("Lines committed and dropped within one feed are never reported")
    internal func droppedWithinOneFeed() {
        var transcript = Transcript()
        _ = transcript.feed(Array("a\n".utf8))
        let change = transcript.feed(Array(String(repeating: "x\n", count: 10_005).utf8))
        #expect(change.evicted == 1)
        #expect(change.committed.count == 10_000)
        #expect(transcript.lines.count == 10_000)
    }

    @Test("A 2 MiB line keeps its newest 1 MiB, and commits 1 MiB at its LF; the retained count never passes 1 MiB")
    internal func lineInProgressCeiling() {
        var transcript = Transcript()
        let count = 2 << 20
        let digit = { (index: Int) in UInt8(ascii: "0") + UInt8(index % 10) }
        let (feeds, last) = stream(&transcript, count: count, period: 10, byte: digit)
        let largest = feeds.map(\.retainedBytes).max() ?? 0
        print("transcript: 2 MiB line, largest retained \(largest), final \(transcript.retainedBytes)")
        #expect(largest <= 1_048_576)
        #expect(transcript.retainedBytes == 1_048_576)
        let expected = String((count - 1_048_576..<count).map { Character(Unicode.Scalar(digit($0))) })
        #expect(last?.inProgress.text == expected)
        let commit = transcript.feed([0x0A])
        #expect(commit.committed.map(\.byteCount) == [1_048_576])
        #expect(commit.committed.first?.text == expected)
        #expect(transcript.retainedBytes == 1_048_576)
    }

    @Test("The oldest columns go whole characters at a time, and overwrite still lands on whole characters")
    internal func overwriteAfterDrop() {
        var transcript = Transcript()
        let dots = 1_048_576 / 3 + 1
        _ = transcript.feed(Array(String(repeating: "●", count: dots).utf8))
        #expect(transcript.retainedBytes == (dots - 1) * 3)
        let change = transcript.feed(Array("\rb\n".utf8))
        let text = change.committed.first?.text ?? ""
        #expect(text == "b" + String(repeating: "●", count: dots - 2))
    }

    @Test(
        "50 MB of lines in 16 KiB feeds: at most 10 MiB retained after every feed, every line accounted for",
        arguments: [76, 4_095])
    internal func streamedLines(columns: Int) {
        var transcript = Transcript()
        let width = columns + 1
        let fed = 50_000_000 / width
        let (feeds, _) = stream(&transcript, count: fed * width, period: width) { index in
            index % width == columns ? 0x0A : UInt8(ascii: "A") + UInt8(index % width % 26)
        }
        let largest = feeds.map(\.retainedBytes).max() ?? 0
        print("transcript: \(columns)-column lines, largest retained \(largest), final \(transcript.retainedBytes)")
        #expect(largest <= 10_485_760)
        #expect(feeds.allSatisfy { $0.lines <= 10_000 })
        #expect(feeds.map(\.evicted).reduce(0, +) + transcript.lines.count == fed)
    }

    @Test("50 MB on one line in 16 KiB feeds: at most 1 MiB retained after every feed, 1 MiB committed at the LF")
    internal func streamedLine() {
        var transcript = Transcript()
        let (feeds, _) = stream(&transcript, count: 50_000_000, period: 1) { _ in UInt8(ascii: "Q") }
        let largest = feeds.map(\.retainedBytes).max() ?? 0
        print("transcript: one 50 MB line, largest retained \(largest), final \(transcript.retainedBytes)")
        #expect(largest <= 1_048_576)
        #expect(transcript.lines.isEmpty)
        #expect(transcript.feed([0x0A]).committed.map(\.byteCount) == [1_048_576])
    }

    @Test("An LF commits at most 1 MiB, however the bytes before it were chunked")
    internal func lineCapAtCommit() {
        let line = [UInt8](repeating: UInt8(ascii: "x"), count: 2_097_152) + [0x0A]
        var whole = Transcript()
        #expect(whole.feed(line).committed.map(\.byteCount) == [1_048_576])
        #expect(whole.retainedBytes == 1_048_576)

        var chunked = Transcript()
        for start in stride(from: 0, to: line.count, by: 1_024) {
            _ = chunked.feed(Array(line[start..<min(start + 1_024, line.count)]))
        }
        #expect(chunked.lines == whole.lines)
        #expect(chunked.retainedBytes == whole.retainedBytes)

        var full = Transcript()
        _ = full.feed([UInt8](repeating: UInt8(ascii: "x"), count: 1_048_576))
        #expect(full.retainedBytes == 1_048_576)
        let tail = full.feed([UInt8](repeating: UInt8(ascii: "y"), count: 1_023) + [0x0A])
        #expect(tail.committed.map(\.byteCount) == [1_048_576])
        #expect(tail.committed.first?.text.hasSuffix(String(repeating: "y", count: 1_023)) == true)
    }

    @Test("clear() empties the lines, resets the style and starts a fresh line")
    internal func clear() {
        var transcript = Transcript()
        _ = transcript.feed(Array("\(escape)[1;31mab\ncd\(escape)]0;ti".utf8))
        transcript.clear()
        #expect(transcript.lines.isEmpty)
        #expect(transcript.retainedBytes == 0)
        let change = transcript.feed(Array("tle\u{07}x\n".utf8))
        #expect(change.committed.map(\.spans) == [[Span(text: "tlex", style: Style())]])
    }
}

// The ceilings across feed ends and within one feed (ho-04.2): an extension, not a second suite, so
// these stay serialized with the rest of the suite.
extension TranscriptTests {
    @Test("Fed whole or in 16 KiB or 1,024-byte chunks across all three ceilings, with overwrites, it is the same")
    internal func ceilingsChunked() {
        var input = Array(String(repeating: "éa\rZ\n", count: 5_500).utf8)
        input += Array(String(repeating: "ab\ré\n", count: 5_500).utf8)
        let grows = [UInt8](repeating: UInt8(ascii: "w"), count: 1_999) + Array("\réé\n".utf8)
        let shrinks = Array((String(repeating: "é", count: 999) + "w\rZZ\n").utf8)
        for _ in 0..<3_000 {
            input += grows + shrinks
        }
        input += [UInt8](repeating: UInt8(ascii: "L"), count: 2_097_152) + Array("\ré".utf8)
        input += [UInt8](repeating: UInt8(ascii: "y"), count: 1_023) + Array("\rZ\n".utf8)
        input += Array(String(repeating: "é", count: 786_432).utf8) + Array("\rQ".utf8)
        input += [UInt8](repeating: UInt8(ascii: "u"), count: 1_000)

        var whole = Transcript()
        let all = whole.feed(input)
        for size in [16_384, 1_024] {
            let (chunked, last) = fed(input, by: size)
            #expect(chunked.lines == whole.lines, "in \(size)-byte feeds")
            #expect(last?.inProgress == all.inProgress, "in \(size)-byte feeds")
            #expect(chunked.retainedBytes == whole.retainedBytes, "in \(size)-byte feeds")
        }
        #expect(whole.lines.count <= 10_000)
        #expect(whole.retainedBytes <= 10_485_760)
        #expect(whole.lines.allSatisfy { $0.byteCount <= 1_048_576 })
        #expect(whole.lines.last?.text.hasPrefix("Z") == true)
        #expect(all.inProgress.byteCount == 1_048_576 - 1 - 1_000)
        #expect(all.inProgress.text.hasPrefix("Q" + String(repeating: "u", count: 1_000) + "é") == true)
    }

    @Test("A carriage return after the oldest columns go lands on the first retained column, however fed")
    internal func overwriteAcrossFeedEnds() {
        let input =
            [UInt8](repeating: UInt8(ascii: "x"), count: 1_048_576)
            + [UInt8](repeating: UInt8(ascii: "y"), count: 1_023)
            + Array("\rZ\n".utf8)
        var whole = Transcript()
        let line = whole.feed(input).committed
        #expect(line.map(\.byteCount) == [1_048_576])
        #expect(line.first?.text.hasPrefix("Zxxx") == true)
        #expect(line.first?.text.hasSuffix(String(repeating: "y", count: 1_023)) == true)
        for size in [16_384, 1_024] {
            #expect(fed(input, by: size).transcript.lines == whole.lines, "in \(size)-byte feeds")
        }
    }

    @Test("One 50 MB feed of short lines holds only what the ceilings keep, while it is read too")
    internal func oneFeedCeiling() {
        let input = Array(repeating: [UInt8](repeating: UInt8(ascii: "x"), count: 99) + [0x0A], count: 500_000)
            .flatMap(\.self)
        #expect(input.count == 50_000_000)
        var whole = Transcript()
        var change: Transcript.Change?
        let growth = peakAllocatedGrowth { change = whole.feed(input) }
        print("transcript: one 50 MB feed, peak allocated growth \(growth)")
        #expect(growth < 32 << 20)
        #expect(change?.committed.count == 10_000)
        #expect(change?.evicted == 0)
        #expect(whole.retainedBytes == 990_000)
        #expect(fed(input, by: 16_384).transcript.lines == whole.lines)
    }

    @Test("The reviewer's probe: the oldest line goes at the byte that passes 10 MiB, under every partition")
    internal func aggregateCeilingPerByte() {
        var prefix: [UInt8] = []
        for letter in "ABCDEFGHI".utf8 {
            prefix += [UInt8](repeating: letter, count: 1_048_576) + [0x0A]
        }
        prefix += [UInt8](repeating: UInt8(ascii: "J"), count: 1_048_575) + [0x0A]
        let whole = equivalent(prefix, Array("é\rZ\n".utf8))
        #expect(whole.lines.count == 10)
        #expect(whole.lines.first?.text.hasPrefix("B") == true)
        #expect(whole.lines.last?.text == "Z")
        #expect(whole.retainedBytes == 9_437_184)
    }

    @Test("The line window: a character that passes 1 MiB moves the origin, under every partition")
    internal func lineWindowPerByte() {
        let whole = equivalent([UInt8](repeating: UInt8(ascii: "x"), count: 1_048_575), Array("é\rZ\n".utf8))
        #expect(whole.lines.map(\.byteCount) == [1_048_576])
        #expect(whole.lines.first?.text.hasPrefix("Zx") == true)
        #expect(whole.lines.first?.text.hasSuffix("xé") == true)
    }

    @Test("The line count: each commit past 10,000 drops the oldest, under every partition")
    internal func lineCountPerByte() {
        let prefix = Array((0..<10_000).map { "line \($0)\n" }.joined().utf8)
        let whole = equivalent(prefix, Array("é\rZ\né\rZ\n".utf8))
        #expect(whole.lines.count == 10_000)
        #expect(whole.lines.first?.text == "line 2")
        #expect(whole.lines.suffix(2).map(\.text) == ["Z", "Z"])
    }

    @Test("Each of SGR 30–37 sets its colour index", arguments: 0...7)
    internal func foreground(index: Int) {
        #expect(spans("\(escape)[3\(index)mx\n") == [Span(text: "x", style: Style(color: UInt8(index)))])
    }

    @Test("A CR overwrite in another style replaces the styled columns it covers and keeps the rest")
    internal func styledOverwrite() {
        #expect(
            spans("\(escape)[31mabcd\r\(escape)[1;34mXY\(escape)[0m\n") == [
                Span(text: "XY", style: Style(bold: true, color: 4)),
                Span(text: "cd", style: Style(color: 1)),
            ])
    }
}
