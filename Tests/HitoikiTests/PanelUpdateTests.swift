import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import HitoikiCore
import Testing

@testable import Hitoiki

// The update line: shown in every state, opening the site, and changing nothing else on the panel.
extension PanelTests {
    @Test("A newer release shows the update line in Composing, Running and Done; state, input and transcript stay")
    internal func updateLine() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let window = fixture.window
        #expect(window.updateLine.isHidden)
        #expect(window.updateLine.isDescendant(of: window.bar))
        fixture.panel.show()

        // Composing, a line typed: the check finds v1.1, as the app hands it to the panel.
        let stand = try FetchStandIn(tag: "v1.1")
        let check = UpdateCheck(version: "1.0.0", enabled: { true }, fetch: stand.fetch)
        check.observe { fixture.panel.announce($0.available) }
        #expect(window.updateLine.isHidden)
        window.input.stringValue = "typed line"
        let composing = fixture.look()
        await check.tick()?.value
        #expect(!window.updateLine.isHidden)
        #expect(window.updateLine.title == "Hitoiki 1.1 is available")
        #expect(fixture.look() == composing)
        #expect(fixture.keyboardInInput)

        // Running: the command keeps reading and drawing.
        window.input.stringValue = ""
        fixture.panel.submit(Fixture.held)
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let running = fixture.look()
        fixture.panel.announce("1.2")
        #expect(!window.updateLine.isHidden)
        #expect(window.updateLine.title == "Hitoiki 1.2 is available")
        #expect(fixture.look() == running)
        #expect(window.firstResponder === window.transcript)
        try await fixture.alive("after")
        try await fixture.transcriptContains("got after")
        try await fixture.end {}

        // Done, from a clean panel, so the Done waited for is this command's.
        fixture.panel.escape()
        #expect(fixture.panel.state == nil)
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        let done = fixture.look()
        fixture.panel.announce("1.3")
        #expect(window.updateLine.title == "Hitoiki 1.3 is available")
        #expect(fixture.look() == done)
    }

    @Test("A click on the update line asks to open the site and opens nothing else; no version, no line")
    internal func updateLineOpensSite() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        var opened: [URL] = []
        fixture.panel.openURL = { opened.append($0) }
        fixture.panel.show()
        fixture.panel.announce(nil)
        #expect(fixture.window.updateLine.isHidden)
        fixture.panel.announce("1.1")
        let shown = fixture.look()
        // The line's own action, sent as a click sends it: `performClick` spins the run loop for its highlight,
        // and the test process ended there (ho-05.1).
        let line = fixture.window.updateLine
        #expect(line.sendAction(line.action, to: line.target))
        #expect(opened.map(\.absoluteString) == ["https://hitoiki.sageframe.net"])
        #expect(fixture.look().state == shown.state)
        #expect(fixture.look().input == shown.input)
        #expect(fixture.look().transcript == shown.transcript)
    }

    @Test("The notice lines show as before beside the update line")
    internal func updateLineBesideNotices() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.note("first notice")
        fixture.panel.announce("1.1")
        fixture.panel.note("second notice")
        #expect(!window.notice.isHidden)
        #expect(window.notice.stringValue == "first notice\nsecond notice")
        #expect(!window.updateLine.isHidden)
        #expect(window.updateLine.title == "Hitoiki 1.1 is available")
        // The update line is its own line, under the notice in the bar.
        window.contentView?.layoutSubtreeIfNeeded()
        let notice = window.notice.convert(window.notice.bounds, to: nil)
        let line = window.updateLine.convert(window.updateLine.bounds, to: nil)
        #expect(line.maxY <= notice.minY)
    }
}
