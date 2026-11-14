import Foundation

/// What a command printed, as lines of styled text, within a fixed ceiling.
///
/// Bytes in, a change out. The grammar is what the commands measured in ho-01 needed and nothing more; anything
/// wider is a terminal emulator (ho-04 Decision 1):
/// - SGR `0` or empty resets, `1` is bold, `22` is regular weight, `30`–`37` set the colour and `39`
///   returns to the default. Every other parameter is ignored; `38`, `48` and `58` take their `5;n`
///   or `2;r;g;b` arguments with them. A parameter holding `:` is ignored whole.
/// - CR returns to column zero and the following characters overwrite; LF commits the line; TAB is
///   a character.
/// - Every other escape sequence is removed: CSI with any other final or with a private marker, OSC
///   and the DCS, SOS, PM and APC strings up to BEL or `ESC \`, and single-character ESC sequences
///   with their intermediate bytes. One longer than `sequenceByteLimit`, ESC included, is abandoned
///   and the parser returns to ground. Every other C0 control is dropped.
///
/// A UTF-8 continuation byte joins the character before it, so a character is one column. State
/// carries across feeds: a chunk may end inside a sequence or a character.
public struct Transcript: Sendable {
    /// A weight and a colour.
    public struct Style: Sendable, Equatable {
        /// Bold weight; SGR `1` sets it, `22` and a reset clear it.
        public var bold = false
        /// One of the eight basic colours, 0–7, or nil for the default; SGR `30`–`37` set it, `39`
        /// and a reset clear it.
        public var color: UInt8?
    }

    /// Adjacent characters of one style.
    public struct Span: Sendable, Equatable {
        /// The characters, decoded as UTF-8; a byte that is not becomes U+FFFD.
        public let text: String
        /// Their style.
        public let style: Style
    }

    /// One line of output, without its LF.
    public struct Line: Sendable, Equatable {
        /// The line's spans, in order; none for an empty line.
        public let spans: [Span]
        /// The bytes the line was made of, counted toward the ceiling.
        public let byteCount: Int

        /// The line's characters, without style.
        public var text: String { spans.map(\.text).joined() }
    }

    /// What one feed did, for a view that holds the lines reported so far.
    public struct Change: Sendable, Equatable {
        /// Lines dropped from the top of those already reported.
        public let evicted: Int
        /// Lines committed by this feed and still retained, oldest first.
        ///
        /// A line committed and dropped within the same feed is never reported.
        public let committed: [Line]
        /// The line in progress as it now stands, reported on every feed.
        public let inProgress: Line
    }

    /// The most committed lines kept, oldest dropped first.
    ///
    /// With the line in progress capped at 1 MiB, 10,000 lines held 50 MB of output at 9.7 MB peak
    /// resident (ho-01 findings, §4, second run).
    public static let lineLimit = 10_000
    /// The most bytes kept of the line in progress, oldest characters dropped first.
    ///
    /// A line count alone held a 66.7 MB single line whole at 174.5 MB peak resident; this cap held
    /// the same output at 9.7 MB (ho-01 findings, §4).
    public static let lineByteLimit = 1 << 20
    /// The most bytes kept across every retained line, oldest whole lines dropped first.
    ///
    /// Ten times the per-line cap, so 10,000 lines of wide output stay bounded too (ho-01 findings, §4).
    public static let byteLimit = 10 << 20
    /// How far the origin of the line in progress may move before the bytes behind it are dropped,
    /// so the dropping is paid once per this many bytes, not per byte; Run's read size (16 KiB), so a
    /// chunk from Run compacts at most once before the end-of-feed compaction.
    internal static let trimSlack = 16_384
    /// The longest escape or control sequence, ESC included, before it is abandoned: an unfinished one would
    /// otherwise grow without bound, outside the line cap (ho-01.1).
    public static let sequenceByteLimit = 256

    private enum State {
        case ground
        case escape
        case escapeIntermediate
        case controlSequence
        case controlString
        case controlStringEscape
    }

    private static let escapeByte: UInt8 = 0x1B
    private static let bell: UInt8 = 0x07
    /// What an evicted line leaves in its place until the array is compacted: nothing held.
    private static let evictedLine = Line(spans: [], byteCount: 0)

