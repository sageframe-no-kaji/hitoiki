// The Panel suite and the panel's lifecycle: its states, the Escape ladder over them, launch and quitting.
// One area in one file, which runs past the length rule rather than split the area (ho-06.2 Decision 11).
// swiftlint:disable file_length

import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import HitoikiCore
import Testing

@testable import Hitoiki

/// After an event that did nothing to a busy panel, the command is as it was: an In flight line still
/// starts; a live command still draws what it prints; a stopped one is still alive and still not drawn.
@MainActor
private func expectUntouched(_ rung: PanelTests.Rung, _ fixture: Fixture, opening open: () -> Void) async throws {
    switch rung {
    case .inFlight:
        #expect(fixture.panel.isBusy)
        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
    case .live:
        try await fixture.alive("after")
        try await fixture.transcriptContains("got after")
    case .stopped:
        let drawn = fixture.window.transcript.string
        try await fixture.alive("after")
        // At Done every chunk has been through the panel, the line's print among them.
        try await fixture.end(opening: open)
        #expect(fixture.window.transcript.string == drawn)
        return
    default:
        Issue.record("\(rung) is not busy")
    }
    try await fixture.end(opening: open)
}

// Serialized and on the main actor: Panel is main-actor bound, and two Runs spawning at once
// intermittently fail forkpty (ho-02 Reflect).
@Suite("Panel", .serialized)
@MainActor
internal struct PanelTests {
    @Test("Clean: not busy; show focuses the input; Escape hides; the hotkey shows and hides")
    internal func clean() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        #expect(fixture.panel.state == nil)
        #expect(!fixture.panel.isBusy)
        fixture.panel.show()
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        fixture.panel.escape()
        #expect(fixture.look() == Look.clean.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == .clean)
        fixture.panel.toggle()
        #expect(fixture.look() == Look.clean.hidden)
    }

    @Test("A command goes Running then Done; a failing status is shown in the alarm colour")
    internal func submit() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        // The read holds the command at its readiness point until Running has been asserted.
        fixture.panel.submit("echo ready; read -r line; exit 3")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        guard case .running = fixture.panel.state else {
            Issue.record("not Running at the readiness point: \(String(describing: fixture.panel.state))")
            return
        }
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        #expect(fixture.window.status.stringValue == "exit 3")
        #expect(same(fixture.window.status.textColor, Theme.Token.alarm))
    }

    @Test("An empty or blank line starts nothing", arguments: ["", "   "])
    internal func blankLine(line: String) async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit(line)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.panel.state == nil)
    }

    @Test("Running stays up through click-out and the hotkey; keys go to the transcript; Stop ends it and its group")
    internal func runningStaysUp() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("sleep 30")
        let pid = try await fixture.running()
        #expect(fixture.panel.isBusy)
        fixture.clickOut()
        #expect(fixture.window.isVisible)
        fixture.panel.toggle()
        fixture.panel.toggle()
        #expect(fixture.window.isVisible)
        #expect(fixture.window.isKeyWindow)
        #expect(fixture.window.input.currentEditor() == nil)
        #expect(fixture.window.firstResponder === fixture.window.transcript)
        #expect(!fixture.window.stopButton.isHidden)

        fixture.panel.stop()
        let ended = try await fixture.done()
        #expect(ended != .done(.status(0), retry: nil))
        #expect(try await survivors(ofGroup: pid).isEmpty)
        #expect(!fixture.panel.isBusy)
        #expect(fixture.window.stopButton.isHidden)
        fixture.clickOut()
        #expect(!fixture.window.isVisible)
    }

    @Test("Stop interrupts, a second Stop kills; the count starts again at Done")
    internal func stopTwice() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        // `echo ready` follows the trap, so the first Stop cannot arrive before it is set.
        fixture.panel.submit("sh -c 'trap \"\" INT; echo ready; sleep 300'")
        let pid = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.stop()
        try await Task.sleep(for: .milliseconds(500))
        #expect(try !ps(["-o", "pid=", "-g", "\(pid)"]).isEmpty)
        fixture.panel.stop()
        #expect(try await fixture.done() == .done(.signal(SIGKILL), retry: nil))
        #expect(try await survivors(ofGroup: pid).isEmpty)

        fixture.panel.submit("sleep 30")
        let next = try await fixture.running()
        fixture.panel.stop()
        let ended = try await fixture.done()
        #expect(ended != .done(.signal(SIGKILL), retry: nil))
        #expect(try await survivors(ofGroup: next).isEmpty)
    }

    @Test("Keystrokes reach the command and nothing typed is drawn")
    internal func keystrokes() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("stty -echo; echo ready; read -r secret; echo \"length ${#secret}\"")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.keystroke(.write(Array("hunter2".utf8)))
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        try await fixture.transcriptContains("length 7")
        #expect(!fixture.window.transcript.string.contains("hunter2"))
    }

    @Test("Paste writes the general pasteboard's string to the command")
    internal func paste() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let pasteboard = NSPasteboard.general
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        pasteboard.clearContents()
        pasteboard.setString("thirteen-long", forType: .string)

        fixture.panel.submit("echo ready; read -r line; echo \"length ${#line}\"")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.keystroke(.paste)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        try await fixture.transcriptContains("length 13")
    }

    @Test("The -tt offer: Retry is shown, an empty line takes it, and it clears at the next run")
    internal func offer() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()

        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        #expect(!fixture.window.retryButton.isHidden)
        #expect(fixture.window.status.stringValue.contains("ssh -tt host 'sudo true'"))

        fixture.panel.submit("")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ok")
        guard case .running = fixture.panel.state else {
            Issue.record("not Running at the readiness point: \(String(describing: fixture.panel.state))")
            return
        }
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.retryButton.isHidden)
    }

    @Test("A clear takes a showing offer with it; an empty line then starts nothing")
    internal func clearTakesOffer() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()
        fixture.panel.show()
        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        fixture.panel.escape()
        #expect(fixture.panel.state == nil)
        #expect(fixture.window.retryButton.isHidden)
        #expect(fixture.look() == .clean)
        fixture.panel.submit("")
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.panel.state == nil)
    }

    @Test("A clear then a hide: the next summons is Clean — no state, no transcript, no status, no buttons")
    internal func clearThenHide() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        try await fixture.transcriptContains("shown")
        #expect(!fixture.window.openButton.isHidden)

        fixture.panel.escape()
        #expect(fixture.window.isVisible)
        fixture.panel.escape()
        #expect(!fixture.window.isVisible)
        fixture.panel.toggle()
        #expect(fixture.look() == .clean)
        #expect(fixture.panel.state == nil)
        #expect(fixture.window.transcript.string.isEmpty)
        #expect(fixture.window.status.stringValue.isEmpty)
        #expect(fixture.window.retryButton.isHidden)
        #expect(fixture.window.openButton.isHidden)
    }

    @Test("The block cursor shows only while Running, not after a clear, and is never part of the transcript's text")
    internal func cursor() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        #expect(!fixture.window.transcript.showsCursor)
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(fixture.window.transcript.showsCursor)
        #expect(fixture.window.transcript.string == "ready\n")

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(!fixture.window.transcript.showsCursor)
        #expect(!fixture.window.transcript.string.contains("\u{2588}"))
        #expect(!fixture.window.transcript.string.contains("\u{FFFC}"))
        fixture.panel.escape()
        #expect(fixture.panel.state == nil)
        #expect(!fixture.window.transcript.showsCursor)
    }
}

