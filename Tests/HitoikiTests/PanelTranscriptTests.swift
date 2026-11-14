import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import HitoikiCore
import Testing

@testable import Hitoiki

/// The transcript's attribute `key` at the first character of `text`.
@MainActor
private func attribute(_ key: NSAttributedString.Key, of text: String, in transcript: TranscriptView) -> Any? {
    let location = (transcript.string as NSString).range(of: text).location
    guard location != NSNotFound else { return nil }
    return transcript.textStorage?.attribute(key, at: location, effectiveRange: nil)
}

// The transcript: what the model makes of real output, copying, and the two cards.
extension PanelTests {
    @Test("Colours reach the storage: red in the table's index 1, the rest in ink, no escape bytes")
    internal func colours() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("printf '\\033[31mred\\033[0m plain\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let transcript = fixture.window.transcript
        #expect(transcript.string == "red plain\n")
        #expect(same(attribute(.foregroundColor, of: "red", in: transcript) as? NSColor, Theme.transcriptColors[1]))
        #expect(same(attribute(.foregroundColor, of: "plain", in: transcript) as? NSColor, Theme.Token.ink))
    }

    @Test("Bold reaches the storage as the bold monospace font at the same size; the rest is regular")
    internal func bold() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("printf '\\033[1mbold\\033[22m plain\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let transcript = fixture.window.transcript
        #expect(transcript.string == "bold plain\n")
        let bold = try #require(attribute(.font, of: "bold", in: transcript) as? NSFont)
        let plain = try #require(attribute(.font, of: "plain", in: transcript) as? NSFont)
        #expect(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        #expect(bold.isFixedPitch)
        #expect(bold.pointSize == TranscriptView.font.pointSize)
        #expect(plain == TranscriptView.font)
    }

    @Test("A progress line rewrites itself in place")
    internal func progressLine() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("printf '1%%\\r2%%\\r3%%\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == "3%\n")
    }

    @Test("Copy: the whole transcript with no selection, only the selection with one; plain text only")
    internal func copy() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        fixture.panel.submit("printf '\\033[34mfirst\\033[0m line\\nsecond\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let transcript = fixture.window.transcript
        let pasteboard = NSPasteboard.general

        transcript.copy(nil)
        #expect(pasteboard.string(forType: .string) == "first line\nsecond\n")
        #expect(pasteboard.pasteboardItems?.map(\.types) == [[.string]])

        transcript.setSelectedRange(NSRange(location: 0, length: 5))
        transcript.copy(nil)
        #expect(pasteboard.string(forType: .string) == "first")
        #expect(pasteboard.pasteboardItems?.map(\.types) == [[.string]])

        transcript.setSelectedRange(NSRange(location: 0, length: 0))
        pasteboard.clearContents()
        fixture.window.copyButton.performClick(nil)
        #expect(pasteboard.string(forType: .string) == "first line\nsecond\n")
    }