    /// The committed lines retained, oldest first.
    public private(set) var lines: [Line] = []
    /// The first retained line of `lines` during a feed.
    ///
    /// The lines before it are evicted and hold nothing; zero between feeds.
    private var head = 0
    /// Lines evicted since the feed began.
    private var dropped = 0
    private var committedBytes = 0
    private var state = State.ground
    /// The parameter and intermediate bytes of the control sequence being read.
    private var sequence: [UInt8] = []
    private var sequenceLength = 0
    private var style = Style()
    /// The line in progress, whole characters, and the style of each of its bytes, from `origin` on.
    private var bytes: [UInt8] = []
    private var styles: [Style] = []
    /// The first retained byte of the line in progress.
    ///
    /// It moves forward, by whole characters, so at most `lineByteLimit` bytes are retained after
    /// every byte; zero between feeds.
    private var origin = 0
    /// The style every byte of the line in progress has, or nil once two have differed; it spares
    /// the comparison of every byte when the line is reported on each feed.
    private var shared: Style?
    /// The byte offset of the column the next character takes; never before `origin`.
    private var cursor = 0

    /// An empty transcript in the default style.
    public init() {
        // Public: the memberwise initializer of a public struct is internal.
    }

    /// The bytes held across the committed lines and the line in progress.
    public var retainedBytes: Int { committedBytes + bytes.count - origin }

    /// Reads `input` and returns what changed since the last feed.
    public mutating func feed(_ input: [UInt8]) -> Change {
        let reported = lines.count
        dropped = 0
        for byte in input {
            step(byte)
        }
        // Every ceiling already holds at the byte that would break it; the feed only compacts.
        lines.removeFirst(head)
        head = 0
        compact()
        let evicted = min(dropped, reported)
        return Change(
            evicted: evicted,
            committed: Array(lines[(reported - evicted)...]),
            inProgress: Self.line(bytes[...], styles[...], shared: shared))
    }

    /// Forgets every line, the line in progress, the style and any sequence half read.
    public mutating func clear() {
        self = Self()
    }

    private mutating func step(_ byte: UInt8) {
        if state != .ground {
            sequenceLength += 1
            // A sequence that never ends would otherwise hold the parser forever; past the bound it
            // is noise and the stream reads as text again.
            guard sequenceLength <= Self.sequenceByteLimit else {
                sequence.removeAll()
                state = .ground
                return
            }
        }
        switch state {
        case .ground:
            ground(byte)
        case .escape:
            escape(byte)
        case .escapeIntermediate:
            switch byte {
            case 0x20...0x2F:
                break
            case 0x30...0x7E:
                state = .ground
            default:
                state = .ground
                ground(byte)
            }
        case .controlSequence:
            controlSequence(byte)
        case .controlString, .controlStringEscape:
            controlString(byte)
        }
    }

    private mutating func ground(_ byte: UInt8) {
        switch byte {
        case Self.escapeByte:
            state = .escape
            sequenceLength = 1
        case 0x0D:
            cursor = origin
        case 0x0A:
            commit()
        case 0x80...0xBF where cursor > origin:
            bytes.insert(byte, at: cursor)
            styles.insert(styles[cursor - 1], at: cursor)
            cursor += 1
            advanceOrigin()
            evict()
        case 0x09, 0x20...0xFF:
            put(byte)
        default:
            break
        }
    }

    private mutating func escape(_ byte: UInt8) {
        switch byte {
        case UInt8(ascii: "["):
            sequence.removeAll()
            state = .controlSequence
        case UInt8(ascii: "]"), UInt8(ascii: "P"), UInt8(ascii: "X"), UInt8(ascii: "^"), UInt8(ascii: "_"):
            state = .controlString
        case Self.escapeByte:
            sequenceLength = 1
        case 0x20...0x2F:
            state = .escapeIntermediate
        case 0x30...0x7E:
            state = .ground
        default:
            state = .ground
            ground(byte)
        }
    }

    /// Inside an OSC, DCS, SOS, PM or APC string, which BEL or `ESC \` ends and nothing else does.
    private mutating func controlString(_ byte: UInt8) {
        if byte == Self.escapeByte {
            state = .controlStringEscape
        } else if byte == Self.bell {
            state = .ground
        } else if state == .controlStringEscape {
            // After an ESC inside the string a backslash ends it, as BEL does above, and another ESC
            // waits again for one; any other byte is more of the string.
            state = byte == UInt8(ascii: "\\") ? .ground : .controlString
        }
    }

