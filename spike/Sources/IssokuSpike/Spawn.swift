import Darwin

/// A child running under a pseudoterminal.
///
/// `forkpty` calls `setsid` in the child, so the child is a session leader and its
/// process-group id equals its pid; `pid` is therefore also the group passed to `killpg`.
struct PTYChild: Sendable {
    /// The child's pid, which is also its process-group id.
    let pid: pid_t
    /// The master side of the pseudoterminal; the child holds the slave as fds 0, 1, 2.
    let master: Int32
}

/// The spawn failed before the child existed.
struct SpawnError: Error {
    /// `errno` from `forkpty`.
    let code: Int32
}

/// The spawn path: candidate 1 of ho-01 Decision 2, `forkpty`.
///
/// Runs `<shell> -c <line>` with exactly `environment` and nothing inherited, under a new
/// pseudoterminal that is the child's controlling terminal, in a new session and process
/// group, with the working directory inherited. This path calls `fork`.
///
/// The window size is left unset (nil), so the child's terminal reports 0 rows by 0 columns.
func spawnUnderPTY(shell: String, line: String, environment: [String: String]) throws -> PTYChild {
    // Everything the child reads is allocated before the fork. Between fork and exec the
    // child calls only async-signal-safe functions: signal, sigprocmask, execve, _exit.
    var argv: [UnsafeMutablePointer<CChar>?] = [strdup(shell), strdup("-c"), strdup(line), nil]
    var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
        for pointer in argv { free(pointer) }
        for pointer in envp { free(pointer) }
    }

    var master: Int32 = -1
    let pid = argv.withUnsafeMutableBufferPointer { argvBuffer in
        envp.withUnsafeMutableBufferPointer { envpBuffer in
            let forked = forkpty(&master, nil, nil, nil)
            if forked == 0 {
                execInChild(argv: argvBuffer.baseAddress, envp: envpBuffer.baseAddress)
            }
            return forked
        }
    }
    guard pid > 0 else { throw SpawnError(code: errno) }
    return PTYChild(pid: pid, master: master)
}

// Runs in the forked child only. Signal dispositions are reset to default and the mask is
// cleared, because exec preserves an ignored disposition: a harness launched with `&` from a
// non-interactive shell starts with SIGINT ignored, and the child would inherit that.
private func execInChild(
    argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    envp: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Never {
    for signalNumber in 1..<NSIG {
        signal(signalNumber, SIG_DFL)
    }
    var emptyMask = sigset_t()
    sigemptyset(&emptyMask)
    sigprocmask(SIG_SETMASK, &emptyMask, nil)
    if let argv, let path = argv[0] {
        execve(path, argv, envp)
    }
    _exit(127)
}
