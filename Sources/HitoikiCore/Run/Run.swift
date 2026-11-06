import Darwin
import Dispatch
import Foundation

/// How a command ended.
public enum Exit: Sendable, Equatable {
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
    /// Every chunk read from the pseudoterminal, in order, unmodified, for one consumer.
    ///
    /// Read-ahead pauses at `outputCeiling`; the command then waits on its terminal.
    /// The sequence ends when Run is released, after every chunk read before then.
    nonisolated public var bytes: Output { Output(chunks: chunks, run: self) }
    /// `.running` after each successful start, `.done` after each child is reaped and its output taken.
    nonisolated public let states: AsyncStream<RunState>

    static let outputCeiling = 1 << 20

    private let chunks: AsyncStream<[UInt8]>
    private let chunksOut: AsyncStream<[UInt8]>.Continuation
    private let statesOut: AsyncStream<RunState>.Continuation
    private let queue = DispatchSerialQueue(label: "hitoiki.run")
    private var environment: [String: String]
    private let captureShell: String?
    private var child: Child?
    private var doneWaiters: [CheckedContinuation<Void, Never>] = []
    private var untaken = 0

    /// Run's output as its consumer pulls it; each chunk taken makes room for the command.
    public struct Output: AsyncSequence, Sendable {
        let chunks: AsyncStream<[UInt8]>
        weak var run: Run?

        /// An iterator that tells Run what it takes.
        public func makeAsyncIterator() -> Iterator { Iterator(chunks: chunks.makeAsyncIterator(), run: run) }
    }

    private struct Child {
        let pid: pid_t
        let line: String
        let reads: DispatchSourceRead
        let exits: DispatchSourceProcess
        /// The pseudoterminal's primary side; nil once the read source has drained and closed it.
        var primary: Int32?
        var exit: Exit?
        var scanner = RefusalScanner()
        var pending: [UInt8] = []
        /// Present only while keystrokes pend; fires when the terminal has room.
        var writes: DispatchSourceWrite?
        var held = false
    }