// The launch task, output, failure and quitting: an extension, not a second suite, so these stay
// serialized with the rest of Panel's tests.
extension PanelTests {
    @Test("The first command waits for the launch task")
    internal func launchTaskAwaited() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.submit("echo ready; read -r line")
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.panel.state == nil)
        #expect(fixture.window.transcript.string.isEmpty)

        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        guard case .running = fixture.panel.state else {
            Issue.record("not Running at the readiness point: \(String(describing: fixture.panel.state))")
            return
        }
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
    }

    @Test("A submission in flight stays up through the launch wait and while it runs; at Done a click-out hides it")
    internal func inFlightStaysUp() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        await Task.yield()
        fixture.panel.escape()
        fixture.panel.toggle()
        #expect(fixture.window.isVisible)
        #expect(fixture.window.isKeyWindow)
        fixture.clickOut()
        #expect(fixture.window.isVisible)
        #expect(fixture.panel.isBusy)
        #expect(fixture.panel.state == nil)

        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(fixture.panel.isBusy)
        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
        #expect(!fixture.panel.isBusy)
        fixture.panel.toggle()
        fixture.clickOut()
        #expect(!fixture.window.isVisible)
    }

    @Test("A click-out or the hotkey after start but before Running arrives leaves the panel up (ho-03x, run 2)")
    internal func hideBeforeRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("sleep 30")
        await Task.yield()
        // Held, the main actor lets Run start the command without delivering Running.
        usleep(50_000)
        fixture.panel.toggle()
        #expect(fixture.window.isVisible)
        fixture.clickOut()
        #expect(fixture.window.isVisible)

        let pid = try await fixture.running()
        fixture.panel.stop()
        guard case .done(.signal, _) = try await fixture.done() else {
            Issue.record("not ended by a signal: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(try await survivors(ofGroup: pid).isEmpty)
        #expect(!fixture.panel.isBusy)
    }

    @Test("A second Return while the launch task is pending is ignored; one command runs")
    internal func oneSubmission() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.submit("touch \"$HOME/first\"; echo ready; read -r line")
        fixture.panel.submit("touch \"$HOME/second\"")
        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(FileManager.default.fileExists(atPath: fixture.home + "/first"))
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/second"))
        fixture.panel.keystroke(.write([0x0D]))
        _ = try await fixture.done()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/second"))
        guard case .done = fixture.panel.state else {
            Issue.record("not Done: \(String(describing: fixture.panel.state))")
            return
        }
    }

    @Test("Every chunk is drawn before Done, and none reaches the panel after a clear")
    internal func outputBeforeDone() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("sleep 0.1; head -c 65536 /dev/zero | tr '\\000' x")
        _ = try await fixture.running()
        // Held, the main actor draws nothing while the command writes everything and ends.
        usleep(300_000)
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let text = fixture.window.transcript.string
        #expect(text.count == 65_536)
        #expect(text.allSatisfy { $0 == "x" })

        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(fixture.window.transcript.string.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.window.transcript.string.isEmpty)
    }

    @Test(
        "A failed capture is a notice in plain words; the command still runs",
        arguments: [
            (LoginEnvironment.CaptureError.noLoginShell, "no login shell"),
            (.shellFailed(status: 2), "shell exited 2"),
            (.timedOut, "timed out after five seconds"),
        ])
    internal func launchTaskFailed(error: LoginEnvironment.CaptureError, reason: String) async throws {
        let fixture = try Fixture(launch: Task { throw error })
        defer { fixture.tearDown() }
        fixture.panel.submit("true")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        try await fixture.until { fixture.window.notice.stringValue.contains("not captured") }
        #expect(fixture.window.notice.stringValue.contains(reason))
    }

    @Test("Quit kills a running command within about a second and leaves its group empty")
    internal func killForQuit() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.submit("sleep 300")
        let pid = try await fixture.running()
        let clock = ContinuousClock()
        let asked = clock.now
        await fixture.panel.killForQuit()
        #expect(clock.now - asked < .milliseconds(1_500))
        #expect(fixture.panel.state == .done(.signal(SIGKILL), retry: nil))
        #expect(try await survivors(ofGroup: pid).isEmpty)
    }

    @Test("Quit during the launch wait kills the command once it starts and leaves no child")
    internal func killForQuitInFlight() async throws {
        let (launch, open) = gate()
        let fixture = try Fixture(launch: launch)
        defer { fixture.tearDown() }
        fixture.panel.submit("sleep 30")
        let quit = Task { await fixture.panel.killForQuit() }
        try await Task.sleep(for: .milliseconds(100))
        open()
        await quit.value
        #expect(fixture.panel.state == .done(.signal(SIGKILL), retry: nil))
        // No group check: the kill lands before the command can report its pid, and Done after SIGKILL is Run's reap.
        #expect(try await children().isEmpty)
    }

    @Test("Quit at once after a killing clear waits for that kill: the command is gone when Quit returns")
    internal func killForQuitAfterClear() async throws {
        let (fixture, _) = try await reach(.live)
        defer { fixture.tearDown() }
        guard case .running(let pid) = fixture.panel.state else { throw TimedOut() }
        // Stop, which the command ignores, then the clear, which kills it; Quit is asked for at once.
        fixture.panel.escape()
        fixture.panel.escape()
        // The panel is clean, but the clear's kill is still on its way: Quit must wait for it.
        #expect(fixture.panel.quitMustWait)
        #expect(fixture.look() == .clean)
        await fixture.panel.killForQuit()
        // Read before the test yields: the kill was sent and the command's Done had arrived when Quit returned.
        #expect(!fixture.panel.quitMustWait)
        #expect(try ps(["-o", "pid=", "-p", "\(pid)"]).isEmpty)
        #expect(try await survivors(ofGroup: pid).isEmpty)
        #expect(fixture.look() == .clean)
    }
}

