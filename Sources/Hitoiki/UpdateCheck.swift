import Foundation

/// The update check (ho-06.1 Decisions 4, 5, 6 and 15): one GET to GitHub's latest release for Hitoiki, at
/// launch and every 24 hours while the switch is on, and whenever Check for Updates asks.
///
/// The check is the app's only network request. It sends the app's name and version and nothing about the
/// user; the fetch is handed in, so a test hands a stand-in and nothing reaches GitHub. Nothing is persisted:
/// the last-checked time and what was found live in memory until the app quits.
@MainActor
internal final class UpdateCheck {
    /// What a manual check ends in, one of three (Decision 6).
    internal enum Answer: Equatable, Sendable {
        case upToDate
        /// A newer release, by the version its tag gives without the `v`.
        case available(String)
        /// No network, an error from GitHub, or a reply that is not a release.
        case failed

        /// The answer line's words.
        internal var text: String {
            switch self {
            case .upToDate:
                "Hitoiki is up to date."
            case .available(let version):
                "Hitoiki \(version) is available."
            case .failed:
                "Couldn't check for updates."
            }
        }
    }

    /// Sends a request and returns the reply: the shared memory-only session in the app, a stand-in in a test.
    internal typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// GitHub's latest-release endpoint for the Hitoiki repository.
    nonisolated internal static let github = URL(
        string: "https://api.github.com/repos/sageframe-no-kaji/hitoiki/releases/latest")
    /// Where the update line and the answer line send the user: the site carries the download and what changed.
    nonisolated internal static let site = URL(string: "https://hitoiki.sageframe.net")
    /// The automatic check's period, timed from launch.
    nonisolated internal static let interval: TimeInterval = 24 * 60 * 60

    /// A memory-only session: no cookie is kept and no reply is cached, on disk or in memory.
    nonisolated internal static let session = URLSession(configuration: configuration())

    /// The app's fetch: the request through `session`.
    nonisolated internal static let send: Fetch = { request in try await session.data(for: request) }

    /// The running version, or nil in a build from source, which has no Info.plist and so never checks.
    internal let version: String?
    /// The newest release a check has found that is newer than the running version, without the `v`; once
    /// found, it stays until the app quits.
    internal private(set) var available: String?
    /// The last manual check's answer, until the settings window closes.
    internal private(set) var answer: Answer?
    /// True while a manual check is in flight.
    internal private(set) var checking = false
    /// When the last check that sent its request ended.
    ///
    /// Held here only; no key is written for it.
    internal private(set) var lastChecked: Date?
    /// The daily timer, from `begin`.
    internal private(set) var timer: Timer?

    private let enabled: @MainActor () -> Bool
    private let endpoint: URL?
    private let fetch: Fetch
    private var observers: [@MainActor (UpdateCheck) -> Void] = []

    /// A check for `version` that reads `enabled` at each automatic moment and sends through `fetch`.
    ///
    /// - Parameters:
    ///   - version: The running version; nil sends nothing, for either kind of check.
    ///   - enabled: The switch, read when an automatic check is due.
    ///   - endpoint: Where the request goes: GitHub in the app, a loopback listener in one test.
    ///   - fetch: What sends the request.
    internal init(
        version: String?,
        enabled: @escaping @MainActor () -> Bool,
        endpoint: URL? = UpdateCheck.github,
        fetch: @escaping Fetch
    ) {
        self.version = version
        self.enabled = enabled
        self.endpoint = endpoint
        self.fetch = fetch
    }

    /// The short version in the bundle's Info.plist, or nil when it has none.
    internal static func runningVersion(in bundle: Bundle = .main) -> String? {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The request a check sends for `version`, exactly as Decisions 4 and 15 fix it.
    ///
    /// The networking library fills `Accept-Language` from the user's language list unless the request sets
    /// it, so it is set empty: the header goes, carrying no language (Decision 15).
    nonisolated internal static func request(version: String, to endpoint: URL) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Hitoiki/\(version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("", forHTTPHeaderField: "Accept-Language")
        return request
    }

    /// The memory-only session's configuration: ephemeral, and it takes, keeps and sends no cookie and caches
    /// no reply.
    nonisolated internal static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // A check that hangs holds Checking… on the button; palana's eight seconds bounds it.
        configuration.timeoutIntervalForRequest = 8
        return configuration
    }

