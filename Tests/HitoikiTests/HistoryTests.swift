// The History suite and the file watcher its rewrite test needs. Stopping the watcher's stream on every path
// took the file a few lines past the length rule (ho-06.2 Decision 9).
// swiftlint:disable file_length

import CoreServices
import Foundation
import Testing

@testable import Hitoiki

/// The history switch, flipped by the test.
@MainActor
private final class Switch {
    var on: Bool

    init(_ on: Bool) {
        self.on = on
    }
}

/// The notice lines a History gave, in order.
@MainActor
private final class Notices {
    var lines: [String] = []
}

/// A History over a folder in a directory the test owns and removes: no test here reaches the app's own
/// folder in Application Support.
@MainActor
private struct Place {
    let root: URL
    let folder: URL
    let file: URL
    let toggle: Switch
    let notices: Notices
    let history: History

    init(historyOn on: Bool = true) throws {
        let name = "hitoiki-history-tests-" + UUID().uuidString
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        folder = root.appending(path: "Hitoiki")
        file = folder.appending(path: "history.txt")
        let toggle = Switch(on)
        let notices = Notices()
        self.toggle = toggle
        self.notices = notices
        history = History(folder: folder) { toggle.on }
        history.report = { notices.lines.append($0) }
    }

    var fileExists: Bool { FileManager.default.fileExists(atPath: file.path) }

    func text() throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    /// The file's lines, its last newline not counted as a line.
    func lines() throws -> [String] {
        try text().split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    }

    /// Writes `text` as a text editor would, making the folder first if it is absent.
    func write(byHand text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func permissions(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    func setPermissions(_ mode: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    func tearDown() {
        // Permissions a test took away are given back, so everything it made can be removed.
        for url in [folder, file] {
            try? setPermissions(0o700, of: url)
        }
        try? FileManager.default.removeItem(at: root)
    }
}

/// `count` numbered lines, each ending in a newline: `line 1` to `line <count>`.
private func numbered(_ count: Int) -> String {
    (1...count).map { "line \($0)\n" }.joined()
}

// Writing: what is kept, in what order, and with what permissions.
@Suite("History")
@MainActor
internal struct HistoryTests {
    @Test("History on: three commands run, the file holds the three in order, each ending in a newline")
    internal func threeInOrder() throws {
        let place = try Place()
        defer { place.tearDown() }
        for line in ["echo one", "echo two", "echo three"] {
            place.history.record(line)
        }
        #expect(try place.text() == "echo one\necho two\necho three\n")
        #expect(place.notices.lines.isEmpty)
    }

    @Test("History off: commands run, and neither the file nor its folder is made; the session keeps them")
    internal func offWritesNothing() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        place.history.record("echo one")
        place.history.record("echo two")
        #expect(!FileManager.default.fileExists(atPath: place.folder.path))
        #expect(place.history.entries == ["echo two", "echo one"])
    }

    @Test("A submission of several lines writes each line that is not blank, in order")
    internal func multiLine() throws {
        let place = try Place()
        defer { place.tearDown() }
        place.history.record("echo a\necho b\n\n   \n\techo c && echo d; echo e\n")
        #expect(try place.lines() == ["echo a", "echo b", "\techo c && echo d; echo e"])
    }

    @Test("A line that starts with a space is kept nowhere; the lines beside it in its block are kept")
    internal func spaceRule() throws {
        for on in [true, false] {
            let place = try Place(historyOn: on)
            defer { place.tearDown() }
            place.history.record("echo before\n echo secret\necho after")
            place.history.record(" echo alone")
            #expect(place.history.entries == ["echo after", "echo before"])
            #expect(place.history.matches("secret").isEmpty)
            #expect(place.history.suggestion(for: "echo s") == nil)
            if on {
                #expect(try place.lines() == ["echo before", "echo after"])
            }
        }
    }

    @Test("A file that does not end in a newline, edited by hand, gets one before the next line")
    internal func finalNewline() throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: "echo old")
        place.history.record("echo new")
        #expect(try place.text() == "echo old\necho new\n")
    }

