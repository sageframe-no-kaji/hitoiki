import Darwin

/// A terminal size in character cells, as the child's pseudoterminal reports it.
public struct WindowSize: Sendable, Equatable {
    /// The width in characters.
    public let columns: UInt16
    /// The height in lines.
    public let rows: UInt16

    /// Pixel dimensions are not carried; the kernel's are left zero.
    public init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }

    /// The kernel's form of the size, for `forkpty` and `TIOCSWINSZ`.
    var winsize: Darwin.winsize { Darwin.winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0) }
}

/// A child running under a pseudoterminal.
///
/// `forkpty` calls `setsid` in the child, so the child leads a new session and process group and
/// its pid is also the group passed to `killpg`.
struct PTYChild {
    /// The child's pid, which is also its process-group id.
    let pid: pid_t
    /// The pseudoterminal's primary side, which POSIX calls the master; the child holds the other
    /// side as fds 0, 1, 2.
    let primary: Int32
}

/// Runs `<shell> -c <line>` under a new pseudoterminal that is the child's controlling terminal.
///
/// The child gets exactly `environment` and nothing inherited, starts in `cwd`, and sees `size`
/// from its first instruction. Everything the child reads is allocated before the fork.
func spawnUnderPTY(
    shell: String,
    line: String,
    cwd: String,
    environment: [String: String],
    size: WindowSize
) throws -> PTYChild {
    var argv: [UnsafeMutablePointer<CChar>?] = [strdup(shell), strdup("-c"), strdup(line), nil]
    var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    let directory = strdup(cwd)
    defer {
        for pointer in argv + envp {
            free(pointer)
        }
        free(directory)
    }

    var primary: Int32 = -1
    var window = size.winsize
    let pid = argv.withUnsafeMutableBufferPointer { argvBuffer in
        envp.withUnsafeMutableBufferPointer { envpBuffer in
            let forked = forkpty(&primary, nil, nil, &window)
            if forked == 0 {
                execInChild(directory: directory, argv: argvBuffer.baseAddress, envp: envpBuffer.baseAddress)
            }
            return forked
        }
    }
    guard pid > 0 else { throw RunError.spawnFailed(errno: errno) }
    // Run's queue must never wait on a child that stops reading its terminal.
    _ = fcntl(primary, F_SETFL, fcntl(primary, F_GETFL) | O_NONBLOCK)
    return PTYChild(pid: pid, primary: primary)
}

// Runs in the forked child only, between fork and exec. The child execs or exits and never
// reports coverage, so these lines are uncoverable by construction. Only async-signal-safe calls:
// signal, sigemptyset, sigprocmask, getdtablesize, close, chdir, execve, _exit. Every disposition
// is reset to default and the mask cleared, because exec preserves an ignored disposition and the
// app may ignore SIGINT. A working directory that cannot be entered ends the child with 127, as a
// failed exec does.
private func execInChild(
    directory: UnsafePointer<CChar>?,
    argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    envp: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Never {
    for signalNumber in 1..<NSIG {
        signal(signalNumber, SIG_DFL)
    }
    var emptyMask = sigset_t()
    sigemptyset(&emptyMask)
    sigprocmask(SIG_SETMASK, &emptyMask, nil)
    // The app's files and sockets must not leak into every command; forkpty has already closed the
    // primary in the child, and the pseudoterminal is fds 0, 1, 2.
    for descriptor in 3..<getdtablesize() {
        close(descriptor)
    }
    if let directory, chdir(directory) == 0, let argv, let path = argv[0] {
        execve(path, argv, envp)
    }
    _exit(127)
}
