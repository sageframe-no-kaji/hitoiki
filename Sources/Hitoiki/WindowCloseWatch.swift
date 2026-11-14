import AppKit
import SwiftUI

/// Calls `closed` when the window holding the form closes, by its close button, Escape, or anything else.
///
/// The settings window is hidden on close, not released, so the form and its state live on through a close;
/// the window's own close notice is what marks one.
internal struct WindowCloseWatch: NSViewRepresentable {
    let closed: @MainActor () -> Void

    func makeNSView(context: Context) -> CloseWatchView {
        CloseWatchView(closed: closed)
    }

    func updateNSView(_ view: CloseWatchView, context: Context) {
        view.closed = closed
    }
}

internal final class CloseWatchView: NSView {
    var closed: @MainActor () -> Void

    init(closed: @escaping @MainActor () -> Void) {
        self.closed = closed
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
    }

    @objc
    private func windowWillClose() {
        closed()
    }
}