// The Escape ladder and the click-out rule: every reachable cell of the table, one test per
// column and result, the state as the parameter. A cell that says "nothing" reads the panel before and
// after, then shows the command untouched.
extension PanelTests {
    @Test("Escape × Clean: hide")
    internal func escapeHidesClean() async throws {
        let (fixture, _) = try await reach(.clean)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.panel.escape()
        #expect(fixture.look() == before.hidden)
    }

    @Test("Escape × Typed, Done: clear", arguments: [Rung.typed, .done, .doneTyped])
    internal func escapeClears(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        #expect(fixture.look() != .clean)
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        #expect(fixture.window.outputCard.isHidden)
    }

    @Test("Escape × In flight: nothing")
    internal func escapeInFlight() async throws {
        let (fixture, open) = try await reach(.inFlight)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.panel.escape()
        #expect(fixture.look() == before)
        try await expectUntouched(.inFlight, fixture, opening: open)
    }

    @Test("Escape × Running, live: stop — the group is interrupted, the Stop count advances, nothing more is drawn")
    internal func escapeStops() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        let pid = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.escape()
        #expect(fixture.window.isVisible)
        guard case .done(.signal(SIGINT), _) = try await fixture.done() else {
            Issue.record("not ended by SIGINT: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(try await survivors(ofGroup: pid).isEmpty)

        // The same counter and flag as Stop: after Escape, Stop kills, and what the command printed
        // meanwhile was not drawn.
        fixture.panel.submit(Fixture.held)
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let drawn = fixture.window.transcript.string
        fixture.panel.escape()
        try await fixture.alive("a")
        fixture.panel.stop()
        #expect(try await fixture.done() == .done(.signal(SIGKILL), retry: nil))
        #expect(fixture.window.transcript.string == drawn)
    }

    @Test("Click-out × Clean, Typed, Done: hide, keeping everything", arguments: [Rung.clean, .typed, .done])
    internal func clickOutHides(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.clickOut()
        #expect(fixture.look() == before.hidden)
    }

    @Test(
        "Click-out × In flight, Running live, Running stopped: nothing; the panel stays",
        arguments: [Rung.inFlight, .live, .stopped])
    internal func clickOutStays(rung: Rung) async throws {
        let (fixture, open) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.clickOut()
        #expect(fixture.look() == before.withoutKeyboard)
        try await expectUntouched(rung, fixture, opening: open)
    }

    @Test("Hotkey, hidden × Clean, Typed, Done: show, as it was", arguments: [Rung.clean, .typed, .done])
    internal func hotkeyShows(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.clickOut()
        #expect(!fixture.window.isVisible)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(fixture.keyboardInInput)
    }

    @Test(
        "Hotkey, visible without the keyboard × every state: take the keyboard",
        arguments: [Rung.clean, .typed, .inFlight, .live, .stopped, .done])
    internal func hotkeyTakesKeyboard(rung: Rung) async throws {
        let (fixture, open) = try await reach(rung)
        defer { fixture.tearDown() }
        fixture.loseKeyboard()
        let before = fixture.look()
        #expect(before.visible && !before.key)
        fixture.panel.toggle()
        #expect(fixture.look() == before.withKeyboard)
        if rung.busy {
            try await expectUntouched(rung, fixture, opening: open)
        }
    }

    @Test(
        "Hotkey, visible with the keyboard × Clean, Typed, Done: hide, keeping everything",
        arguments: [Rung.clean, .typed, .done])
    internal func hotkeyHides(rung: Rung) async throws {
        let (fixture, _) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        fixture.panel.toggle()
        #expect(fixture.look() == before.hidden)
    }

    @Test(
        "Hotkey, visible with the keyboard × In flight, Running live, Running stopped: nothing",
        arguments: [Rung.inFlight, .live, .stopped])
    internal func hotkeyStays(rung: Rung) async throws {
        let (fixture, open) = try await reach(rung)
        defer { fixture.tearDown() }
        let before = fixture.look()
        #expect(before.visible && before.key)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        try await expectUntouched(rung, fixture, opening: open)
    }
}

// The race of Escape in Running, stopped against Done, and the rules tested on their own.
extension PanelTests {
    @Test("Escape × Running, stopped, the command alive: clear, killing it; its Done lands on nothing")
    internal func escapeClearsKilling() async throws {
        let (fixture, _) = try await reach(.live)
        defer { fixture.tearDown() }
        guard case .running(let pid) = fixture.panel.state else { throw TimedOut() }
        fixture.panel.escape()
        try await fixture.alive("a")
        #expect(fixture.panel.state == .running(pid: pid))
        fixture.panel.escape()
        #expect(fixture.panel.awaitsClearedDone)
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        #expect(!fixture.window.transcript.showsCursor)
        #expect(try await survivors(ofGroup: pid).isEmpty)

        // The killed command's Done has reached the panel once it is no longer awaited; the panel is
        // read after that, so a Done applied there would be seen, not overwritten unseen.
        try await fixture.until { !fixture.panel.awaitsClearedDone }
        #expect(fixture.look() == .clean)
        #expect(fixture.window.outputCard.isHidden)
        #expect(fixture.keyboardInInput)

        // Nothing of it reaches the next command either.
        fixture.panel.escape()
        #expect(fixture.look() == Look.clean.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == .clean)
        fixture.panel.submit("echo after")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == "after\n")
        #expect(fixture.window.status.stringValue == "exit 0")
    }

