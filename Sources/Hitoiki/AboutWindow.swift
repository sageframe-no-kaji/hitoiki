import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The About window: palana's layout in the Theme's colours, one instance for the app's life, made by the
/// application at the first About Hitoiki.
///
/// OK, Return, Escape and the close button hide it; the next About Hitoiki brings back the same window.
@MainActor
internal final class AboutWindow: NSWindow {
    /// The window for the running version, or for a build from source when `version` is nil.
    internal init(version: String?) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        title = "About Hitoiki"
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = Theme.Token.ground.nsColor
        let host = NSHostingView(rootView: AboutView(version: version) { [weak self] in self?.performClose(nil) })
        contentView = host
        setContentSize(host.fittingSize)
        center()
    }

    /// Escape closes the window, whatever has the keyboard, as OK does.
    override internal func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard event.type == .keyDown, Int(event.keyCode) == kVK_Escape, modifiers.isEmpty else {
            return super.sendEvent(event)
        }
        performClose(nil)
    }
}

/// About's face, top to bottom: the icon, the name, the version, the maker's line, the three links, the note on
/// the update check, and OK.
private struct AboutView: View {
    let version: String?
    let close: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .padding(.top, 24)
            Text("Hitoiki 一息")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 14)
            Text(version.map { "Version \($0)" } ?? "Development build")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 4)
            // A localized key, not a plain string, so the markdown links are parsed and open in the browser.
            Text(
                LocalizedStringKey(
                    "Andrew Todd Marcus — [atmarcus.net](https://atmarcus.net) · "
                        + "[sageframe.net](https://sageframe.net). Lovingly made by hand, in collaboration with AI, "
                        + "using the [Ho process](https://hosystem.sageframe.net/).")
            )
            .font(.system(size: 12))
            .foregroundStyle(Theme.inkFaint)
            .tint(Theme.accent)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
            .padding(.top, 14)
            links
                .padding(.top, 18)
            Text(
                "Checks GitHub for a newer version when Hitoiki opens and once a day. You can turn this off in "
                    + "Settings."
            )
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkFaint)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            Button("OK", action: close)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 18)
                .padding(.bottom, 22)
        }
        .frame(width: 360)
        .background(Theme.ground)
    }

    /// Website · GitHub · Support; Website is the site the update line and the answer open.
    private var links: some View {
        HStack(spacing: 10) {
            Link("Website", destination: UpdateCheck.site)
            separator
            // FORCE: a fixed, well-formed URL, which `URL(string:)` always parses.
            // swift-format-ignore: NeverForceUnwrap
            Link("GitHub", destination: URL(string: "https://github.com/sageframe-no-kaji/hitoiki")!)
            separator
            // FORCE: a fixed, well-formed URL, which `URL(string:)` always parses.
            // swift-format-ignore: NeverForceUnwrap
            Link(destination: URL(string: "https://buymeacoffee.com/sageframe")!) {
                Label("Support", systemImage: "heart.fill")
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .tint(Theme.accent)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(Theme.inkFaint)
    }
}
