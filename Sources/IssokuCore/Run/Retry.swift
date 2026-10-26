/// The `-tt` retry offer.
///
/// sudo refused for want of a terminal, so the same `ssh` line is offered again with a terminal
/// requested. This is the only transformation Run ever makes to a typed line.
public enum Retry {
    /// The clause sudo prints when it has no terminal to read a password from.
    ///
    /// Only this clause: the text after it has changed across sudo releases.
    static let clause = Array("sudo: a terminal is required to read the password".utf8)

    /// The line to relaunch, or nil unless all four guards hold.
    ///
    /// The guards: the exit is not `.status(0)`; sudo's clause appeared; the line, with leading
    /// whitespace dropped, begins with the four bytes `ssh `; and no word after `ssh` already
    /// carries `-t` (a word beginning with `-` whose letters, up to the first non-letter, include
    /// `t`). The offer inserts `-tt ` after the leading `ssh ` and leaves the rest byte for byte.
    public static func offer(line: String, exit: Exit, sawSudoRefusal: Bool) -> String? {
        let trimmed = line.drop { $0.isWhitespace }
        guard exit != .status(0), sawSudoRefusal, trimmed.utf8.starts(with: "ssh ".utf8) else { return nil }
        let rest = Substring(trimmed.utf8.dropFirst(4))
        let carriesTerminal = rest.split(whereSeparator: \.isWhitespace).contains { word in
            word.first == "-" && word.dropFirst().prefix { $0.isASCII && $0.isLetter }.contains("t")
        }
        return carriesTerminal ? nil : "ssh -tt " + rest
    }
}

/// Watches the streamed bytes for sudo's clause, across chunk boundaries.
struct RefusalScanner {
    /// Whether the clause has appeared in any chunk so far.
    private(set) var sawRefusal = false
    /// The last clause-length bytes of what has been scanned.
    private var tail: [UInt8] = []

    /// Scans the next chunk together with the end of the previous one.
    mutating func scan(_ chunk: [UInt8]) {
        guard !sawRefusal else { return }
        let length = Retry.clause.count
        sawRefusal = chunk.contains(Retry.clause) || (tail + chunk.prefix(length)).contains(Retry.clause)
        tail = Array((tail + chunk.suffix(length)).suffix(length))
    }
}