    @Test("Escape × Running, stopped, Done landing first: the second Escape finds Done and clears")
    internal func escapeClearsAfterDone() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        let pid = try await fixture.running()
        try await fixture.transcriptContains("ready")
        fixture.panel.escape()
        guard case .done(.signal, _) = try await fixture.done() else {
            Issue.record("not ended by a signal: \(String(describing: fixture.panel.state))")
            return
        }
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        #expect(try await survivors(ofGroup: pid).isEmpty)
    }

    // Once the leader exits, the kernel's hang-up on the closing terminal is what reaches the rest of the
    // group, as a closed terminal window's does. A job that ignores it outlives the panel, and nothing is
    // built for it. The test records that, then kills the group itself (ho-02's ruling of 2026-10-26, kept
    // for the panel by the practitioner in ho-04.6.1).
    @Test("A job that ignores the hang-up outlives its leader's Done, a clear and a hide")
    internal func survivorOfHangUp() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        var group: pid_t?
        // Cleanup only: the group is killed here if the test ends early with members left.
        defer {
            if let group, (try? ps(["-o", "pid=", "-g", "\(group)"]))?.isEmpty == false { killpg(group, SIGKILL) }
        }
        fixture.panel.show()
        fixture.panel.submit("sh -c 'trap \"\" HUP INT; echo ready; sleep 30' & wait")
        let pid = try await fixture.running()
        group = pid
        try await fixture.transcriptContains("ready")
        fixture.panel.escape()
        guard case .done = try await fixture.done() else { throw TimedOut() }
        // The leader is gone and the job is not; its sleep may still be starting, so later reads keep
        // every pid this one lists.
        let members = Set(try ps(["-o", "pid=", "-g", "\(pid)"]).split(whereSeparator: \.isNewline))
        #expect(try ps(["-o", "pid=", "-p", "\(pid)"]).isEmpty)
        #expect(!members.isEmpty)

        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        fixture.panel.escape()
        #expect(fixture.look() == Look.clean.hidden)
        #expect(members.isSubset(of: try ps(["-o", "pid=", "-g", "\(pid)"]).split(whereSeparator: \.isNewline)))

        killpg(pid, SIGKILL)
        #expect(try await survivors(ofGroup: pid).isEmpty)
    }

    @Test("A start that fails before Running keeps its reason through a hide and a show")
    internal func failedStartKept() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let window = fixture.window
        fixture.panel.show()
        window.input.stringValue = "echo never"
        try await failStart(window.input.stringValue, in: fixture)
        #expect(!fixture.panel.isBusy)
        let before = fixture.look()
        #expect(before.state == nil && before.input == "echo never")
        #expect(before.status.hasPrefix("Could not start: "))
        #expect(same(window.status.textColor, Theme.Token.alarm))
        #expect(!window.outputCard.isHidden)

        fixture.clickOut()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(same(window.status.textColor, Theme.Token.alarm))
        #expect(!window.outputCard.isHidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(same(window.status.textColor, Theme.Token.alarm))
        #expect(!window.outputCard.isHidden)

        // The next submission and its Running end the reason.
        fixture.panel.submit("echo after")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.status.stringValue == "exit 0")
        #expect(same(window.status.textColor, Theme.Token.inkFaint))

        // So does a clear.
        window.input.stringValue = "echo never"
        try await failStart(window.input.stringValue, in: fixture)
        #expect(window.status.stringValue.hasPrefix("Could not start: "))
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(window.outputCard.isHidden)
    }

    @Test("In flight, live and stopped, neither click-out nor the hotkey hides the panel")
    internal func nothingAliveHidden() async throws {
        let (fixture, open) = try await reach(.inFlight)
        defer { fixture.tearDown() }
        func attempt() {
            fixture.clickOut()
            #expect(fixture.window.isVisible)
            fixture.panel.toggle()
            #expect(fixture.window.isVisible)
            #expect(fixture.window.isKeyWindow)
            fixture.panel.toggle()
            #expect(fixture.window.isVisible)
        }
        attempt()
        #expect(fixture.panel.state == nil && fixture.panel.isBusy)
        open()
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        attempt()
        fixture.panel.stop()
        attempt()
        guard case .running = fixture.panel.state else { throw TimedOut() }
        try await fixture.end(opening: open)
    }

    @Test("A Done panel with an offer and a typed line, hidden and shown, is as it was")
    internal func hidingLosesNothing() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()
        fixture.panel.show()
        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        fixture.window.input.stringValue = "typed line"
        let before = fixture.look()
        #expect(before.offer && !before.transcript.isEmpty && !before.status.isEmpty)

        fixture.clickOut()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        fixture.panel.toggle()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(fixture.keyboardInInput)
    }

    @Test("Clear a live command, submit a new line at once, and it reaches Running")
    internal func submitAfterClear() async throws {
        let (fixture, _) = try await reach(.live)
        defer { fixture.tearDown() }
        guard case .running(let cleared) = fixture.panel.state else { throw TimedOut() }
        fixture.panel.escape()
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        fixture.window.input.stringValue = "echo next; read -r line"
        fixture.panel.submit(fixture.window.input.stringValue)
        let next = try await fixture.running()
        #expect(next != cleared)
        try await fixture.transcriptContains("next")
        #expect(fixture.window.status.stringValue == "running")
        #expect(try await survivors(ofGroup: cleared).isEmpty)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        // The terminal echoes the carriage return as an empty line; nothing of the cleared command is there.
        #expect(fixture.window.transcript.string == "next\n\n")
    }

    @Test("Escape never reaches the command; a line read after it has length zero")
    internal func escapeNeverWritten() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        // The command ignores the interrupt Escape sends, and writes the length where the panel, now
        // stopped, does not draw.
        fixture.panel.submit("sh -c 'trap \"\" INT; echo ready; read -r secret; printf %s \"${#secret}\" > length'")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let window = fixture.window
        #expect(window.firstResponder === window.transcript)
        window.transcript.keyDown(with: try key("\u{1B}", code: UInt16(kVK_Escape), in: window))
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(try String(contentsOfFile: fixture.home + "/length", encoding: .utf8) == "0")
    }
}

