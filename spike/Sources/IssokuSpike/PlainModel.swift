/// The plain-text model of what Transcript will show (ho-01 Decision 8).
///
/// The minimal handling the System Design commits to, and nothing more:
/// - SGR sequences (`ESC [ … m`) pass through unchanged.
/// - Every other escape sequence is removed: other CSI finals, OSC, the DCS/SOS/PM/APC
///   strings, and single-character ESC sequences (with any intermediate bytes).
/// - CR rewinds the current line, so later bytes overwrite from column zero.
/// - LF commits the line.
///
/// Every other byte is a printed character. A UTF-8 continuation byte joins the character
/// before it, so a multi-byte character occupies one column. Other C0 controls (TAB, BS,
/// BEL) are not interpreted; they are kept as characters.
///
/// The current line keeps at most `lineByteLimit` bytes (Decision 6, amended). Past that,
/// its oldest columns are dropped, whole characters at a time, once per `feed` call.
///
/// Two more bounds keep the parser's own state finite (ho-01.1): an escape or control
/// sequence longer than `sequenceByteLimit` bytes is abandoned, its bytes dropped and the
/// parser back at ground; and SGR not yet attached to a character keeps at most
/// `pendingSGRByteLimit` bytes, oldest sequences dropped first.
struct PlainModel {
    private enum State {
        case ground
        case escape
        case escapeIntermediate
        case controlSequence
        case controlString
    }

    private static let escapeByte: UInt8 = 0x1B
    private static let carriageReturn: UInt8 = 0x0D
    private static let lineFeed: UInt8 = 0x0A
    private static let bell: UInt8 = 0x07

    /// The longest escape or control sequence, ESC included, before it is abandoned.
    static let sequenceByteLimit = 256
    /// The most bytes of SGR held while no character has arrived to carry them.
    static let pendingSGRByteLimit = 4_096

    /// The most bytes kept of the current line.
    let lineByteLimit: Int

    private var state = State.ground
    private var sequence: [UInt8] = []
    private var sequenceLength = 0
    private var columns: [[UInt8]] = []
    private var cursor = 0
    private var lineBytes = 0
    private var pendingSGR: [UInt8] = []

    /// Creates a model whose current line keeps at most `lineByteLimit` bytes.
    init(lineByteLimit: Int) {
        self.lineByteLimit = lineByteLimit
    }

    /// Feeds bytes from the master; `emit` receives each committed line, without its LF.
    mutating func feed(_ bytes: ArraySlice<UInt8>, emit: ([UInt8]) -> Void) {
        for byte in bytes {
            step(byte, emit: emit)
        }
        dropOldestColumnsOverLimit()
    }

    /// The line in progress, rendered exactly as `takeLine` would commit it now.
    ///
    /// Every column, then any SGR still waiting for a character. Reading it changes nothing.
    var lineInProgress: [UInt8] {
        columns.flatMap { $0 } + pendingSGR
    }

    /// The final partial line, if anything is on it.
    mutating func finish() -> [UInt8]? {
        guard !columns.isEmpty || !pendingSGR.isEmpty else { return nil }
        return takeLine()
    }

    private mutating func step(_ byte: UInt8, emit: ([UInt8]) -> Void) {
        if state != .ground {
            sequenceLength += 1
            // A sequence that never ends would otherwise hold the parser, and for CSI its bytes,
            // forever; past the bound it is treated as noise and the stream reads as text again.
            if sequenceLength > Self.sequenceByteLimit {
                sequence.removeAll()
                state = .ground
                return
            }
        }
        switch state {
        case .ground:
            ground(byte, emit: emit)
        case .escape:
            escape(byte, emit: emit)
        case .escapeIntermediate:
            if byte >= 0x30 && byte <= 0x7E {
                state = .ground
            } else if byte < 0x20 || byte > 0x2F {
                state = .ground
                ground(byte, emit: emit)
            }
        case .controlSequence:
            controlSequence(byte, emit: emit)
        case .controlString:
            if byte == Self.bell {
                state = .ground
            } else if byte == Self.escapeByte {
                // ESC \ is the string terminator; the backslash is then a single-character
                // escape and is removed with it.
                state = .escape
            }
        }
    }

    private mutating func ground(_ byte: UInt8, emit: ([UInt8]) -> Void) {
        switch byte {
        case Self.escapeByte:
            state = .escape
            sequenceLength = 1
        case Self.carriageReturn:
            cursor = 0
        case Self.lineFeed:
            emit(takeLine())
        case 0x80...0xBF where cursor > 0:
            columns[cursor - 1].append(byte)
            lineBytes += 1
        default:
            put(pendingSGR + [byte])
            pendingSGR.removeAll()
        }
    }

    private mutating func escape(_ byte: UInt8, emit: ([UInt8]) -> Void) {
        switch byte {
        case UInt8(ascii: "["):
            sequence = [Self.escapeByte, byte]
            state = .controlSequence
        case UInt8(ascii: "]"), UInt8(ascii: "P"), UInt8(ascii: "X"), UInt8(ascii: "^"), UInt8(ascii: "_"):
            state = .controlString
        case Self.escapeByte:
            // ESC ESC: the first is abandoned and a new sequence starts here.
            state = .escape
            sequenceLength = 1
        case 0x20...0x2F:
            state = .escapeIntermediate
        case 0x30...0x7E:
            state = .ground
        default:
            state = .ground
            ground(byte, emit: emit)
        }
    }

    private mutating func controlSequence(_ byte: UInt8, emit: ([UInt8]) -> Void) {
        switch byte {
        case 0x20...0x3F:
            sequence.append(byte)
        case 0x40...0x7E:
            sequence.append(byte)
            let isSGR = byte == UInt8(ascii: "m") && !sequence.dropLast().contains(where: { $0 >= 0x20 && $0 <= 0x2F })
            if isSGR {
                appendPendingSGR(sequence)
            }
            sequence.removeAll()
            state = .ground
        default:
            sequence.removeAll()
            state = .ground
            ground(byte, emit: emit)
        }
    }

    // SGR with no character after it (a run of colour changes, or a child that never prints)
    // would otherwise accumulate without limit. Whole sequences go, oldest first; every
    // sequence starts with ESC and holds no other, so the next ESC is the next boundary.
    private mutating func appendPendingSGR(_ sgr: [UInt8]) {
        pendingSGR.append(contentsOf: sgr)
        while pendingSGR.count > Self.pendingSGRByteLimit {
            if let next = pendingSGR.dropFirst().firstIndex(of: Self.escapeByte) {
                pendingSGR.removeFirst(next)
            } else {
                pendingSGR.removeAll()
            }
        }
    }

    private mutating func put(_ column: [UInt8]) {
        if cursor < columns.count {
            lineBytes -= columns[cursor].count
            columns[cursor] = column
        } else {
            columns.append(column)
        }
        lineBytes += column.count
        cursor += 1
    }

    // The cap: drop the oldest columns until the current line fits in `lineByteLimit`.
    private mutating func dropOldestColumnsOverLimit() {
        guard lineBytes > lineByteLimit else { return }
        var dropped = 0
        while lineBytes > lineByteLimit && dropped < columns.count {
            lineBytes -= columns[dropped].count
            dropped += 1
        }
        columns.removeFirst(dropped)
        cursor = max(cursor - dropped, 0)
    }

    private mutating func takeLine() -> [UInt8] {
        let line = lineInProgress
        columns.removeAll()
        pendingSGR.removeAll()
        cursor = 0
        lineBytes = 0
        return line
    }
}
