import Foundation
import Testing

@testable import HitoikiCore

/// A fresh directory under the temporary directory, removed by the caller.
internal func makeDirectory() throws -> String {
    let path = NSTemporaryDirectory() + "hitoiki-tests-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

/// Writes an executable `/bin/sh` script into `directory` and returns its path.
internal func writeScript(_ name: String, in directory: String, body: String) throws -> String {
    let path = directory + "/" + name
    try ("#!/bin/sh\n" + body + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    return path
}

@Suite("Login environment")
internal struct LoginEnvironmentTests {
    @Test("Every variable is kept but the shell's own four; TERM is kept when present")
    internal func keepsVariables() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let shell = try writeScript(
            "fake-shell",
            in: directory,
            body: """
                [ "$1 $2 $3" = "-l -c env -0" ] || exit 9
                printf 'HOME=/home/u\\0SSH_AUTH_SOCK=/tmp/agent\\0EMPTY=\\0EQ=a=b\\0TERM=vt100\\0'
                printf '_=/usr/bin/env\\0SHLVL=1\\0OLDPWD=/\\0PWD=/tmp\\0NOEQUALS\\0'
                """)
        let captured = try LoginEnvironment.capture(shell: shell)
        #expect(
            captured == [
                "HOME": "/home/u", "SSH_AUTH_SOCK": "/tmp/agent", "EMPTY": "", "EQ": "a=b", "TERM": "vt100",
            ])
    }

    @Test("TERM is supplied when the capture yields none")
    internal func suppliesTerm() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let shell = try writeScript("fake-shell", in: directory, body: "printf 'A=1\\0'")
        #expect(try LoginEnvironment.capture(shell: shell) == ["A": "1", "TERM": "xterm-256color"])
    }

    @Test("A shell that exits non-zero throws shellFailed")
    internal func nonZero() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let shell = try writeScript("fake-shell", in: directory, body: "printf 'A=1\\0'; exit 4")
        #expect(throws: LoginEnvironment.CaptureError.shellFailed(status: 4)) {
            try LoginEnvironment.capture(shell: shell)
        }
    }

    @Test("A shell that outlives five seconds throws timedOut")
    internal func timesOut() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let shell = try writeScript("fake-shell", in: directory, body: "exec /bin/sleep 30")
        let clock = ContinuousClock()
        let started = clock.now
        #expect(throws: LoginEnvironment.CaptureError.timedOut) {
            try LoginEnvironment.capture(shell: shell)
        }
        let elapsed = clock.now - started
        #expect(elapsed >= .seconds(5) && elapsed < .seconds(8))
    }

    @Test("A shell that closes its output and keeps running throws timedOut at the same deadline")
    internal func timesOutAfterOutputCloses() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let shell = try writeScript("fake-shell", in: directory, body: "printf 'A=1\\0'; exec >&-; exec /bin/sleep 30")
        let clock = ContinuousClock()
        let started = clock.now
        #expect(throws: LoginEnvironment.CaptureError.timedOut) {
            try LoginEnvironment.capture(shell: shell)
        }
        let elapsed = clock.now - started
        #expect(elapsed >= .seconds(5) && elapsed < .seconds(8))
    }

    @Test("The login shell comes from the password database")
    internal func loginShell() throws {
        let shell = try LoginEnvironment.loginShell()
        #expect(shell.hasPrefix("/"))
        #expect(FileManager.default.isExecutableFile(atPath: shell))
    }
}
