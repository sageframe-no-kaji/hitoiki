import Darwin
import Foundation

/// The commands run: the session's own memory always, and the history file while history is on (ho-05.2).
///
/// The file is `history.txt` in the folder handed in at init, one command per line. It is written only by
/// `record`, which Panel calls when Run reports Running for a submission, and read again at every recall:
/// nothing read from it is kept, so a line deleted in a text editor is gone from the next keystroke's
/// recall (Decision 3). Nothing here touches user defaults; the switch is read through `enabled` at use.
@MainActor
internal final class History {
    /// The most lines the file holds after a write, and the most commands session memory holds (Decision 4).
    internal static let ceiling = 5_000

    /// Named once, so every read, append, rewrite and delete aims at this one file and at no other in the
    /// folder (invariant 4).
    internal let file: URL

    /// Where a notice line goes: the panel's notice, each line once.
    ///
    /// A repeat of a line already given adds nothing.
    internal var report: (@MainActor (String) -> Void)?

    private let folder: URL
    private let enabled: @MainActor () -> Bool
    /// The commands run since launch, oldest first.
    private var session: [String] = []
    /// The notice lines already given.
    private var noted: Set<String> = []

    /// A history kept in `folder`, which is made at the first write; `enabled` is the history switch.
    internal init(folder: URL, enabled: @escaping @MainActor () -> Bool) {
        self.folder = folder
        self.enabled = enabled
        file = folder.appending(path: "history.txt", directoryHint: .notDirectory)
    }

    /// Entries: the session's commands newest first, then, with history on, the file's newest first, each
    /// command once, at its newest place (Decision 2).
    ///
    /// Two commands are the same when they match with leading and trailing whitespace ignored; an entry is
    /// the newest one's text exactly as it ran, so `cd My\ ` comes back with its escaped space (ho-05.2.1).
    /// The file is read now; a missing file is an empty one.
    internal var entries: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for command in session.reversed() + fileLines().reversed() {
            let same = command.trimmingCharacters(in: .whitespaces)
            guard !same.isEmpty, seen.insert(same).inserted else { continue }
            result.append(command)
        }
        return result
    }

    /// Keeps what ran: each line of `ran` that does not start with a space and is not blank, in session
    /// memory and, with history on, at the end of the file (Decisions 1 and 12).
    ///
    /// Panel calls it at Running, with the line it handed to Run, so the file is written when a command
    /// starts running and at no other moment. With history off the file is not created, opened or changed.
    internal func record(_ ran: String) {
        let lines = ran.split(whereSeparator: \.isNewline).map(String.init).filter(Self.kept)
        guard !lines.isEmpty else { return }
        session.append(contentsOf: lines)
        if session.count > Self.ceiling { session.removeFirst(session.count - Self.ceiling) }
        guard enabled() else { return }
        do {
            try append(lines)
            try trim()
        } catch {
            notice("History not saved: " + Self.reason(error))
        }
    }

    /// The list's rows for `filter`: the entries that contain it anywhere, upper and lower case alike, or
    /// every entry when it is empty (Decision 7).
    internal func matches(_ filter: String) -> [String] {
        let all = entries
        guard !filter.isEmpty else { return all }
        return all.filter { $0.range(of: filter, options: .caseInsensitive) != nil }
    }

    /// The grey suggestion for `text`: the rest of the newest entry that starts with it exactly, case and all,
    /// and is longer; nil for empty text or when no entry does (Decision 8).
    internal func suggestion(for text: String) -> String? {
        guard !text.isEmpty, let entry = entries.first(where: { $0.count > text.count && $0.hasPrefix(text) })
        else { return nil }
        return String(entry.dropFirst(text.count))
    }

    /// Clear History: session memory is emptied and the file deleted, with history on or off; the folder and
    /// every setting stay (Decision 9).
    ///
    /// Nil when the file is gone afterwards. Otherwise the line the settings window shows under the button,
    /// "History not cleared: <reason>" (ho-05.2.1): the file is still there and its commands still recalled,
    /// so Clear must not look done.
    internal func clear() -> String? {
        session.removeAll()
        do {
            try FileManager.default.removeItem(at: file)
        } catch CocoaError.fileNoSuchFile {
            // A file already gone is what Clear wants.
        } catch {
            return "History not cleared: " + Self.reason(error)
        }
        return nil
    }

    /// The space rule (Decision 12) and the blank rule (Decision 1): a line kept is neither.
    private static func kept(_ line: String) -> Bool {
        !line.hasPrefix(" ") && !line.allSatisfy(\.isWhitespace)
    }

    /// The plain words for `error`: the system's message for its POSIX code where there is one.
    private static func reason(_ error: any Error) -> String {
        let error = error as NSError
        let posix = error.domain == NSPOSIXErrorDomain ? error : error.userInfo[NSUnderlyingErrorKey] as? NSError
        guard let posix, posix.domain == NSPOSIXErrorDomain else { return error.localizedDescription }
        return String(cString: strerror(Int32(posix.code)))
    }

    /// The file's lines with history on; none with it off, when it is missing, or when it cannot be read,
    /// which is said once on the notice.
    private func fileLines() -> [String] {
        guard enabled() else { return [] }
        do {
            let data = try Data(contentsOf: file)
            // Lossy on purpose: a byte that is not UTF-8, from a hand edit, spoils its own line, not the file.
            // swiftlint:disable:next optional_data_string_conversion
            return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            notice("History could not be read: " + Self.reason(error))
            return []
        }
    }

    /// Appends `lines`, each ending in a newline, making the folder (0700) and the file (0600) if they are
    /// absent; a file that does not end in a newline, edited by hand, gets one first.
    private func append(_ lines: [String]) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // O_CREAT's mode applies only when the file is made: an existing file's permissions are left alone.
        let descriptor = open(file.path, O_RDWR | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var text = lines.map { $0 + "\n" }.joined()
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data("\n".utf8) { text = "\n" + text }
        }
        // O_APPEND: the write lands at the end wherever the read left the offset.
        try handle.write(contentsOf: Data(text.utf8))
    }

    /// Past the ceiling, the newest lines replace the file in one step, so a crash never leaves half a file;
    /// the file keeps the permissions it had.
    private func trim() throws {
        let data = try Data(contentsOf: file)
        let breaks = data.indices.filter { data[$0] == UInt8(ascii: "\n") }
        guard breaks.count > Self.ceiling else { return }
        let keptFrom = breaks[breaks.count - Self.ceiling - 1] + 1
        let manager = FileManager.default
        let permissions = try manager.attributesOfItem(atPath: file.path)[.posixPermissions]
        try data[keptFrom...].write(to: file, options: .atomic)
        if let permissions { try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path) }
    }

    /// Gives `line` to the notice the first time it is said.
    private func notice(_ line: String) {
        guard noted.insert(line).inserted else { return }
        report?(line)
    }
}
