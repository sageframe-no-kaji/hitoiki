import Darwin
import Foundation

@testable import HitoikiCore

/// A command run to Done: every byte it sent, how it ended, the offer, and its pid and group.
internal struct Outcome {
    let output: [UInt8]
    let exit: Exit
    let retry: String?
    let pid: pid_t

    var text: String { String(bytes: output, encoding: .utf8) ?? "" }
}

/// A state other than the one the test waited for.
internal struct UnexpectedState: Error {
    let state: RunState?
}

/// An environment the test owns.
///
/// HOME is the test's own empty directory, so the login shell reads no startup file of the user's;
/// HOME and LOGNAME are given because zsh exports them when absent.
internal func ownedEnvironment(home: String, path: String = "/usr/bin:/bin:/usr/sbin:/sbin") -> [String: String] {
    ["HOME": home, "LOGNAME": NSUserName(), "PATH": path, "TERM": "xterm-256color"]
}

/// Runs `line` to Done on a fresh Run started in `environment["HOME"]`.
///
/// `before` runs on the Run before the start. With a `marker`, waits until the output holds it, then
/// calls `act`. The rest of the bytes are taken alongside the wait for Done, which follows the taking
/// of every chunk, so what was taken by Done is every byte the command sent.
internal func drive(
    _ line: String,
    environment: [String: String],
    captureShell: String? = nil,
    size: WindowSize = WindowSize(columns: 80, rows: 24),
    before: (Run) async throws -> Void = { _ in },
    after marker: String? = nil,
    act: (Run, pid_t) async throws -> Void = { _, _ in }
) async throws -> Outcome {
    var output: [UInt8] = []
    let run = Run(environment: environment, captureShell: captureShell)
    var bytes = run.bytes.makeAsyncIterator()
    try await before(run)
    var states = run.states.makeAsyncIterator()
    try await run.start(line: line, cwd: environment["HOME"] ?? "/", size: size)
    let started = await states.next()
    guard case .running(let pid) = started else { throw UnexpectedState(state: started) }
    if let marker {
        while !output.contains(Array(marker.utf8)), let chunk = await bytes.next() {
            output += chunk
        }
    }
    try await act(run, pid)
    let rest = remaining(bytes)
    let ended = await states.next()
    rest.cancel()
    output += await rest.value
    guard case .done(let exit, let retry) = ended else { throw UnexpectedState(state: ended) }
    return Outcome(output: output, exit: exit, retry: retry, pid: pid)
}

/// Takes every chunk `bytes` has left, each as it arrives, until the task is cancelled.
///
/// Cancel it after Done, by which every chunk has been taken; cancelling the wait for another ends the stream.
internal func remaining(_ bytes: sending Run.Output.Iterator) -> Task<[UInt8], Never> {
    Task {
        var bytes = bytes
        var taken: [UInt8] = []
        while let chunk = await bytes.next() { taken += chunk }
        return taken
    }
}

/// What `/bin/ps` prints for `arguments`, trimmed.
///
/// The process table is the witness, not Run.
internal func ps(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The pids left in process group `group`, read until none remain or two seconds pass.
internal func survivors(ofGroup group: pid_t) async throws -> String {
    let deadline = ContinuousClock.now + .seconds(2)
    while true {
        let listed = try ps(["-o", "pid=", "-g", "\(group)"])
        if listed.isEmpty || ContinuousClock.now >= deadline {
            return listed
        }
        try await Task.sleep(for: .milliseconds(50))
    }
}

/// The order events were observed in.
internal actor Order {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}
