import Darwin
import Foundation
import Testing

@testable import Hitoiki

/// Stands in for the network: records every request handed to it and answers each with `reply`, sending
/// nothing anywhere.
///
/// Held, it keeps each request in flight until `release`.
@MainActor
internal final class FetchStandIn {
    /// Every request the check handed over, in order.
    internal private(set) var requests: [URLRequest] = []
    /// What each request gets back.
    internal var reply: Result<(Data, URLResponse), URLError>

    private var gate: AsyncStream<Void>?
    private var opener: AsyncStream<Void>.Continuation?

    /// A stand-in answering with a release whose tag is `tag`, or with GitHub's not-found body for nil.
    internal init(tag: String?) throws {
        reply = try .success((Self.body(tag: tag), Self.response()))
    }

    /// The fetch to hand the check.
    internal var fetch: UpdateCheck.Fetch {
        { request in try await self.take(request) }
    }

    /// GitHub's reply body: a release carrying `tag`, or, for nil, the body GitHub sends for a repository it
    /// does not show.
    internal static func body(tag: String?) throws -> Data {
        let object: [String: String] =
            tag.map { ["tag_name": $0, "name": "Hitoiki \($0)"] } ?? ["message": "Not Found"]
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// A reply with `status`, at GitHub's address.
    internal static func response(status: Int = 200) throws -> URLResponse {
        try #require(
            HTTPURLResponse(
                url: URL(fileURLWithPath: "/"), statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
    }

    /// From now on, each request waits until `release`.
    internal func hold() {
        (gate, opener) = AsyncStream<Void>.makeStream()
    }

    /// Lets every held request through.
    internal func release() {
        opener?.finish()
        gate = nil
    }

    private func take(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if let gate {
            for await _ in gate {}
        }
        return try reply.get()
    }
}

/// The switch an automatic check reads, as the test sets it.
@MainActor
private final class Switch {
    var on: Bool

    init(_ on: Bool) {
        self.on = on
    }
}

/// A listener on the loopback address, at a port the system chose, that answers one request.
///
/// The one test that sends a real check sends it here: nothing leaves the machine.
private struct Loopback {
    let descriptor: Int32
    let port: UInt16

    init() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        try #require(listener >= 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        // Port 0: the system chooses a free one, read back below.
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                bind(listener, address, length) == 0 && listen(listener, 1) == 0
                    && getsockname(listener, address, &length) == 0
            }
        }
        try #require(bound)
        descriptor = listener
        port = UInt16(bigEndian: address.sin_port)
    }

    /// Waits up to ten seconds for one connection, reads it to the end of its headers and a moment beyond,
    /// answers with `body`, and returns every byte that arrived; nil when nothing came.
    func answerOne(with body: String) async -> String? {
        let descriptor = descriptor
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: Self.serve(descriptor, body))
            }
        }
    }

    func close() {
        _ = Darwin.close(descriptor)
    }

    private static func serve(_ listener: Int32, _ body: String) -> String? {
        var waiting = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard poll(&waiting, 1, 10_000) == 1 else { return nil }
        let connection = accept(listener, nil, nil)
        guard connection >= 0 else { return nil }
        defer { _ = Darwin.close(connection) }
        var received: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4_096)
        var reading = pollfd(fd: connection, events: Int16(POLLIN), revents: 0)
        // Up to the blank line that ends the headers; then a quarter second more, so a body would be caught.
        func headersEnded() -> Bool { String(bytes: received, encoding: .utf8)?.contains("\r\n\r\n") == true }
        while poll(&reading, 1, headersEnded() ? 250 : 10_000) == 1 {
            let count = buffer.withUnsafeMutableBytes { read(connection, $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            received += buffer[0..<count]
        }
        let reply =
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + body
        _ = Array(reply.utf8).withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
        return String(bytes: received, encoding: .utf8)
    }
}

/// One case of the newer-version rule: a tag, the running version, and whether the tag is newer.
internal struct NewerCase: Sendable, CustomTestStringConvertible {
    let tag: String
    let running: String
    let newer: Bool

    var testDescription: String { "\"\(tag)\" over \(running): \(newer ? "newer" : "not newer")" }

    init(_ tag: String, _ running: String, _ newer: Bool) {
        self.tag = tag
        self.running = running
        self.newer = newer
    }
}