    @Test("The folder is made 0700 and the file 0600 when absent; a file that exists keeps its permissions")
    internal func permissions() throws {
        let place = try Place()
        defer { place.tearDown() }
        place.history.record("echo one")
        #expect(try place.permissions(of: place.folder) == 0o700)
        #expect(try place.permissions(of: place.file) == 0o600)

        try place.setPermissions(0o640, of: place.file)
        place.history.record("echo two")
        #expect(try place.permissions(of: place.file) == 0o640)
        #expect(try place.lines() == ["echo one", "echo two"])
    }
}

// The ceiling: the file and session memory keep the newest 5,000.
extension HistoryTests {
    @Test("A file of 5,000 lines and one write holds 5,000: the oldest gone, the new one last, permissions kept")
    internal func ceiling() throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: numbered(History.ceiling))
        try place.setPermissions(0o640, of: place.file)
        place.history.record("echo new")
        let lines = try place.lines()
        #expect(lines.count == 5_000)
        #expect(lines.first == "line 2")
        #expect(lines.dropLast().last == "line 5000")
        #expect(lines.last == "echo new")
        #expect(try place.permissions(of: place.file) == 0o640)
        #expect(try FileManager.default.contentsOfDirectory(atPath: place.folder.path) == ["history.txt"])
    }

    @Test("A file of 4,999 lines and one write holds 5,000, its first line unchanged")
    internal func underCeiling() throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: numbered(4_999))
        place.history.record("echo new")
        let lines = try place.lines()
        #expect(lines.count == 5_000)
        #expect(lines.first == "line 1")
        #expect(lines.last == "echo new")
    }

    @Test("A block that carries the file past the ceiling keeps the newest 5,000, the block's lines last")
    internal func blockPastCeiling() throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: numbered(4_999))
        place.history.record("echo a\necho b\necho c")
        let lines = try place.lines()
        #expect(lines.count == 5_000)
        #expect(lines.first == "line 3")
        #expect(Array(lines.suffix(3)) == ["echo a", "echo b", "echo c"])
    }

    @Test("Session memory past 5,000 commands drops its oldest")
    internal func sessionCeiling() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        for number in 1...5_001 {
            place.history.record("command \(number)")
        }
        let entries = place.history.entries
        #expect(entries.count == 5_000)
        #expect(entries.first == "command 5001")
        #expect(entries.last == "command 2")
        #expect(!entries.contains("command 1"))
    }

    @Test("The ceiling's rewrite leaves the history file alone in its folder; where its transient file went is printed")
    internal func rewriteLeavesOneFile() async throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: numbered(History.ceiling))
        let folder = Watcher.named(place.folder.path) + "/"
        let watcher = try Watcher(watching: NSTemporaryDirectory())
        // Stopped on every way out, a failed wait included: the stream must not outlive the watcher it calls.
        defer { _ = watcher.stop() }
        place.history.record("echo new")
        // A file made after the rewrite: once its event has arrived, every earlier event has.
        let marker = place.root.appending(path: "marker")
        try Data().write(to: marker)
        try await until { watcher.seen.contains(Watcher.named(marker.path)) }
        let seen = watcher.stop()

        let inFolder = Set(seen.filter { $0.hasPrefix(folder) }).sorted()
        let replacement = Set(seen.filter { $0.contains("/TemporaryItems/") }).sorted()
        print("ho-05.2 Discovery 2: paths in the history folder \(inFolder); in TemporaryItems \(replacement)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: place.folder.path) == ["history.txt"])
        // Every other name the rewrite wrote in the folder was transient: it is gone.
        for path in inFolder where path != folder + "history.txt" {
            #expect(!FileManager.default.fileExists(atPath: path))
        }
        #expect(try place.lines().count == 5_000)
    }
}

