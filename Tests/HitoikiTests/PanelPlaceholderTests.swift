import AppKit
import Carbon.HIToolbox
import Foundation
import HitoikiCore
import Testing

@testable import Hitoiki

/// The input's placeholder, or the empty string when it has none.
@MainActor
private func placeholder(_ fixture: Fixture) -> String {
    fixture.window.input.placeholderString ?? ""
}

// The command stays visible: the input empties when a command starts, and the command shows as the input's
// placeholder through Running and Done, never part of its value (ho-06.3 Decision 9). In the Panel suite, one
// test at a time.
extension PanelTests {
    @Test("The command that started is the input's placeholder through Running and Done; the input itself is empty")
    internal func placeholderShowsCommand() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let window = fixture.window
        fixture.panel.show()
        #expect(placeholder(fixture).isEmpty)
        let line = "echo ready; read -r line; exit 3"
        window.input.stringValue = line
        fixture.panel.submit(line)
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(window.input.stringValue.isEmpty)
        #expect(placeholder(fixture) == line)

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        #expect(window.input.stringValue.isEmpty)
        #expect(placeholder(fixture) == line)
        #expect(fixture.keyboardInInput)
    }

    @Test("Hidden and shown again, the panel in Done keeps the placeholder with everything else")
    internal func placeholderSurvivesHide() async throws {
        let (fixture, _) = try await reach(.done)
        defer { fixture.tearDown() }
        let before = fixture.look()
        #expect(placeholder(fixture) == "echo shown; exit 3")
        fixture.clickOut()
        #expect(!fixture.window.isVisible)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(placeholder(fixture) == "echo shown; exit 3")
    }

    @Test("Return on the empty input under the placeholder runs nothing; typed text runs and becomes the placeholder")
    internal func placeholderNeverRuns() async throws {
        let (fixture, _) = try await reach(.done)
        defer { fixture.tearDown() }
        let window = fixture.window
        let before = fixture.look()
        #expect(before.input.isEmpty && !before.offer)
        let editor = try #require(window.input.currentEditor() as? NSTextView)
        editor.keyDown(with: try key("\r", code: UInt16(kVK_Return), in: window))
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.look() == before)
        #expect(fixture.history.entries == ["echo shown; exit 3"])
        #expect(placeholder(fixture) == "echo shown; exit 3")

        // Typing replaces it: what is typed is the input's value, and Return runs that and nothing else.
        editor.insertText("echo second", replacementRange: editor.selectedRange())
        #expect(window.input.stringValue == "echo second")
        editor.keyDown(with: try key("\r", code: UInt16(kVK_Return), in: window))
        try await fixture.transcriptContains("second")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.transcript.string == "second\n")
        #expect(fixture.history.entries == ["echo second", "echo shown; exit 3"])
        #expect(window.input.stringValue.isEmpty)
        #expect(placeholder(fixture) == "echo second")
    }

    @Test("The next command's placeholder replaces the last one's at its Running")
    internal func placeholderReplaced() async throws {
        let (fixture, _) = try await reach(.done)
        defer { fixture.tearDown() }
        #expect(placeholder(fixture) == "echo shown; exit 3")
        fixture.panel.submit(Fixture.held)
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(placeholder(fixture) == Fixture.held)
        fixture.panel.stop()
        fixture.panel.stop()
        _ = try await fixture.done()
        #expect(placeholder(fixture) == Fixture.held)
    }

    @Test("The -tt offer: Return on the empty input runs the offer, which then is the placeholder")
    internal func placeholderOfOffer() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        #expect(placeholder(fixture) == "ssh host 'sudo true'")

        let editor = try #require(window.input.currentEditor())
        editor.keyDown(with: try key("\r", code: UInt16(kVK_Return), in: window))
        _ = try await fixture.running()
        try await fixture.transcriptContains("ok")
        #expect(placeholder(fixture) == "ssh -tt host 'sudo true'")
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(placeholder(fixture) == "ssh -tt host 'sudo true'")
    }

    @Test("Escape's clear takes the placeholder with the result", arguments: [Rung.done, .doneTyped, .stopped])
    internal func placeholderCleared(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        let started = rung == .stopped ? Fixture.held : "echo shown; exit 3"
        #expect(placeholder(fixture) == started)
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(placeholder(fixture).isEmpty)
        // A killed command's Done lands on nothing: the placeholder does not come back.
        try await fixture.until { !fixture.panel.awaitsClearedDone }
        #expect(placeholder(fixture).isEmpty)
        // An empty line on the clean panel starts nothing.
        fixture.panel.submit("")
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.panel.state == nil)
        #expect(placeholder(fixture).isEmpty)
    }
}
