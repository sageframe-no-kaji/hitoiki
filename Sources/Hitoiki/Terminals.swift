import AppKit

/// The terminals Open in Terminal can hand a folder to, found through Launch Services each time they are
/// listed: the lookup costs nothing worth caching.
@MainActor
internal enum Terminals {
    /// Terminal.app first, which every Mac has, then the terminals ho-03 Decision 12 detects.
    internal static let known = [
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "org.alacritty",
    ]

    /// The known terminals installed on this Mac, in the order of `known`.
    internal static func installed() -> [String] {
        known.filter { url(for: $0) != nil }
    }

    /// The application with `identifier`, or nil when none is installed.
    internal static func url(for identifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    /// The application's name as the Finder shows it; an identifier that resolves to nothing is shown as
    /// itself, marked not installed.
    internal static func name(of identifier: String) -> String {
        guard let url = url(for: identifier) else { return "\(identifier) (not installed)" }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// The bundle identifier of the application at `url`, for Other…; nil for anything that is not one.
    internal static func identifier(ofApplicationAt url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }
}