// Entries, each command once with the session's first, and reads, fresh from the file every time.
extension HistoryTests {
    @Test("Entries: the session's commands before the file's, newest first in each")
    internal func sessionBeforeFile() throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: "file one\nfile two\n")
        place.history.record("session one")
        place.history.record("session two")
        #expect(place.history.entries == ["session two", "session one", "file two", "file one"])
    }

    @Test("A command in the session and the file appears once, at its session place")
    internal func onceAtSessionPlace() throws {
        let place = try Place()
        defer { place.tearDown() }
        place.history.record("df -h")
        try place.write(byHand: "df -h\nuptime\nls\n")
        #expect(place.history.entries == ["df -h", "ls", "uptime"])
    }

    @Test("`df -h` and ` df -h ` are one command: whitespace at the ends is not compared")
    internal func endsIgnored() throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: " df -h \nuptime\ndf -h\t\n")
        place.history.record("df -h  ")
        // One entry for the three spellings, at its session place and as the session ran it (ho-05.2.1).
        #expect(place.history.entries == ["df -h  ", "uptime"])
    }

    @Test("History off: the session alone, though the file has lines")
    internal func offIsSessionAlone() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        try place.write(byHand: "file one\nfile two\n")
        place.history.record("session one")
        #expect(place.history.entries == ["session one"])
        #expect(try place.text() == "file one\nfile two\n")
    }

    @Test("Every read is fresh: a line removed from the file between two reads is gone from the second")
    internal func freshReads() throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: "echo a\necho b\necho c\n")
        #expect(place.history.entries == ["echo c", "echo b", "echo a"])
        try place.write(byHand: "echo a\necho c\n")
        #expect(place.history.entries == ["echo c", "echo a"])
        #expect(place.history.matches("b").isEmpty)
        #expect(place.history.suggestion(for: "echo ") == "c")
    }

    @Test("A missing file gives the session alone and no notice")
    internal func missingFile() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        place.history.record("echo session")
        place.toggle.on = true
        #expect(!place.fileExists)
        #expect(place.history.entries == ["echo session"])
        #expect(place.notices.lines.isEmpty)
    }

    @Test("A file that cannot be read gives the session alone and one notice line, however often it is read")
    internal func unreadableFile() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        place.history.record("echo session")
        try place.write(byHand: "echo file\n")
        try place.setPermissions(0, of: place.file)
        place.toggle.on = true
        #expect(place.history.entries == ["echo session"])
        #expect(place.history.matches("echo") == ["echo session"])
        #expect(place.history.suggestion(for: "echo f") == nil)
        #expect(place.notices.lines.count == 1)
        #expect(place.notices.lines.first?.hasPrefix("History could not be read: ") == true)
    }
}