    /// The executor is the serial queue the dispatch sources use.
    nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// A Run that launches commands with `environment`, plus `TERM` when it has none.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(environment: environment, captureShell: nil)
    }

    /// `captureShell` replaces the login shell for `refreshEnvironment`, so tests can fake it.
    init(environment: [String: String], captureShell: String? = nil) {
        self.environment = LoginEnvironment.withTerm(environment)
        self.captureShell = captureShell
        (chunks, chunksOut) = AsyncStream.makeStream()
        (states, statesOut) = AsyncStream.makeStream()
    }

    // No command outlives Run. The handlers hold Run weakly and do nothing from here on; the read
    // source's cancel handler still closes the primary it captured. A waiting refresh holds Run.
    deinit {
        if let child {
            if child.exit == nil {
                // By pid as well: forkpty returns before the child's setsid, so the group may not exist yet.
                Darwin.kill(child.pid, SIGKILL)
                killpg(child.pid, SIGKILL)
            }
            if child.held { child.reads.resume() }
            child.writes?.cancel()
            child.reads.cancel()
            child.exits.cancel()
            var status: Int32 = 0
            while child.exit == nil, waitpid(child.pid, &status, 0) < 0, errno == EINTR {}
        }
        chunksOut.finish()
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

    /// Sends `SIGINT` to the command's process group, until Done, whether or not its leader has exited.
    public func interrupt() {
        signalGroup(SIGINT)
    }

    /// Sends `SIGKILL` to the command's process group, until Done, whether or not its leader has exited.
    public func kill() {
        signalGroup(SIGKILL)
    }

    /// Writes keystrokes to the pseudoterminal, all of them, in order.
    ///
    /// What it cannot take yet is held until it can, and discarded at Done. Nothing is echoed.
    public func write(_ bytes: [UInt8]) {
        guard child?.primary != nil, child?.reads.isCancelled == false else { return }
        child?.pending += bytes
        flush()
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
        environment = try LoginEnvironment.capture(shell: captureShell)
    }

    private func flush() {
        guard let primary = child?.primary else { return }
        while child?.pending.isEmpty == false {
            let written = child?.pending.withUnsafeBytes { Darwin.write(primary, $0.baseAddress, $0.count) } ?? 0
            if written > 0 {
                child?.pending.removeFirst(written)
            } else if errno == EAGAIN {
                if child?.writes == nil {
                    let writes = DispatchSource.makeWriteSource(fileDescriptor: primary, queue: queue)
                    writes.setEventHandler { [weak self] in self?.assumeIsolated { $0.flush() } }
                    writes.resume()
                    child?.writes = writes
                }
                return
            } else if errno != EINTR {
                child?.pending = []
            }
        }
        child?.writes?.cancel()
        child?.writes = nil
    }

    /// Signals the group for as long as Run holds the command, until Done: a reaped leader can leave
    /// members of its group holding the terminal, and they are still the command's.
    private func signalGroup(_ signal: Int32) {
        guard let child else { return }
        // Before forkpty's child calls setsid, its new process group may not exist yet. Only an
        // unreaped child is signalled by pid: once reaped, its pid is free for another process.
        if killpg(child.pid, signal) < 0, errno == ESRCH, child.exit == nil { Darwin.kill(child.pid, signal) }
    }

    /// False at end of output or on a read error other than `EINTR` or `EAGAIN` (nothing now).
    private func readChunk() -> Bool {
        guard let primary = child?.primary else { return false }
        let capacity = min(16_384, Self.outputCeiling - untaken)
        let count = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity) { buffer in
            let count = Darwin.read(primary, buffer.baseAddress, buffer.count)
            if count > 0 {
                let chunk = Array(buffer[..<count])
                chunksOut.yield(chunk)
                child?.scanner.scan(chunk)
                untaken += count
                if untaken >= Self.outputCeiling { hold(true) }
            }
            return count
        }
        return count > 0 || (count < 0 && (errno == EINTR || errno == EAGAIN))
    }

    private func readable() {
        if untaken >= Self.outputCeiling { hold(true) }
        if child?.held == false, !readChunk() { stopReading() }
    }

    /// The consumer took `count` bytes; reading resumes once what is untaken is under the ceiling,
    /// and an ended command's Done once nothing is untaken.
    nonisolated func taken(_ count: Int) {
        queue.async {
            self.assumeIsolated { run in
                run.untaken -= count
                if run.untaken < Self.outputCeiling { run.hold(false) }
                run.finishIfDone()
            }
        }
    }

    /// Suspends or resumes the read source, once each way: suspensions must balance, and a suspended
    /// source is resumed before it is cancelled, since releasing one traps.
    private func hold(_ held: Bool) {
        guard let reads = child?.reads, child?.held != held else { return }
        if held { reads.suspend() } else { reads.resume() }
        child?.held = held
    }

    /// Cancels writing, discarding what pends, then reading, whose cancel handler closes the primary.
    private func stopReading() {
        child?.pending = []
        flush()
        hold(false)
        child?.reads.cancel()
    }

    /// Reaps the child; reading and closure still wait for room in the output queue.
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
        if child?.primary != nil { readable() }
        finishIfDone()
    }

    private func closed() {
        child?.primary = nil
        finishIfDone()
    }

    /// Done once the child is reaped, the pseudoterminal closed and every chunk taken.
    ///
    /// Until then the ended child stays in place, so `start` throws `alreadyRunning`.
    private func finishIfDone() {
        guard let current = child, current.primary == nil, let exit = current.exit, untaken == 0 else { return }
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

extension Run.Output {
    /// Pulls the next chunk and tells Run the size of the one before.
    public struct Iterator: AsyncIteratorProtocol {
        var chunks: AsyncStream<[UInt8]>.Iterator
        weak var run: Run?
        /// The chunk last handed over is the consumer's until it comes back for the next.
        var holding = 0

        /// The next chunk, or nil once Run is released and every chunk read before then is taken.
        public mutating func next() async -> [UInt8]? {
            if holding > 0 { run?.taken(holding) }
            let chunk = await chunks.next()
            holding = chunk?.count ?? 0
            return chunk
        }
    }
}