/// One reply to a manual check and what it must end in: the answer, and the version the update line then shows.
internal struct ReplyCase: Sendable, CustomTestStringConvertible {
    let tag: String?
    let status: Int
    let answer: UpdateCheck.Answer
    let available: String?

    var testDescription: String { "\(tag ?? "no tag"), status \(status)" }
}

/// The app's defaults domain without AppKit's own keys: the status item and window keys other suites' windows
/// write there are not the check's, nor the login item's.
internal func appDomainKeys() -> Set<String> {
    let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
    return Set(domain.keys.filter { !$0.hasPrefix("NS") && !$0.hasPrefix("Apple") })
}

// Serialized: the defaults-domain reading at the end is compared with the one at the start.
@Suite("Update check", .serialized)
@MainActor
internal struct UpdateCheckTests {
    @Test("The request for 1.2.3: GET to the exact URL, no body, no query, the two headers, an empty language")
    internal func request() {
        let github = UpdateCheck.github
        #expect(github.absoluteString == "https://api.github.com/repos/sageframe-no-kaji/hitoiki/releases/latest")
        let request = UpdateCheck.request(version: "1.2.3", to: github)
        #expect(request.httpMethod == "GET")
        #expect(request.url == github)
        #expect(request.url?.query == nil)
        #expect(request.httpBody == nil && request.httpBodyStream == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Hitoiki/1.2.3")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "Accept-Language")?.isEmpty == true)
        #expect(
            Set((request.allHTTPHeaderFields ?? [:]).keys) == ["User-Agent", "Accept", "Accept-Language"])
    }

    @Test("The session is memory-only: it keeps, takes and sends no cookie and caches no reply")
    internal func session() {
        for configuration in [UpdateCheck.configuration(), UpdateCheck.session.configuration] {
            #expect(configuration.httpCookieStorage == nil)
            #expect(configuration.httpCookieAcceptPolicy == .never)
            #expect(!configuration.httpShouldSetCookies)
            #expect(configuration.urlCache == nil)
            #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        }
    }

    // The networking library adds headers the built request does not show, so what arrives is read
    // (ho-06.1 Decision 15).
    @Test("A real check to a loopback listener: what arrives is one GET, the two headers and an empty language")
    internal func onTheWire() async throws {
        let loopback = try Loopback()
        defer { loopback.close() }
        let path = UpdateCheck.github.path
        let endpoint = try #require(URL(string: "http://127.0.0.1:\(loopback.port)\(path)"))
        let check = UpdateCheck(version: "1.2.3", enabled: { true }, endpoint: endpoint, fetch: UpdateCheck.send)
        async let heard = loopback.answerOne(with: #"{"tag_name":"v1.3"}"#)
        await check.manual()
        let arrived = try #require(await heard)
        print("ho-06.1 Decision 15, the request as it arrived:\n\(arrived)")

        let parts = arrived.components(separatedBy: "\r\n\r\n")
        let lines = parts[0].components(separatedBy: "\r\n")
        #expect(lines.first == "GET \(path) HTTP/1.1")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            headers[pair[0].lowercased()] = pair.count > 1 ? pair[1].trimmingCharacters(in: .whitespaces) : nil
        }
        #expect(headers["user-agent"] == "Hitoiki/1.2.3")
        #expect(headers["accept"] == "application/vnd.github+json")
        // Present and empty: the library's own value, the user's languages, is replaced by nothing.
        #expect(headers["accept-language"]?.isEmpty == true)
        #expect(headers["cookie"] == nil && headers["authorization"] == nil)
        #expect(headers["content-length"] == nil && headers["transfer-encoding"] == nil)
        #expect(parts.dropFirst().joined().isEmpty)
        // The reply was read: v1.3 is newer than 1.2.3.
        #expect(check.answer == .available("1.3"))
        #expect(check.available == "1.3")
    }

    @Test(
        "Newer: one to three whole numbers, less a leading v, compared number by number; any other tag is not",
        arguments: [
            NewerCase("v1.1", "1.0.0", true),
            NewerCase("1.1", "1.0.0", true),
            NewerCase("v1.0", "1.0.0", false),
            NewerCase("v1.0.0", "1.0.0", false),
            NewerCase("v0.9.9", "1.0.0", false),
            NewerCase("v1.0.1", "1.0.0", true),
            NewerCase("v2", "1.9.9", true),
            NewerCase("v1.10.0", "1.9.0", true),
            NewerCase("v1.0.0-beta", "0.1", false),
            NewerCase("latest", "0.1", false),
            NewerCase("", "0.1", false),
            NewerCase("v1.2.3.4", "0.1", false),
            NewerCase("v", "0.1", false),
            NewerCase("v1..2", "0.1", false),
            NewerCase("V2", "0.1", false),
            NewerCase("v99999999999999999999", "0.1", false),
        ])
    internal func newer(_ rule: NewerCase) {
        #expect(UpdateCheck.isNewer(rule.tag, than: rule.running) == rule.newer)
    }

    @Test("A running version outside the rule finds nothing newer")
    internal func runningOutsideTheRule() {
        #expect(!UpdateCheck.isNewer("v9", than: "1.0.0-dev"))
    }

    @Test("The switch: automatic off sends nothing, on sends once; manual sends with it off")
    internal func theSwitch() async throws {
        let stand = try FetchStandIn(tag: "v1.0.0")
        let toggle = Switch(false)
        let check = UpdateCheck(version: "1.0.0", enabled: { toggle.on }, fetch: stand.fetch)
        #expect(check.tick() == nil)
        #expect(stand.requests.isEmpty)
        toggle.on = true
        await check.tick()?.value
        #expect(stand.requests.count == 1)
        toggle.on = false
        await check.manual()
        #expect(stand.requests.count == 2)
    }

    @Test("Without a running version, neither kind of check sends anything")
    internal func noVersion() async throws {
        let stand = try FetchStandIn(tag: "v9")
        let check = UpdateCheck(version: nil, enabled: { true }, fetch: stand.fetch)
        #expect(check.begin() == nil)
        check.timer?.invalidate()
        #expect(check.tick() == nil)
        await check.manual()
        #expect(stand.requests.isEmpty)
        #expect(check.available == nil)
        // Still one of the three answers; nothing was checked.
        #expect(check.answer == .failed)
    }

    @Test("The running version is the Info.plist's short version; a bundle without one has none")
    internal func runningVersion() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "hitoiki-version-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let versioned = root.appending(path: "Versioned.app")
        let bare = root.appending(path: "Bare.app")
        for (bundle, plist) in [
            (versioned, ["CFBundleIdentifier": "test.versioned", "CFBundleShortVersionString": "1.0.0"]),
            (bare, ["CFBundleIdentifier": "test.bare"]),
        ] {
            let contents = bundle.appending(path: "Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appending(path: "Info.plist"))
        }
        #expect(UpdateCheck.runningVersion(in: try #require(Bundle(url: versioned))) == "1.0.0")
        #expect(UpdateCheck.runningVersion(in: try #require(Bundle(url: bare))) == nil)
    }

    @Test(
        "A manual check's answer, by reply",
        arguments: [
            ReplyCase(tag: "v1.0.0", status: 200, answer: .upToDate, available: nil),
            ReplyCase(tag: "v1.1", status: 200, answer: .available("1.1"), available: "1.1"),
            ReplyCase(tag: "1.1", status: 200, answer: .available("1.1"), available: "1.1"),
            ReplyCase(tag: "v0.9", status: 200, answer: .upToDate, available: nil),
            // A tag in another form gives no notice; the reply was a release, so the check did not fail.
            ReplyCase(tag: "v1.2-beta", status: 200, answer: .upToDate, available: nil),
            ReplyCase(tag: nil, status: 404, answer: .failed, available: nil),
            ReplyCase(tag: nil, status: 200, answer: .failed, available: nil),
            ReplyCase(tag: "v1.1", status: 500, answer: .failed, available: nil),
        ])
    internal func manualAnswer(_ reply: ReplyCase) async throws {
        let stand = try FetchStandIn(tag: reply.tag)
        stand.reply = try .success((FetchStandIn.body(tag: reply.tag), FetchStandIn.response(status: reply.status)))
        let check = UpdateCheck(version: "1.0.0", enabled: { false }, fetch: stand.fetch)
        await check.manual()
        #expect(stand.requests.count == 1)
        #expect(check.answer == reply.answer)
        #expect(check.available == reply.available)
        #expect(!check.checking)
        #expect(check.lastChecked != nil)
    }

    @Test("The three answers' words, the update line's, and the site the links open")
    internal func words() {
        #expect(UpdateCheck.Answer.upToDate.text == "Hitoiki is up to date.")
        #expect(UpdateCheck.Answer.available("1.1").text == "Hitoiki 1.1 is available.")
        #expect(UpdateCheck.Answer.failed.text == "Couldn't check for updates.")
        #expect(UpdateCheck.notice(for: "1.1") == "Hitoiki 1.1 is available")
        #expect(UpdateCheck.site.absoluteString == "https://hitoiki.sageframe.net")
        // The failed answer's link names the site by the same name.
        #expect(UpdateCheck.siteName == "hitoiki.sageframe.net")
    }

    @Test("A failed fetch: a manual check says so; an automatic one leaves no version and no answer")
    internal func failure() async throws {
        let stand = try FetchStandIn(tag: "v2")
        stand.reply = .failure(URLError(.notConnectedToInternet))
        let check = UpdateCheck(version: "1.0.0", enabled: { true }, fetch: stand.fetch)
        await check.tick()?.value
        #expect(stand.requests.count == 1)
        #expect(check.available == nil)
        #expect(check.answer == nil)
        await check.manual()
        #expect(check.answer == .failed)
        #expect(check.available == nil)
    }

    @Test("An automatic check that finds a newer release sets the version and no answer; observers hear it")
    internal func automaticFinds() async throws {
        let stand = try FetchStandIn(tag: "v1.1")
        let check = UpdateCheck(version: "1.0.0", enabled: { true }, fetch: stand.fetch)
        var heard: [String?] = []
        check.observe { heard.append($0.available) }
        #expect(heard == [nil])
        await check.tick()?.value
        #expect(check.available == "1.1")
        #expect(check.answer == nil)
        #expect(heard.last == "1.1")
        // Found once, it stays: a later failure does not take it away.
        stand.reply = .failure(URLError(.timedOut))
        await check.tick()?.value
        #expect(check.available == "1.1")
    }

    @Test("While a manual check is in flight it is Checking…, and another does nothing; the answer then empties")
    internal func oneManualAtATime() async throws {
        let stand = try FetchStandIn(tag: "v1.0.0")
        stand.hold()
        let check = UpdateCheck(version: "1.0.0", enabled: { false }, fetch: stand.fetch)
        let first = Task { await check.manual() }
        try await until { stand.requests.count == 1 }
        #expect(check.checking)
        #expect(check.answer == nil)
        await check.manual()
        #expect(stand.requests.count == 1)
        stand.release()
        await first.value
        #expect(!check.checking)
        #expect(check.answer == .upToDate)
        check.dismissAnswer()
        #expect(check.answer == nil)
    }

    @Test("Launch makes one automatic check; a tick of the 24-hour timer one more; a manual check adds none")
    internal func schedule() async throws {
        let stand = try FetchStandIn(tag: "v1.0.0")
        let check = UpdateCheck(version: "1.0.0", enabled: { true }, fetch: stand.fetch)
        await check.begin()?.value
        let timer = try #require(check.timer)
        defer { timer.invalidate() }
        #expect(stand.requests.count == 1)
        #expect(timer.isValid)
        // 24 hours, in seconds.
        #expect(timer.timeInterval == 86_400)
        let due = timer.fireDate
        #expect(abs(due.timeIntervalSinceNow - 86_400) < 60)

        await check.manual()
        #expect(stand.requests.count == 2)
        // The manual check did not move the schedule.
        #expect(timer.fireDate == due)

        // The timer's own tick, driven directly: one more automatic check, and the schedule stands.
        timer.fire()
        try await until { stand.requests.count == 3 }
        #expect(check.timer === timer)
        #expect(timer.fireDate == due)
    }

    @Test("Nothing the check does writes a key: the switch's store holds only the switch, the app's domain no new key")
    internal func noNewKey() async throws {
        let before = appDomainKeys()
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        settings.updateCheckEnabled = true
        let stand = try FetchStandIn(tag: "v1.1")
        let check = UpdateCheck(version: "1.0.0", enabled: { settings.updateCheckEnabled }, fetch: stand.fetch)
        await check.begin()?.value
        check.timer?.fire()
        try await until { stand.requests.count == 2 }
        check.timer?.invalidate()
        await check.manual()
        check.dismissAnswer()
        #expect(check.available == "1.1")
        #expect(suite.keys == ["updateCheckEnabled"])
        #expect(appDomainKeys() == before)
    }
}