// The filter and the suggestion; Clear; a write that fails.
extension HistoryTests {
    @Test("The filter: entries containing the text anywhere, either case, newest first; empty gives all; none")
    internal func filter() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        for line in ["ssh host-a uptime", "ping HOST-b", "ls"] {
            place.history.record(line)
        }
        #expect(place.history.matches("host") == ["ping HOST-b", "ssh host-a uptime"])
        #expect(place.history.matches("HoSt") == ["ping HOST-b", "ssh host-a uptime"])
        #expect(place.history.matches("a up") == ["ssh host-a uptime"])
        #expect(place.history.matches("") == ["ls", "ping HOST-b", "ssh host-a uptime"])
        #expect(place.history.matches("zzz").isEmpty)
    }

    @Test("The suggestion: the newest entry that starts with the text wins, and its rest is the suggestion")
    internal func suggestionNewest() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        for line in ["echo one", "echo two", "uptime"] {
            place.history.record(line)
        }
        #expect(place.history.suggestion(for: "echo ") == "two")
        #expect(place.history.suggestion(for: "echo o") == "ne")
        #expect(place.history.suggestion(for: "u") == "ptime")
    }

    @Test("The suggestion: case must match; an entry equal to the text gives none; empty text gives none")
    internal func suggestionNone() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        place.history.record("ssh host-a")
        #expect(place.history.suggestion(for: "SSH h") == nil)
        #expect(place.history.suggestion(for: "ssh host-a") == nil)
        #expect(place.history.suggestion(for: "") == nil)
        #expect(place.history.suggestion(for: "ping") == nil)
        // A shorter entry equal to the text does not stop a longer, older one.
        place.history.record("ssh")
        #expect(place.history.suggestion(for: "ssh") == " host-a")
    }

    @Test("Clear: the file is gone, entries are empty, and a command run afterwards is the only entry")
    internal func clear() throws {
        let place = try Place()
        defer { place.tearDown() }
        place.history.record("echo one")
        place.history.record("echo two")
        #expect(place.fileExists)
        #expect(place.history.clear() == nil)
        #expect(!place.fileExists)
        #expect(place.history.entries.isEmpty)
        #expect(place.history.suggestion(for: "echo") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: place.folder.path).isEmpty)
        place.history.record("echo three")
        #expect(place.history.entries == ["echo three"])
        #expect(try place.text() == "echo three\n")
    }

    @Test("Clear with history off deletes a file left from before, and forgets the session")
    internal func clearWhileOff() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        try place.write(byHand: "echo before\n")
        place.history.record("echo session")
        #expect(place.history.clear() == nil)
        #expect(!place.fileExists)
        #expect(place.history.entries.isEmpty)
    }

    @Test("A write that fails puts one notice line; the same failure again adds none; the session keeps the line")
    internal func writeFails() throws {
        let place = try Place()
        defer { place.tearDown() }
        try FileManager.default.createDirectory(at: place.folder, withIntermediateDirectories: true)
        try place.setPermissions(0o500, of: place.folder)
        place.history.record("echo one")
        #expect(place.notices.lines.count == 1)
        #expect(place.notices.lines.first?.hasPrefix("History not saved: ") == true)
        place.history.record("echo two")
        #expect(place.notices.lines.count == 1)
        #expect(!place.fileExists)
        #expect(place.history.entries == ["echo two", "echo one"])
    }
}

