import Darwin
import Dispatch
import Foundation

/// How a command ended.
public enum Exit: Sendable, Equatable {
    /// The child exited with this status.
    case status(Int32)
    /// The child was terminated by this signal.
    case signal(Int32)
}

/// Where the command is in its life.
public enum RunState: Sendable, Equatable {
    /// The child was spawned; `pid` is also its process group.
    case running(pid: Int32)
    /// The child was reaped. `retry` is the `-tt` relaunch line when the offer applies.
    case done(Exit, retry: String?)
}

/// Why `start` did not launch.
public enum RunError: Error, Equatable {
    /// A command is alive; one runs at a time.
    case alreadyRunning
    /// `forkpty` failed with this `errno`.
    case spawnFailed(errno: Int32)
}

/// One command's life: launch under a pseudoterminal in its own process group, stream its bytes,
/// carry keystrokes in, interrupt, kill, report the exit and the `-tt` retry offer.
///
/// The actor runs on a serial dispatch queue, the same queue its dispatch sources fire on, so a
/// source's handler enters the actor in order without a task hop.
public actor Run {
    /// Every chunk read from the pseudoterminal, in order, unmodified.
    ///
    /// The stream ends when Run is released.
    nonisolated public let bytes: AsyncStream<[UInt8]>
    /// `.running` after each successful start, `.done` after each child is reaped.
    nonisolated public let states: AsyncStream<RunState>

    private let bytesOut: AsyncStream<[UInt8]>.Continuation
    private let statesOut: AsyncStream<RunState>.Continuation
    private let queue = DispatchSerialQueue(label: "issoku.run")
    private var environment: [String: String]
    private var child: Child?
    private var doneWaiters: [CheckedContinuation<Void, Never>] = []

    /// The command alive, from spawn until Done.
    private struct Child {
        let pid: pid_t
        let line: String
        let reads: DispatchSourceRead
        let exits: DispatchSourceProcess
        /// The pseudoterminal's primary side; nil once the read source has drained and closed it.
        var primary: Int32?
        /// Set when the child is reaped.
        var exit: Exit?
        var scanner = RefusalScanner()
    }

    /// The executor is the serial queue the dispatch sources use.
    nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// A Run that launches commands with `environment`, plus `TERM` when it has none.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = LoginEnvironment.withTerm(environment)
        (bytes, bytesOut) = AsyncStream.makeStream()
        (states, statesOut) = AsyncStream.makeStream()
    }

    deinit {
        bytesOut.finish()
        statesOut.finish()
    }

    /// Launches `<login shell> -c <line>` in `cwd` under a pseudoterminal of `size`.
    ///
    /// - Throws: `RunError.alreadyRunning` while a command is alive, `RunError.spawnFailed` if
    ///   `forkpty` fails, `LoginEnvironment.CaptureError.noLoginShell` if there is no shell.
    public func start(line: String, cwd: String, size: WindowSize = WindowSize(columns: 80, rows: 24)) throws {
        guard child == nil else { throw RunError.alreadyRunning }
        let spawned = try spawnUnderPTY(
            shell: LoginEnvironment.loginShell(), line: line, cwd: cwd, environment: environment, size: size)
        let reads = DispatchSource.makeReadSource(fileDescriptor: spawned.primary, queue: queue)
        let exits = DispatchSource.makeProcessSource(identifier: spawned.pid, eventMask: .exit, queue: queue)
        reads.setEventHandler { [weak self] in self?.assumeIsolated { $0.readable() } }
        reads.setCancelHandler { [weak self] in
            close(spawned.primary)
            self?.assumeIsolated { $0.closed() }
        }
        // A child that exits before the source is registered posts no event; the registration
        // handler catches it without waiting.
        exits.setRegistrationHandler { [weak self] in self?.assumeIsolated { $0.reap(waiting: false) } }
        exits.setEventHandler { [weak self] in self?.assumeIsolated { $0.reap(waiting: true) } }
        child = Child(pid: spawned.pid, line: line, reads: reads, exits: exits, primary: spawned.primary)
        statesOut.yield(.running(pid: spawned.pid))
        reads.resume()
        exits.resume()
    }

    /// Sends `SIGINT` to the command's process group.
    public func interrupt() {
        signalGroup(SIGINT)
    }

    /// Sends `SIGKILL` to the command's process group.
    public func kill() {
        signalGroup(SIGKILL)
    }

    /// Writes keystrokes to the pseudoterminal, all of them.
    ///
    /// Nothing is echoed or kept here.
    public func write(_ bytes: [UInt8]) {
        guard let primary = child?.primary else { return }
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(primary, $0.baseAddress, $0.count) }
            if written > 0 {
                offset += written
            } else if errno != EINTR {
                return
            }
        }
    }

    /// Sets the pseudoterminal's size; the kernel sends the child `SIGWINCH`.
    public func resize(_ size: WindowSize) {
        guard let primary = child?.primary else { return }
        var window = size.winsize
        _ = ioctl(primary, TIOCSWINSZ, &window)
    }

    /// Captures the login environment again for the commands that follow.
    ///
    /// While a command is running this waits for Done; it never captures alongside a command.
    /// On failure the environment Run had is kept and the capture's error is thrown.
    public func refreshEnvironment() async throws {
        while child != nil {
            await withCheckedContinuation { doneWaiters.append($0) }
        }
        environment = try LoginEnvironment.capture()
    }

    private func signalGroup(_ signal: Int32) {
        guard let child, child.exit == nil else { return }
        killpg(child.pid, signal)
    }

    /// Reads one chunk into `bytes`.
    ///
    /// False at end of output or on a read error other than `EINTR`.
    private func readChunk() -> Bool {
        guard let primary = child?.primary else { return false }
        let count = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 16_384) { buffer in
            let count = Darwin.read(primary, buffer.baseAddress, buffer.count)
            if count > 0 {
                let chunk = Array(buffer[..<count])
                bytesOut.yield(chunk)
                child?.scanner.scan(chunk)
            }
            return count
        }
        return count > 0 || (count < 0 && errno == EINTR)
    }

    private func readable() {
        if !readChunk() {
            child?.reads.cancel()
        }
    }

    /// Reaps the child if it has exited, drains what it left in the pseudoterminal, then closes it.
    private func reap(waiting: Bool) {
        guard let pid = child?.pid, child?.exit == nil else { return }
        var status: Int32 = 0
        var reaped: pid_t
        repeat {
            reaped = waitpid(pid, &status, waiting ? 0 : WNOHANG)
        } while reaped < 0 && errno == EINTR
        guard reaped == pid else { return }
        let termination = status & 0x7F
        child?.exit = termination == 0 ? .status((status >> 8) & 0xFF) : .signal(termination)
        child?.exits.cancel()
        if let primary = child?.primary {
            var ready = pollfd(fd: primary, events: Int16(POLLIN), revents: 0)
            while poll(&ready, 1, 0) > 0, readChunk() {}
            child?.reads.cancel()
        }
        finishIfDone()
    }

    private func closed() {
        child?.primary = nil
        finishIfDone()
    }

    /// Done once the child is reaped and the pseudoterminal closed: emit `.done` and wake refreshes.
    private func finishIfDone() {
        guard let current = child, current.primary == nil, let exit = current.exit else { return }
        child = nil
        let retry = Retry.offer(line: current.line, exit: exit, sawSudoRefusal: current.scanner.sawRefusal)
        statesOut.yield(.done(exit, retry: retry))
        let waiters = doneWaiters
        doneWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }
}