    private mutating func controlSequence(_ byte: UInt8) {
        switch byte {
        case 0x20...0x3F:
            sequence.append(byte)
        case UInt8(ascii: "m") where sequence.allSatisfy { (0x30...0x3B).contains($0) }:
            select()
            state = .ground
        case 0x40...0x7E:
            state = .ground
        default:
            state = .ground
            ground(byte)
        }
    }

    /// Applies an SGR's parameters in order.
    private mutating func select() {
        let parameters = sequence.split(separator: UInt8(ascii: ";"), omittingEmptySubsequences: false)
            .map(Self.number)
        var index = 0
        while index < parameters.count {
            switch parameters[index] {
            case 0?:
                style = Style()
            case 1?:
                style.bold = true
            case 22?:
                style.bold = false
            case .some(let code) where (30...37).contains(code):
                style.color = UInt8(code - 30)
            case 39?:
                style.color = nil
            case 38?, 48?, 58?:
                switch parameters.dropFirst(index + 1).first {
                case 5?:
                    index += 2
                case 2?:
                    index += 4
                default:
                    break
                }
            default:
                break
            }
            index += 1
        }
    }

    /// A parameter's value, zero when empty, nil when it holds anything but digits.
    private static func number(_ parameter: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for byte in parameter {
            guard (0x30...0x39).contains(byte) else { return nil }
            value = min(value * 10 + Int(byte - 0x30), 1_000)
        }
        return value
    }

    /// Writes a character's first byte at the cursor, replacing the whole character there.
    private mutating func put(_ byte: UInt8) {
        shared = bytes.isEmpty || shared == style ? style : nil
        if cursor < bytes.count {
            var end = cursor + 1
            while end < bytes.count, Self.isContinuation(bytes[end]) {
                end += 1
            }
            bytes.replaceSubrange(cursor..<end, with: CollectionOfOne(byte))
            styles.replaceSubrange(cursor..<end, with: CollectionOfOne(style))
        } else {
            bytes.append(byte)
            styles.append(style)
        }
        cursor += 1
        advanceOrigin()
        evict()
    }

    /// Commits the retained line, then evicts from the top what the ceilings no longer hold.
    private mutating func commit() {
        let line = Self.line(bytes[origin...], styles[origin...], shared: shared)
        lines.append(line)
        committedBytes += line.byteCount
        bytes.removeAll()
        styles.removeAll()
        origin = 0
        cursor = 0
        evict()
    }

    /// Drops the oldest committed lines while more than `lineLimit` remain or more than `byteLimit`
    /// bytes are retained; they are counted, and released at once.
    ///
    /// Called after every byte that adds a line or changes the line in progress, so the ceilings hold
    /// after every byte and no partition of the bytes into feeds changes what is dropped.
    private mutating func evict() {
        while head < lines.count, lines.count - head > Self.lineLimit || retainedBytes > Self.byteLimit {
            committedBytes -= lines[head].byteCount
            lines[head] = Self.evictedLine
            head += 1
            dropped += 1
        }
        if head >= Self.lineLimit {
            lines.removeFirst(head)
            head = 0
        }
    }

    /// Moves the origin past the oldest characters, whole, until at most `lineByteLimit` bytes are
    /// retained, and drops what lies behind it once that passes the slack.
    private mutating func advanceOrigin() {
        while bytes.count - origin > Self.lineByteLimit {
            origin += 1
            while origin < bytes.count, Self.isContinuation(bytes[origin]) {
                origin += 1
            }
        }
        cursor = max(cursor, origin)
        if origin > Self.trimSlack { compact() }
    }

    /// Drops the bytes before the origin; what is reported does not change.
    private mutating func compact() {
        bytes.removeFirst(origin)
        styles.removeFirst(origin)
        cursor -= origin
        origin = 0
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        byte & 0xC0 == 0x80
    }

    private static func line(_ bytes: ArraySlice<UInt8>, _ styles: ArraySlice<Style>, shared: Style?) -> Line {
        var spans: [Span] = []
        var start = bytes.startIndex
        while start < bytes.endIndex {
            var end = shared == nil ? start + 1 : bytes.endIndex
            while end < bytes.endIndex, styles[end] == styles[start] {
                end += 1
            }
            // Decoding repairs, never drops: a byte that is not UTF-8 becomes U+FFFD, and the failable
            // initializer the rule prefers would lose the whole span.
            // swiftlint:disable:next optional_data_string_conversion
            spans.append(Span(text: String(decoding: bytes[start..<end], as: UTF8.self), style: styles[start]))
            start = end
        }
        return Line(spans: spans, byteCount: bytes.count)
    }
}
