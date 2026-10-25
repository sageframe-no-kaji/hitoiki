import Darwin
import Foundation

/// The environment read once from the user's login shell (ho-01 Decision 3).
///
/// The invocation is `<shell> -l -c 'env -0'`, run with the harness's own environment and
/// stdin from /dev/null. Which variables are kept is ho-02's decision; the spike keeps all.
struct LoginEnvironment {
    /// The login shell from the password database entry for the current uid.
    let shell: String
    /// The argument vector the capture ran.
    let invocation: [String]
    /// Every `NAME=value` pair the capture printed.
    let variables: [String: String]
}

/// The capture could not produce an environment.
enum EnvironmentCaptureError: Error {
    /// `getpwuid(getuid())` returned no entry or no shell.
    case noLoginShell
    /// The capture shell exited non-zero.
    case captureFailed(status: Int32)
}

/// Reads the login shell and captures its environment.
func captureLoginEnvironment() throws -> LoginEnvironment {
    guard let entry = getpwuid(getuid()), let shellPointer = entry.pointee.pw_shell else {
        throw EnvironmentCaptureError.noLoginShell
    }
    let shell = String(cString: shellPointer)
    let arguments = ["-l", "-c", "env -0"]

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw EnvironmentCaptureError.captureFailed(status: process.terminationStatus)
    }

    var variables: [String: String] = [:]
    for entryBytes in data.split(separator: 0) {
        guard let text = String(bytes: entryBytes, encoding: .utf8), let equals = text.firstIndex(of: "=") else {
            continue
        }
        variables[String(text[..<equals])] = String(text[text.index(after: equals)...])
    }
    return LoginEnvironment(shell: shell, invocation: [shell] + arguments, variables: variables)
}
