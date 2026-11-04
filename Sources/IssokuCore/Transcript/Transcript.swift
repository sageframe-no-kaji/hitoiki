import Foundation

/// What a command printed, as lines of styled text, within a fixed ceiling.
///
/// Bytes in, a change out. The grammar is the ho-01 list and nothing more (ho-04 Decision 1):
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
    /// Ten times the per-line cap, so 10,000 lines of wide output stay bounded too (ho-04 Decision 3,
    /// from ho-01 findings, §4).
    public static let byteLimit = 10 << 20
    /// How far the line in progress may pass `lineByteLimit` before it is trimmed mid-feed, so the
    /// trimming is paid once per this many bytes, not per byte; Run's read size (16 KiB), so a chunk
    /// from Run trims at most once before the end-of-feed trim.
    internal static let trimSlack = 16_384
    /// The longest escape or control sequence, ESC included, before it is abandoned (ho-01.1).
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

    /// The committed lines retained, oldest first.
    public private(set) var lines: [Line] = []
    private var committedBytes = 0
    private var state = State.ground
    /// The parameter and intermediate bytes of the control sequence being read.
    private var sequence: [UInt8] = []
    private var sequenceLength = 0
    private var style = Style()
    /// The line in progress, whole characters, and the style of each of its bytes.
    private var bytes: [UInt8] = []
    private var styles: [Style] = []
    /// The style every byte of the line in progress has, or nil once two have differed; it spares
    /// the comparison of every byte when the line is reported on each feed.
    private var shared: Style?
    /// The byte offset of the column the next character takes.
    private var cursor = 0

    /// An empty transcript in the default style.
    public init() {
        // Public: the memberwise initializer of a public struct is internal.
    }

    /// The bytes held across the committed lines and the line in progress.
    public var retainedBytes: Int { committedBytes + bytes.count }

    /// Reads `input` and returns what changed since the last feed.
    public mutating func feed(_ input: [UInt8]) -> Change {
        let reported = lines.count
        for byte in input {
            step(byte)
        }
        dropOldestColumns()
        var dropped = 0
        while dropped < lines.count, lines.count - dropped > Self.lineLimit || retainedBytes > Self.byteLimit {
            committedBytes -= lines[dropped].byteCount
            dropped += 1
        }
        lines.removeFirst(dropped)
        let evicted = min(dropped, reported)
        return Change(
            evicted: evicted,
            committed: Array(lines[(reported - evicted)...]),
            inProgress: Self.line(bytes, styles, shared: shared))
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
            cursor = 0
        case 0x0A:
            commit()
        case 0x80...0xBF where cursor > 0:
            bytes.insert(byte, at: cursor)
            styles.insert(styles[cursor - 1], at: cursor)
            cursor += 1
            dropOldestColumns(beyond: Self.trimSlack)
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
        } else if state == .controlStringEscape {
            // After an ESC inside the string a backslash ends it; any other byte is more of the string.
            state = byte == UInt8(ascii: "\\") ? .ground : .controlString
        } else if byte == Self.bell {
            state = .ground
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
        dropOldestColumns(beyond: Self.trimSlack)
    }

    private mutating func commit() {
        dropOldestColumns()
        let line = Self.line(bytes, styles, shared: shared)
        lines.append(line)
        committedBytes += line.byteCount
        bytes.removeAll()
        styles.removeAll()
        cursor = 0
    }

    /// The cap on the line in progress: once it is more than `slack` bytes over, its oldest characters
    /// go, whole, until it fits.
    private mutating func dropOldestColumns(beyond slack: Int = 0) {
        guard bytes.count > Self.lineByteLimit + slack else { return }
        var drop = bytes.count - Self.lineByteLimit
        while drop < bytes.count, Self.isContinuation(bytes[drop]) {
            drop += 1
        }
        bytes.removeFirst(drop)
        styles.removeFirst(drop)
        cursor = max(cursor - drop, 0)
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        byte & 0xC0 == 0x80
    }

    private static func line(_ bytes: [UInt8], _ styles: [Style], shared: Style?) -> Line {
        var spans: [Span] = []
        var start = 0
        while start < bytes.count {
            var end = shared == nil ? start + 1 : bytes.count
            while end < bytes.count, styles[end] == styles[start] {
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
