import AppKit
import SwiftUI

/// The terminal row's pop-up: Terminal.app, the other known terminals installed, the stored one when it is
/// neither, then Other….
///
/// An AppKit pop-up, where SwiftUI's picker builds its list once with the view: the list is read from
/// Launch Services each time the pop-up is about to open and each time the window becomes key, so a
/// terminal installed while the window stood open is offered (ho-05.1 Decision 15). Nothing is cached.
internal struct TerminalPopUp: NSViewRepresentable {
    /// The stored bundle identifier, read in the form's body so a change redraws the row.
    let selected: String
    /// A terminal picked, by bundle identifier, or nil for Other….
    let choose: @MainActor (String?) -> Void

    func makeNSView(context: Context) -> TerminalPopUpButton {
        TerminalPopUpButton(selected: selected, choose: choose)
    }

    func updateNSView(_ view: TerminalPopUpButton, context: Context) {
        view.selected = selected
        view.choose = choose
        view.readList()
    }
}

internal final class TerminalPopUpButton: NSPopUpButton, NSMenuDelegate {
    var selected: String
    var choose: @MainActor (String?) -> Void

    init(selected: String, choose: @escaping @MainActor (String?) -> Void) {
        self.selected = selected
        self.choose = choose
        super.init(frame: .zero, pullsDown: false)
        menu?.delegate = self
        target = self
        action = #selector(picked)
        readList()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        readList()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
    }

    /// The list as Launch Services gives it now, with the stored terminal selected.
    func readList() {
        let installed = Terminals.installed()
        let identifiers = installed.contains(selected) ? installed : installed + [selected]
        removeAllItems()
        for identifier in identifiers {
            let item = NSMenuItem(title: Terminals.name(of: identifier), action: nil, keyEquivalent: "")
            item.representedObject = identifier
            menu?.addItem(item)
        }
        menu?.addItem(.separator())
        menu?.addItem(NSMenuItem(title: "Other…", action: nil, keyEquivalent: ""))
        selectItem(at: identifiers.firstIndex(of: selected) ?? 0)
    }

    @objc
    private func windowBecameKey() {
        readList()
    }

    @objc
    private func picked() {
        let identifier = selectedItem?.representedObject as? String
        choose(identifier)
        if let identifier { selected = identifier }
        // Other… cancelled leaves the stored terminal; the pop-up shows it again rather than "Other…".
        readList()
    }
}