// A Clear that cannot delete the file says so; an entry is the text as it ran, so an escaped space survives;
// the history switch's two transitions (ho-05.2.1, review findings M1, N1 and N2).
extension HistoryTests {
    @Test("Clear with no file at all reports nothing: a file already gone is what Clear wants; nothing is made")
    internal func clearWithNoFile() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        place.history.record("echo session")
        place.toggle.on = true
        #expect(place.history.clear() == nil)
        #expect(place.history.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: place.folder.path))
        #expect(place.notices.lines.isEmpty)
    }

    @Test("Clear that cannot delete the file: its reason; the file as it was; the session gone; entries the file's")
    internal func clearFails() throws {
        let place = try Place()
        defer { place.tearDown() }
        place.history.record("echo filed")
        place.toggle.on = false
        place.history.record("echo session only")
        place.toggle.on = true
        let before = try Data(contentsOf: place.file)
        // A folder the user cannot write: the file in it cannot be deleted, and can still be read.
        try place.setPermissions(0o500, of: place.folder)
        let line = try #require(place.history.clear())
        let opening = "History not cleared: "
        #expect(line.hasPrefix(opening))
        #expect(line.count > opening.count)
        #expect(try Data(contentsOf: place.file) == before)
        #expect(place.history.entries == ["echo filed"])
    }

    @Test("A failed Clear, then one that succeeds: the second reports nothing; the file is gone, the folder stays")
    internal func clearFailsThenSucceeds() throws {
        let place = try Place()
        defer { place.tearDown() }
        place.history.record("echo one")
        try place.setPermissions(0o500, of: place.folder)
        #expect(place.history.clear() != nil)
        #expect(place.fileExists)
        try place.setPermissions(0o700, of: place.folder)
        #expect(place.history.clear() == nil)
        #expect(!place.fileExists)
        #expect(place.history.entries.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: place.folder.path).isEmpty)
    }

    @Test("A command ending in an escaped space recalls whole, from the session and, after a relaunch, the file")
    internal func escapedSpace() throws {
        let place = try Place()
        defer { place.tearDown() }
        let command = "cd My\\ "
        place.history.record(command)
        #expect(try place.lines() == [command])
        #expect(place.history.entries == [command])
        #expect(place.history.matches("my") == [command])
        // Taking the suggestion after the backslash loads the whole command: the escaped space comes too.
        #expect(place.history.suggestion(for: "cd My\\") == " ")
        let relaunched = History(folder: place.folder) { true }
        #expect(relaunched.entries == [command])
        #expect(relaunched.suggestion(for: "cd") == " My\\ ")
    }

    @Test("`df -h` run, then ` df -h ` put in the file by hand: one entry, in its newest spelling")
    internal func newestSpelling() throws {
        let place = try Place()
        defer { place.tearDown() }
        place.history.record("df -h")
        let ran = try place.text()
        try place.write(byHand: ran + " df -h \n")
        // The session comes before the file: its spelling is the newest.
        #expect(place.history.entries == ["df -h"])
        // A relaunch has no session: the file's last line is the newest, spelled as it stands.
        let relaunched = History(folder: place.folder) { true }
        #expect(relaunched.entries == [" df -h "])
        #expect(relaunched.matches("DF") == [" df -h "])
    }

    @Test("History turned on after commands ran: only later commands reach the file; earlier ones stay in the session")
    internal func turnedOn() throws {
        let place = try Place(historyOn: false)
        defer { place.tearDown() }
        place.history.record("echo early")
        place.toggle.on = true
        place.history.record("echo late")
        #expect(try place.lines() == ["echo late"])
        #expect(place.history.entries == ["echo late", "echo early"])
    }

    @Test("History turned off: the file stays byte for byte through later commands; recall is the session alone")
    internal func turnedOff() throws {
        let place = try Place()
        defer { place.tearDown() }
        try place.write(byHand: "echo from before\n")
        place.history.record("echo kept")
        let before = try Data(contentsOf: place.file)
        place.toggle.on = false
        place.history.record("echo after")
        place.history.record("echo b\necho c")
        #expect(try Data(contentsOf: place.file) == before)
        #expect(place.history.entries == ["echo c", "echo b", "echo after", "echo kept"])
    }
}

/// The paths the file system reports changed under one folder, gathered from FSEvents while it watches.
///
/// FSEvents names a path in the temporary folder by its real path, under `/private`; the watcher and the
/// test both name every path without it, so they compare like with like.
///
/// Unchecked Sendable: the stream's callback runs on `queue`, the test reads on the main actor, and `lock`
/// guards the paths between them.
private final class Watcher: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "hitoiki-history-tests-watcher")
    private var paths: [String] = []
    private var stream: FSEventStreamRef?

    init(watching root: String) throws {
        let real = try #require(realpath(root, nil))
        defer { free(real) }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil)
        let flags =
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        let made = FSEventStreamCreate(
            nil,
            { _, info, _, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()
                // With kFSEventStreamCreateFlagUseCFTypes the paths come as a CFArray of CFStrings.
                watcher.add(unsafeBitCast(paths, to: NSArray.self) as? [String] ?? [])
            },
            &context,
            [String(cString: real)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0,
            FSEventStreamCreateFlags(flags))
        let stream = try #require(made)
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        let started = FSEventStreamStart(stream)
        // A stream that did not start has queued no callback; it is released here, as the test cannot stop it.
        if !started {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        try #require(started)
    }

    var seen: [String] {
        lock.withLock { paths }
    }

    /// Stops watching and gives every path seen; a second call only gives the paths.
    ///
    /// The stream holds the watcher unretained, so a callback already on the queue runs to its end before this
    /// returns, while the caller still holds the watcher.
    func stop() -> [String] {
        if let stream {
            FSEventStreamFlushSync(stream)
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            queue.sync {}
        }
        return seen
    }

    private func add(_ more: [String]) {
        let named = more.map(Self.named)
        lock.withLock { paths.append(contentsOf: named) }
    }

    /// `path` without a leading `/private`, the name both FSEvents and the test can give.
    static func named(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }
}
