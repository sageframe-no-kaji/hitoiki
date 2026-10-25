/// The last `capacity` lines, oldest dropped first (ho-01 Decision 6).
///
/// The stand-in for Transcript's ceiling; ho-04 sets the real number. A line is closed by
/// LF. The line in progress keeps at most `lineByteLimit` bytes, oldest dropped first
/// (Decision 6, amended), so a line that never ends cannot grow without bound.
struct LineRing {
    /// The most lines kept.
    let capacity: Int
    /// The most bytes kept of the line in progress.
    let lineByteLimit: Int
    private var lines: [[UInt8]] = []
    private var oldest = 0
    private var inProgress: [UInt8] = []

    /// Creates an empty ring holding at most `capacity` lines of at most `lineByteLimit` bytes.
    init(capacity: Int, lineByteLimit: Int) {
        self.capacity = capacity
        self.lineByteLimit = lineByteLimit
        lines.reserveCapacity(capacity)
    }

    /// The number of closed lines held.
    var count: Int { lines.count }

    /// Adds one closed line, dropping the oldest when full.
    mutating func append(line: [UInt8]) {
        if lines.count < capacity {
            lines.append(line)
        } else {
            lines[oldest] = line
            oldest = (oldest + 1) % capacity
        }
    }

    /// Adds raw bytes, closing a line at each LF.
    mutating func append(bytes: ArraySlice<UInt8>) {
        var start = bytes.startIndex
        while let newline = bytes[start...].firstIndex(of: 0x0A) {
            extendLineInProgress(bytes[start..<newline])
            append(line: inProgress)
            inProgress.removeAll(keepingCapacity: true)
            start = bytes.index(after: newline)
        }
        extendLineInProgress(bytes[start...])
    }

    // The one place the line in progress grows, and so the one place it is capped.
    private mutating func extendLineInProgress(_ bytes: ArraySlice<UInt8>) {
        inProgress.append(contentsOf: bytes)
        if inProgress.count > lineByteLimit {
            inProgress.removeFirst(inProgress.count - lineByteLimit)
        }
    }
}