    /// True when `tag` names a version newer than `running` (Decision 5).
    ///
    /// Each, less a leading `v`, must be one to three whole numbers joined by dots; they are compared number by
    /// number, a missing number counting as 0. Anything else is never newer.
    nonisolated internal static func isNewer(_ tag: String, than running: String) -> Bool {
        guard let new = numbers(tag), let current = numbers(running) else { return false }
        for (left, right) in zip(padded(new), padded(current)) where left != right {
            return left > right
        }
        return false
    }

    /// The update line's words for `version` (Decision 6).
    nonisolated internal static func notice(for version: String) -> String {
        "Hitoiki \(version) is available"
    }

    /// Calls `apply` now and after every change to what the check has found, its answer or its flight.
    internal func observe(_ apply: @escaping @MainActor (UpdateCheck) -> Void) {
        observers.append(apply)
        apply(self)
    }

    /// At launch: one automatic check now, and the timer that makes one every 24 hours from now.
    ///
    /// Returns the launch check's task, or nil when the switch is off or there is no version.
    @discardableResult
    internal func begin() -> Task<Void, Never>? {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            // The main run loop fires it, on the main thread.
            MainActor.assumeIsolated { _ = self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        return tick()
    }

    /// An automatic moment, at launch or from the timer: a check only if the switch is on now.
    ///
    /// Returns the check's task, or nil when nothing is sent.
    @discardableResult
    internal func tick() -> Task<Void, Never>? {
        guard enabled(), let version, let endpoint else { return nil }
        return Task { await check(Self.request(version: version, to: endpoint), manual: false) }
    }

    /// Check for Updates: a check whatever the switch says, ending in one of the three answers.
    ///
    /// While one is in flight, another does nothing. The automatic schedule does not move.
    internal func manual() async {
        guard !checking else { return }
        guard let version, let endpoint else {
            // A build with no version sends nothing; nothing was checked.
            answer = .failed
            return changed()
        }
        checking = true
        answer = nil
        changed()
        await check(Self.request(version: version, to: endpoint), manual: true)
        checking = false
        changed()
    }

    /// Empties the answer line: the settings window closed.
    internal func dismissAnswer() {
        answer = nil
        changed()
    }

    /// Sends `request` and takes the reply.
    ///
    /// An automatic failure shows nothing; a manual one is answered.
    private func check(_ request: URLRequest, manual: Bool) async {
        let tag = await latestTag(request)
        lastChecked = Date()
        guard let version, let tag else {
            if manual { answer = .failed }
            return changed()
        }
        if Self.isNewer(tag, than: version) {
            let found = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            available = found
            if manual { answer = .available(found) }
        } else if manual {
            answer = .upToDate
        }
        changed()
    }

    /// The release's tag, or nil on any failure: no reply, a status outside 2xx, or a body without a tag.
    private func latestTag(_ request: URLRequest) async -> String? {
        guard let (data, response) = try? await fetch(request) else { return nil }
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) { return nil }
        return (try? JSONDecoder().decode(Release.self, from: data))?.tagName
    }

    private func changed() {
        for observer in observers {
            observer(self)
        }
    }

    /// One to three whole numbers joined by dots, after a leading `v`; nil for any other form.
    nonisolated private static func numbers(_ text: String) -> [Int]? {
        let bare = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let fields = bare.split(separator: ".", omittingEmptySubsequences: false)
        let digits = fields.allSatisfy { field in !field.isEmpty && field.allSatisfy { ("0"..."9").contains($0) } }
        guard (1...3).contains(fields.count), digits else { return nil }
        let numbers = fields.compactMap { Int($0) }
        // A field too long for Int is not a version.
        return numbers.count == fields.count ? numbers : nil
    }

    nonisolated private static func padded(_ numbers: [Int]) -> [Int] {
        numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
}

/// The one field of GitHub's release reply the check reads.
private struct Release: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
