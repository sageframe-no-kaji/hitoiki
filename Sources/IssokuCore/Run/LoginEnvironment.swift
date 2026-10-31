import Darwin
import Foundation

/// The user's environment, read once from their login shell.
public enum LoginEnvironment {
    /// Why a capture produced no environment.
    public enum CaptureError: Error, Equatable {
        /// The password database has no login shell for the current user.
        case noLoginShell
        /// The capture shell ended with this non-zero status, or this signal.
        case shellFailed(status: Int32)
        /// The capture shell did not finish within five seconds.
        case timedOut
    }

    /// The names the capture itself produces, which carry nothing of the user's. `PWD` is set
    /// by the shell from each command's working directory.
    static let dropped: Set = ["_", "SHLVL", "OLDPWD", "PWD"]

    /// The login shell from the password database entry for the current uid.
    static func loginShell() throws -> String {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell, shell.pointee != 0 else {
            throw CaptureError.noLoginShell
        }
        return String(cString: shell)
    }

    /// `environment` with `TERM=xterm-256color` added when it has no `TERM`.
    static func withTerm(_ environment: [String: String]) -> [String: String] {
        environment.merging(["TERM": "xterm-256color"]) { given, _ in given }
    }

    /// Runs `<shell> -l -c 'env -0'` from this process's environment, with stdin from
    /// `/dev/null`, and returns every variable it prints except the dropped names, with `TERM`
    /// supplied if absent.
    ///
    /// - Parameter shell: The shell to run; nil reads the login shell from the password database.
    /// - Returns: The captured variables by name.
    /// - Throws: `CaptureError` naming why nothing was captured.
    public static func capture(shell: String? = nil) throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try shell ?? loginShell())
        process.arguments = ["-l", "-c", "env -0"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()

        let deadline = ContinuousClock.now + .seconds(5)
        func expired() -> CaptureError {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            return .timedOut
        }
        var output: [UInt8] = []
        var ready = pollfd(fd: pipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        while true {
            let remaining = Int32((ContinuousClock.now.duration(to: deadline) / .milliseconds(1)).rounded(.up))
            guard remaining > 0, poll(&ready, 1, remaining) > 0 else { throw expired() }
            let count = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 4_096) { buffer in
                let count = read(ready.fd, buffer.baseAddress, buffer.count)
                output += buffer.prefix(max(count, 0))
                return count
            }
            if count <= 0 { break }
        }
        // A shell can close its output and keep running; the deadline covers the whole capture.
        while process.isRunning, ContinuousClock.now < deadline { usleep(10_000) }
        guard !process.isRunning else { throw expired() }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw CaptureError.shellFailed(status: process.terminationStatus)
        }

        var variables: [String: String] = [:]
        for entry in output.split(separator: 0) {
            guard let text = String(bytes: entry, encoding: .utf8), let equals = text.firstIndex(of: "=") else {
                continue
            }
            let name = String(text[..<equals])
            if !dropped.contains(name) {
                variables[name] = String(text[text.index(after: equals)...])
            }
        }
        return withTerm(variables)
    }
}