    @Test("Clean is the bar alone; the output card shows from Running with Copy and goes at a clear")
    internal func layout() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        #expect(fixture.window.outputCard.isHidden)
        #expect(fixture.window.frame.height == fixture.window.bar.frame.height)
        // The bar's row: the input, then the gear at the trailing edge, centred top to bottom.
        let row = try #require(fixture.window.input.superview as? NSStackView)
        let gear = try #require(row.arrangedSubviews.last)
        #expect(gear.frame.maxX == row.bounds.maxX)
        #expect(abs(gear.frame.midY - row.bounds.midY) <= 0.5)
        let composingGear = gear.frame.maxX

        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(!fixture.window.outputCard.isHidden)
        #expect(!fixture.window.copyButton.isHidden)
        #expect(fixture.window.frame.height > fixture.window.bar.frame.height + fixture.window.outputCard.frame.height)
        #expect(fixture.window.input.currentEditor() == nil)
        #expect(gear.frame.maxX == composingGear)
        let input = fixture.window.input
        #expect(input.alignmentRect(forFrame: input.frame).maxX + row.spacing == gear.frame.minX)

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(!fixture.window.outputCard.isHidden)
        fixture.panel.escape()
        #expect(fixture.window.isVisible)
        #expect(fixture.window.outputCard.isHidden)
        #expect(fixture.window.transcript.string.isEmpty)
        #expect(fixture.window.frame.height == fixture.window.bar.frame.height)
    }

    @Test("The ceiling holds through the panel: 12,000 lines leave 10,000")
    internal func ceiling() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("yes | head -n 12000")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let lines = fixture.window.transcript.string.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 10_001)
        #expect(lines.dropLast().allSatisfy { $0 == "y" })
        #expect(lines.last?.isEmpty == true)
    }

    @Test("Escape route: with no command running, Escape pressed in the transcript reaches the ladder — Done clears")
    internal func escapeInTranscript() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let window = fixture.window
        #expect(window.makeFirstResponder(window.transcript))
        window.transcript.keyDown(with: try key("\u{1B}", code: UInt16(kVK_Escape), in: window))
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
    }

    @Test("With no command running, a character pressed in the transcript types into the input; Return submits it")
    internal func typingInTranscript() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let window = fixture.window
        #expect(window.makeFirstResponder(window.transcript))
        window.transcript.keyDown(with: try key("a", code: 0, in: window))
        #expect(window.input.stringValue == "a")
        #expect(window.input.currentEditor() != nil)
        #expect(window.isVisible)

        window.input.stringValue = "echo again"
        #expect(window.makeFirstResponder(window.transcript))
        window.transcript.keyDown(with: try key("\r", code: 36, in: window))
        try await fixture.transcriptContains("again")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == "again\n")
    }

    @Test("Command-C with the input focused copies the transcript, unless text is selected in the input")
    internal func commandC() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        fixture.panel.show()
        fixture.panel.submit("printf 'first line\\nsecond\\n'")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let window = fixture.window
        let pasteboard = NSPasteboard.general
        let editor = try #require(window.input.currentEditor())
        #expect(window.firstResponder === editor)

        pasteboard.clearContents()
        #expect(window.performKeyEquivalent(with: try key("c", code: 8, modifiers: .command, in: window)))
        #expect(pasteboard.string(forType: .string) == "first line\nsecond\n")

        window.input.stringValue = "typed text"
        editor.selectedRange = NSRange(location: 0, length: 5)
        pasteboard.clearContents()
        #expect(window.performKeyEquivalent(with: try key("c", code: 8, modifiers: .command, in: window)))
        #expect(pasteboard.string(forType: .string) == "typed")
    }

    @Test("The rows a command is told are the same in Composing as at Running")
    internal func terminalRows() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        #expect(fixture.window.outputCard.isHidden)
        let composing = fixture.window.terminalSize.rows
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(!fixture.window.outputCard.isHidden)
        #expect(fixture.window.terminalSize.rows == composing)
        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
    }

    @Test("The transcript enters its scroll view at the clip view's width, and a line wider than the panel wraps")
    internal func longLineWraps() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        // Before any layout the clip view already has the transcript's width: the transcript's width mask
        // becomes a constraint against it, and one made against a clip view with no width kept the
        // transcript that much wider than the clip in the running app.
        let bare = PanelWindow()
        let bareClip = try #require(bare.transcript.enclosingScrollView?.contentView)
        #expect(bareClip.bounds.width > 0)
        #expect(bareClip.bounds.width == bare.transcript.frame.width)
        fixture.panel.show()
        fixture.panel.submit("printf '%0.s-' $(seq 1 120); echo")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let transcript = fixture.window.transcript
        #expect(transcript.string == String(repeating: "-", count: 120) + "\n")
        let clip = try #require(transcript.enclosingScrollView?.contentView)
        #expect(transcript.frame.width == clip.bounds.width)
        let layout = try #require(transcript.layoutManager)
        var fragments = 0
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: 120)) { _, _, _, _, _ in
            fragments += 1
        }
        #expect(fragments == 2)
    }

    @Test("After Stop nothing more is drawn; Done arrives within seconds; the next command draws again")
    internal func nothingDrawnAfterStop() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("yes | head -n 2000000")
        _ = try await fixture.running()
        let transcript = fixture.window.transcript
        try await fixture.until { transcript.string.count > 10_000 }
        let drawn = transcript.string
        let clock = ContinuousClock()
        let asked = clock.now
        fixture.panel.stop()
        guard case .done = try await fixture.done() else {
            Issue.record("not Done: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(clock.now - asked < .seconds(5))
        #expect(transcript.string == drawn)

        fixture.panel.submit("echo again")
        try await fixture.transcriptContains("again")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(transcript.string == "again\n")
    }

    @Test("The transcript follows the end only when the end was in view")
    internal func scrollFollowsEnd() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let transcript = fixture.window.transcript
        transcript.append(Array((1...300).map { "row \($0)\n" }.joined().utf8))
        fixture.window.fit()
        #expect(transcript.atCap)
        #expect(transcript.bounds.height > transcript.visibleRect.height)

        transcript.scroll(.zero)
        let top = transcript.visibleRect
        #expect(top.minY == 0)
        transcript.append(Array("more\n".utf8))
        #expect(transcript.visibleRect == top)

        transcript.scrollToEndOfDocument(nil)
        transcript.append(Array("last\n".utf8))
        #expect(transcript.visibleRect.maxY == transcript.bounds.maxY)
        #expect(transcript.visibleRect.minY > 0)

        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
    }

    @Test("Command-C through the window while Running copies the transcript so far")
    internal func commandCWhileRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        guard case .running = fixture.panel.state else {
            Issue.record("not Running at the readiness point: \(String(describing: fixture.panel.state))")
            return
        }
        let window = fixture.window
        #expect(window.firstResponder === window.transcript)
        NSPasteboard.general.clearContents()
        #expect(window.performKeyEquivalent(with: try key("c", code: 8, modifiers: .command, in: window)))
        #expect(NSPasteboard.general.string(forType: .string) == "ready\n")

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
    }

    @Test("A selection the line ceiling evicts through keeps exactly its surviving lines, and copies exactly them")
    internal func selectionAcrossEviction() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        let transcript = fixture.window.transcript
        transcript.append(Array((0..<10_000).map { "line \($0)\n" }.joined().utf8))
        let text = transcript.string as NSString
        let from = text.range(of: "line 5990\n").location
        let through = NSMaxRange(text.range(of: "line 6009\n"))
        transcript.setSelectedRange(NSRange(location: from, length: through - from))

        transcript.append(Array((10_000..<16_000).map { "line \($0)\n" }.joined().utf8))
        #expect(transcript.string.hasPrefix("line 6000\n"))
        // Lines 6000 to 6009 survive, now first in the storage, and the selection is exactly them.
        let surviving = (6_000...6_009).map { "line \($0)\n" }.joined()
        let expected = NSRange(location: 0, length: (surviving as NSString).length)
        #expect(transcript.selectedRanges.map(\.rangeValue) == [expected])
        NSPasteboard.general.clearContents()
        transcript.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == surviving)
    }
}
