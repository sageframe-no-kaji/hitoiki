import Testing

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

/// What one feed reported, and what the transcript held after it.
private struct Feed {
    let evicted: Int
    let retainedBytes: Int
    let lines: Int
}

/// `count` bytes, byte `index` being `byte(index)`, in 16 KiB feeds; every feed read, and the last change.
private func stream(
    _ transcript: inout Transcript,
    count: Int,
    byte: (Int) -> UInt8
) -> (feeds: [Feed], last: Transcript.Change?) {
    var feeds: [Feed] = []
    var last: Transcript.Change?
    var offset = 0
    while offset < count {
        let end = min(offset + 16_384, count)
        let change = transcript.feed((offset..<end).map(byte))
        feeds.append(
            Feed(evicted: change.evicted, retainedBytes: transcript.retainedBytes, lines: transcript.lines.count))
        last = change
        offset = end
    }
    return (feeds, last)
}

@Suite("Transcript")
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
            "[38:5:31m", "[>4;1m", "[?1m", "[38m",
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
        #expect(fits.utf8.count == Transcript.sequenceByteLimit)
        #expect(spans(fits + "x\n") == [Span(text: "x", style: Style(bold: true))])

        let over = "\(escape)[" + String(repeating: ";", count: 253) + "1m"
        #expect(spans(over + "x\n") == [Span(text: "x", style: Style())])

        let unterminated = "\(escape)[" + String(repeating: "1", count: 298)
        #expect(unterminated.utf8.count == 300)
        #expect(committed(unterminated + "after\n") == [String(repeating: "1", count: 43) + "after"])
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
        let first = transcript.feed(Array(String(repeating: "x\n", count: Transcript.lineLimit).utf8))
        #expect(first.evicted == 0)
        #expect(first.committed.count == Transcript.lineLimit)
        let last = transcript.feed(Array("y\n".utf8))
        #expect(last.evicted == 1)
        #expect(last.committed.map(\.text) == ["y"])
        #expect(transcript.lines.count == Transcript.lineLimit)
        #expect(transcript.lines.last?.text == "y")
    }

    @Test("Lines committed and dropped within one feed are never reported")
    internal func droppedWithinOneFeed() {
        var transcript = Transcript()
        _ = transcript.feed(Array("a\n".utf8))
        let change = transcript.feed(Array(String(repeating: "x\n", count: Transcript.lineLimit + 5).utf8))
        #expect(change.evicted == 1)
        #expect(change.committed.count == Transcript.lineLimit)
        #expect(transcript.lines.count == Transcript.lineLimit)
    }

    @Test("A 2 MiB line keeps its newest 1 MiB; the retained count never passes the per-line bound")
    internal func lineInProgressCeiling() {
        var transcript = Transcript()
        let count = 2 << 20
        let digit = { (index: Int) in UInt8(ascii: "0") + UInt8(index % 10) }
        let (feeds, last) = stream(&transcript, count: count, byte: digit)
        let largest = feeds.map(\.retainedBytes).max() ?? 0
        print("transcript: 2 MiB line, largest retained \(largest), final \(transcript.retainedBytes)")
        #expect(largest <= Transcript.lineByteLimit)
        #expect(transcript.retainedBytes == Transcript.lineByteLimit)
        let expected = String((count - Transcript.lineByteLimit..<count).map { Character(Unicode.Scalar(digit($0))) })
        #expect(last?.inProgress.text == expected)
    }

    @Test("The oldest columns go whole characters at a time, and overwrite still lands on whole characters")
    internal func overwriteAfterDrop() {
        var transcript = Transcript()
        let dots = Transcript.lineByteLimit / 3 + 1
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
        let (feeds, _) = stream(&transcript, count: fed * width) { index in
            index % width == columns ? 0x0A : UInt8(ascii: "A") + UInt8(index % width % 26)
        }
        let largest = feeds.map(\.retainedBytes).max() ?? 0
        print("transcript: \(columns)-column lines, largest retained \(largest), final \(transcript.retainedBytes)")
        #expect(largest <= Transcript.byteLimit)
        #expect(feeds.allSatisfy { $0.lines <= Transcript.lineLimit })
        #expect(feeds.map(\.evicted).reduce(0, +) + transcript.lines.count == fed)
    }

    @Test("50 MB on one line in 16 KiB feeds: at most 1 MiB retained after every feed")
    internal func streamedLine() {
        var transcript = Transcript()
        let (feeds, _) = stream(&transcript, count: 50_000_000) { _ in UInt8(ascii: "Q") }
        let largest = feeds.map(\.retainedBytes).max() ?? 0
        print("transcript: one 50 MB line, largest retained \(largest), final \(transcript.retainedBytes)")
        #expect(largest <= Transcript.lineByteLimit)
        #expect(transcript.lines.isEmpty)
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