// Every route by which AppKit delivers Escape reaches `Panel.escape()`; the fourth, the transcript
// when no command runs, is `escapeInTranscript`, with the transcript's tests.
extension PanelTests {
    @Test("Escape route: the input's field editor, Clean: hides")
    internal func escapeInInput() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        let editor = try #require(fixture.window.input.currentEditor())
        editor.keyDown(with: try key("\u{1B}", code: UInt16(kVK_Escape), in: fixture.window))
        #expect(fixture.look() == Look.clean.hidden)
    }

    @Test("Escape route: the transcript while Running: stops")
    internal func escapeInTranscriptRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        let pid = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let window = fixture.window
        #expect(window.firstResponder === window.transcript)
        window.transcript.keyDown(with: try key("\u{1B}", code: UInt16(kVK_Escape), in: window))
        guard case .done(.signal(SIGINT), _) = try await fixture.done() else {
            Issue.record("not ended by SIGINT: \(String(describing: fixture.panel.state))")
            return
        }
        #expect(window.isVisible)
        #expect(try await survivors(ofGroup: pid).isEmpty)
    }

    @Test("Escape route: the window's cancelOperation with no text responder, Clean: hides")
    internal func escapeInWindow() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        #expect(fixture.window.makeFirstResponder(nil))
        #expect(fixture.window.firstResponder === fixture.window)
        fixture.window.cancelOperation(nil)
        #expect(fixture.look() == Look.clean.hidden)
    }
}
