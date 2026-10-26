---
created: 2026-10-26
status: draft
type: ho-document
project: issoku
ho: "02"
kamae: 5
shape: ha
phase: 1 — The Process Model
title: Run — the production process model
description: The headless Run component in IssokuCore, built from the spike's answers and specified by its tests, with a command-line driver for the practitioner's run sheet against real hosts.
builds-on:
  - kamae-1-issoku-seed
  - kamae-2-issoku-system-design
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-01-the-spike.md
  - ho-process/hos/ho-01-spike-findings.md
  - ho-process/hos/ho-01.1-fix-pass.md
  - ho-process/audits/ho-01-efficiency-audit.md
model: claude-opus-5-5
opening-hash: 1e6c2dbaa84d0128c9c9a36216f7440b241959e3
---

# ho-02 — Run

This session builds Run, the one component that touches processes: it captures the login environment once, launches a command under a pseudoterminal in its own process group, streams the bytes out, carries keystrokes in, interrupts, kills, reports the exit, and computes the `-tt` retry offer. Run lives in `IssokuCore`, depends on nothing else in the app, and is specified by its tests. The spike under `spike/` is deleted in this ho's first commit; what it proved is carried over as code, not as a reference.

**Out of scope:** rendering of any kind (ho-04); any window, panel, or hotkey (ho-03); settings storage (ho-05); the Transcript buffer and its ceiling (ho-04); a terminal emulator; any rewriting of the typed line beyond the one `-tt` insertion.

**Resolves deferred decisions** (from the System Design and the overview's ho-02 entry):
- Environment capture: the invocation, which variables are kept, and that Refresh Environment waits while a command is running.
- The sudo message: the exact text matched for the retry offer, with sudo's real output as a test fixture, and the rule that the typed line must begin with `ssh ` and not already carry `-t`.

**Every command this ho runs against a host reads. None writes.** Automated tests never touch a live host (CLAUDE.md hard rule). The practitioner's run sheet in Execute, part H, runs against real hosts; every command on it is read-only and the sudo password is typed by the practitioner and by no one else.

**Tight.** The seed's constraint applies to this ho in full and the subagent's brief carries it: no abstraction with one implementation, no generic layer, no configuration surface, no second execution path, no state held in two places. Run's source is expected to come in at or under the spike harness's size (432 nonblank lines across six files); if it comes in larger, the orchestrator sends it back with the excess named.

---

## Phase 1 — Think

Eight decisions, settled 2026-10-26 between the practitioner and the orchestrator. Decisions 1 and 2 are the two the System Design assigned here; the rest fix the shape of the work so the subagent has nothing architectural left to decide.

### Decision 1 — Environment capture: the login shell once, everything it yields, `TERM` supplied if absent

**Invocation.** The login shell is read from the password database entry for the current uid (`getpwuid(getuid())`, `pw_shell`). The capture runs `<shell> -l -c 'env -0'` from the app's own environment, with stdin from `/dev/null` and stdout to a pipe, and must finish within five seconds. This is the spike's Decision 3 invocation unchanged; ho-01 recorded what it yields under a terminal parent and under a scrubbed one.

**What is kept.** Every variable the capture prints, except the three the capture itself produces and that carry nothing of the user's: `_`, `SHLVL`, `OLDPWD`. `PWD` is not kept either; the working directory is set per command from Panel's argument, and the shell sets `PWD` from it. Nothing else is filtered: the environment is the user's own, and filtering it would be a policy no requirement asks for.

**What is added.** `TERM=xterm-256color`, only when the capture yielded no `TERM`. ho-01 found a GUI-style launch has no `TERM`; without it programs refuse colour or print "not a terminal" warnings, and Transcript renders SGR colour. Nothing else is added. `COLUMNS` and `LINES` are not set; the window size goes through the pseudoterminal (Decision 3).

**Failure.** If there is no login shell, the shell exits non-zero, or the five seconds pass, the capture throws a typed error naming which. Run keeps the environment it had: at first launch that is the app's own process environment, the fallback a GUI app has and the one the spike's scrubbed run proved still authenticates to the LAN hosts. The caller (ho-03) decides what to show.

**Refresh.** `refreshEnvironment()` on Run is asynchronous. While a command is running it waits for Done, then captures, then replaces the stored environment. It never captures concurrently with a running command and never interrupts one.

### Decision 2 — The sudo message: the first clause, four guards, one insertion

**Fixture.** sudo's refusal when it has no terminal, captured 2026-10-26 from host-a (`sudo 1.9.13p3`) by `ssh host-a 'sudo true'` with no terminal allocated, exit status 1, 164 bytes, two lines:

```text
sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper
sudo: a password is required
```

The bytes go into the test target verbatim as `Tests/IssokuCoreTests/Fixtures/sudo-no-terminal.txt`. The fixture contains no host, user, or address.

**Match.** The output contains the ASCII bytes `sudo: a terminal is required to read the password`. Only that clause: the text after the semicolon has changed across sudo releases and the fixture is one release. The match is on the bytes Run streamed, across chunk boundaries, so Run keeps the last clause-length bytes of the previous chunk when it scans the next one.

**Guards, all four required.** The exit is non-zero. The clause appeared. The typed line, after leading whitespace is dropped, begins with `ssh ` (the four bytes `s s h space`). No whitespace-separated word after `ssh` begins with `-` and contains the letter `t` before any character that is not a letter: `-t`, `-tt`, `-At`, `-tA` all count as carrying `-t`; `-o`, `-p`, `-4`, and anything not beginning with `-` do not. `-o RequestTTY=yes` is not recognised; a user who writes that has already asked for a terminal and gets the offer anyway, which relaunches harmlessly. The guard stops at the end of the line, not at the destination, because finding the destination would be a parser and the seed forbids one.

**Transformation.** Insert the six bytes `-tt ` after the leading `ssh ` of the trimmed line, once. The rest of the line is untouched, byte for byte. There is no other transformation anywhere in Run.

**Shape.** One pure function, `Retry.offer(line:exit:sawSudoRefusal:) -> String?`, and one byte scanner that sets `sawSudoRefusal`. Run's Done state carries the result as `retry: String?`; Panel reads it and draws the offer. Run never knows Panel exists. A line typed with `-tt` by hand never produces an offer, by the fourth guard.

### Decision 3 — Run's shape: one actor, two streams, the spike's spawn with a real window size

**Type.** `public actor Run` in `IssokuCore`. Interface, exactly as the System Design lists it:

- `init(environment: [String: String] = ProcessInfo.processInfo.environment)`
- `func start(line: String, cwd: String, size: WindowSize = WindowSize(columns: 80, rows: 24)) throws` — throws `RunError.alreadyRunning` if a command is alive, and the spawn error if `forkpty` fails. One process at a time, as the System Design commits.
- `func interrupt()` — `killpg(pgid, SIGINT)`.
- `func kill()` — `killpg(pgid, SIGKILL)`.
- `func write(_ bytes: [UInt8])` — keystrokes to the pseudoterminal master, all of them, never echoed, never stored.
- `func resize(_ size: WindowSize)` — `TIOCSWINSZ` on the master; the kernel sends the child `SIGWINCH`. ho-04 calls it when the transcript's width is known.
- `func refreshEnvironment() async throws` — Decision 1.
- `let bytes: AsyncStream<[UInt8]>` — every chunk read from the master, in order, unmodified.
- `let states: AsyncStream<RunState>` — `.running(pid:)` after a successful start, `.done(Exit, retry: String?)` after the child is reaped.
- `enum Exit: Sendable, Equatable { case status(Int32); case signal(Int32) }`.

The two streams are created once with Run and live as long as it does; each has one consumer (Transcript, Panel). Values are plain `Sendable` types. No delegate, no protocol with one conformer, no callback registry.

**Spawn.** The spike's `spawnUnderPTY` and `execInChild` are copied into `Sources/IssokuCore/Run/PTY.swift` with one change: `forkpty` receives a `winsize` built from `size` instead of nil, so the child sees a real terminal size from its first instruction. Everything else is as proven: argv and envp allocated before the fork; between fork and exec the child calls only `signal`, `sigemptyset`, `sigprocmask`, `execve`, `_exit`; every signal disposition reset to default and the mask cleared, because exec preserves an ignored disposition. The child is `<shell> -c <line>` with `shell` from the password database, exactly `environment` and nothing inherited, and the working directory from `cwd` (`chdir` in the child before `execve` is permitted; it is async-signal-safe).

**Reading and reaping.** A dispatch read source on the master fd delivers chunks to `bytes`. A dispatch process source on the child's pid (`DispatchSource.makeProcessSource`, `.exit`) triggers `waitpid`; the exit status or terminating signal becomes `Exit`; the master is closed after the read source has drained; then `.done` is emitted with the retry offer from Decision 2. Done means the child Run spawned has been reaped. What the pseudoterminal's hang-up does to anything the child left behind is Discovery, below.

**Concurrency.** Strict concurrency, language mode 6. The fd and pid live inside the actor; the dispatch sources hop back into it to publish. No `@unchecked Sendable`, no `nonisolated(unsafe)`, no force unwrap without a `// FORCE:` comment, no lint suppression without a comment naming why.

### Decision 4 — Tests: local processes only, the process table as witness, no sshd fixture

Automated tests never touch a live host. Everything Run does is exercised with local processes, the sudo fixture, and a fake `ssh` on a test-controlled `PATH`:

- **Launch and environment (core interaction step 3).** A child that prints `tty` and `ps -o pid,pgid,sess -p $$` proves the pseudoterminal is the controlling terminal and the child leads a new group. A child that prints `env` proves it sees exactly the environment Run was given, and `TERM` when the given environment lacked it.
- **Failure and the offer (step 4).** The test writes a fake `ssh` script into a temporary directory: it prints the fixture to stderr and exits 1 unless its first argument is `-tt`, in which case it prints `ok` and exits 0. Run is started with an environment whose `PATH` is that directory alone and the line `ssh host 'sudo true'`. Done carries exit status 1 and `retry: "ssh -tt host 'sudo true'"`.
- **Retry (step 5).** Starting the offered line against the same fake `ssh` ends with status 0 and no offer.
- **Keystrokes (step 6).** A child that runs `stty -echo; read -r secret; echo "length ${#secret}"`; the test writes `hunter2\n` through Run; the byte stream contains `length 7` and never the bytes `hunter2`. This is the "nothing typed is drawn" rule: Run writes to the master and the child's terminal, with echo off, returns nothing.
- **Exit (step 7).** `exit 3` arrives as `.status(3)`; a child killed by `kill()` arrives as `.signal(9)`.
- **Termination and orphans.** `sh -c 'sleep 300 & sleep 300 & wait'` interrupted; `sh -c 'trap "" INT; sleep 300'` interrupted, observed alive, then killed. After each, the test reads the process table itself (`ps -o pid= -g <pgid>`, retried for up to two seconds) and asserts it is empty. The test never trusts Run's own report for the orphan assertion (ho-02x asks exactly this).
- **One at a time.** A second `start` while running throws `alreadyRunning`; after Done it succeeds.
- **Refresh waits.** `refreshEnvironment()` requested during a running `sleep 1` completes only after Done, shown by ordering.
- **Capture.** `LoginEnvironment.capture` against a fake shell on `PATH` that prints a known `env -0` block, including a case that omits `TERM`, a case that exits non-zero, and a case that sleeps past the timeout.
- **The retry function alone.** Table-driven over lines: `ssh h cmd`, `  ssh h cmd` (leading space), `ssh -tt h cmd`, `ssh -At h cmd`, `ssh -o Foo=bar h cmd`, `sshfs h`, `scp h`, with exit 0 and exit 1, with and without the clause.
- **ssh's own status.** `ssh -p 1 -o ConnectTimeout=2 -o BatchMode=yes 127.0.0.1 true` ends with `.status(255)` and no offer. This touches no host.
- **Multithreaded parent.** One test starts Run from a detached task while the test runner's other threads are live, proving `forkpty` from a multithreaded process reaches exec (the audit's item 6).

No local `sshd` fixture. The remote behaviours (`-tt` carries the interrupt, the remote survives without it, 255 is ssh's own) are proven in ho-01's findings and belong to ssh, not to Run; a fixture would be a second thing to maintain for no new assertion. The overview's "against real hosts where not" clause is satisfied by the practitioner's run sheet, part H, not by tests. The practitioner's ruling, 2026-10-26.

**Coverage.** The floor is 90% on `IssokuCore`. The lines between fork and exec run in the child, which execs and never reports, so they are uncoverable by construction; they are kept in one function, `execInChild`, with a comment saying so. They are the only intended uncovered lines.

### Decision 5 — Files: four source files, one driver, fixtures beside the tests

```text
Sources/IssokuCore/Run/Run.swift               the actor, the streams, Done
Sources/IssokuCore/Run/PTY.swift               spawnUnderPTY, execInChild, WindowSize
Sources/IssokuCore/Run/LoginEnvironment.swift  capture, the three dropped names, TERM
Sources/IssokuCore/Run/Retry.swift             the clause, the scanner, Retry.offer
Sources/IssokuRunCLI/main.swift                the driver (Decision 8)
Tests/IssokuCoreTests/RunTests.swift
Tests/IssokuCoreTests/LoginEnvironmentTests.swift
Tests/IssokuCoreTests/RetryTests.swift
Tests/IssokuCoreTests/Fixtures/sudo-no-terminal.txt
```

The spike is deleted in this ho's first commit (ho-01 Decision 1). `spike/captures/` is gitignored and stays on disk as the practitioner's evidence; the `.gitignore` line stays. ho-01x's reproduction commands remain valid at ho-01.1's closing commit.

`Package.swift` changes: the test target gains `resources: [.copy("Fixtures")]`; a third product, the executable `issoku-run` from target `IssokuRunCLI`, depending on `IssokuCore`. No dependency is added. `scripts/coverage-floor.sh` adds `Sources/IssokuRunCLI/` to its ignore pattern with a comment: it is a driver, excluded like the surface.

### Decision 6 — One Opus subagent, no agent-task files

The seams (environment, spawn and streams, retry, driver) are real but small, and they share one test file's fixtures. One subagent builds them in the order of Decision 5, with this document as its whole instruction. No `ho-process/agent-tasks/` files.

### Decision 7 — No split unless the subagent halts on size

The overview's reserve split (ho-02.1 launch and termination; ho-02.2 environment and retry) is not taken. If the subagent halts on size, the orchestrator stops and the practitioner rules.

### Decision 8 — A driver for the run sheet: `issoku-run`

Run is a library and the panel does not exist until ho-03, so the practitioner has no way to run Run against a real host. A command-line driver, `Sources/IssokuRunCLI/main.swift`, is the spike's `main.swift` distilled over the production Run and nothing more:

```bash
.build/debug/issoku-run [--env] -- <command line>
```

- Captures the login environment through `LoginEnvironment.capture`; with `--env`, prints the variable names and their count, never a value, and exits.
- Starts Run with the line, the current directory, and the terminal's own window size.
- Puts the terminal in raw mode while Running, forwards stdin bytes to `Run.write`, writes the byte stream to stdout unmodified, restores the terminal on every exit path.
- Control-C arrives as `SIGINT` (the driver keeps `ISIG` on, as the spike did) and calls `interrupt()`; a second `SIGINT` calls `kill()`. This is Panel's Stop and second-Stop, so the practitioner exercises the same two paths.
- On Done prints one line to stderr, `issoku-run: exit <n> | signal <n>` and, when there is an offer, a second line `retry: <line>`, then exits with the status (or 128 plus the signal).

It exists for this ho only. ho-03's first commit deletes `Sources/IssokuRunCLI/` and the `issoku-run` product, as ho-02's first commit deletes the spike, so nothing extra remains once the panel can drive Run. It is excluded from the coverage floor and has no tests of its own; its correctness is the run sheet. It renders nothing: raw bytes to a real terminal, which is why the practitioner reads the output in Ghostty or Terminal.app, not through a plain model. Practitioner's ruling, 2026-10-26: build it for the run sheet, delete it at ho-03.

### Discovery (deferred to execution) — two things only the run can show

- **What the pseudoterminal's hang-up does to a backgrounded grandchild after a normal exit.** `sh -c 'sleep 300 & exit 0'`: the child exits, Run reaps it and closes the master. The session leader is gone and the terminal is closing, so the kernel should deliver `SIGHUP` to the remaining group. The test records whether the `sleep` survives, and no code is written for the answer either way: the hang-up is the kernel's, the same one a closing terminal window gives, and that is the seed's rule. Practitioner's ruling, 2026-10-26: record it, build nothing.
- **The driver's raw-mode interaction with `swift run`.** If `swift run issoku-run` interposes anything on the terminal, the run sheet uses the built binary path directly. Recorded, not worked around.

---

## Phase 2 — Execute

One subagent, in the order of Decision 5, test first for each file.

### Files

The subagent creates or modifies only:

| Path | Action |
|---|---|
| `Sources/IssokuCore/Run/Run.swift` | create |
| `Sources/IssokuCore/Run/PTY.swift` | create |
| `Sources/IssokuCore/Run/LoginEnvironment.swift` | create |
| `Sources/IssokuCore/Run/Retry.swift` | create |
| `Sources/IssokuRunCLI/main.swift` | create |
| `Tests/IssokuCoreTests/RunTests.swift` | create |
| `Tests/IssokuCoreTests/LoginEnvironmentTests.swift` | create |
| `Tests/IssokuCoreTests/RetryTests.swift` | create |
| `Tests/IssokuCoreTests/Fixtures/sudo-no-terminal.txt` | create, bytes exactly as in Decision 2 |
| `Package.swift` | test resources; the `issoku-run` product and target; nothing else |
| `scripts/coverage-floor.sh` | add `Sources/IssokuRunCLI/` to the ignore pattern, with the comment |

The orchestrator, not the subagent, does:

| Path | Change |
|---|---|
| `spike/` | `git rm -r` in the ho's first commit |
| `ho-process/hos/ho-02-run.md` | Reflect, status, frontmatter at close |
| `ho-process/kamae-4-issoku-ho-overview.md` | build-record entry |
| `ho-process/kamae-6-issoku-state-memory.md` | state-summary block |
| `metadata/ho-status.md`, `metadata/ho-status.json` | roster |

### Rules for the subagent

- No commits. The orchestrator commits.
- No files outside the table above. Nothing under `Sources/Issoku/`.
- No dependencies, in `Package.swift` or anywhere. No C target; `forkpty`, `openpty`, `ioctl`, and `killpg` are reachable from `import Darwin`, as the spike proved.
- No architectural decisions. If this document and the System Design do not answer a question, halt and report the question. Do not pick.
- No test touches a live host. The only network call in the suite is the closed local port in Decision 4.
- No test reads the test process's stdin. No test or source logs, stores, or echoes anything written through `Run.write`.
- Never `pkill` or `killall` by pattern, in a test or by hand. Tests kill by pid or pgid they own.
- Tight: no protocol with one conformer, no generic over one type, no configuration struct for values that never vary, no manager, no helper that wraps one call. If a type exists to be mocked, delete it and test the real thing.
- Report back with: every file written, every command in Verification with its full output, the coverage number, and the Discovery results.

### Verification

Run from the repository root, in this order, all green before reporting:

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
swift test --enable-code-coverage && scripts/coverage-floor.sh
swift build -c release
```

The orchestrator then reads the whole diff, runs the stack again, runs `pre-commit run --all-files` with the ho-02 paths staged, sweeps for secrets and real names, and commits.

### H. The practitioner's run sheet (after the orchestrator's verification, before close)

From the repository root, in a real terminal, with `swift build` done. `R` is `.build/debug/issoku-run`. Every command reads. Record the output and the status line of each.

1. `R --env` — names and count only. Expect `SSH_AUTH_SOCK` present when launched from a terminal, `TERM` present either way.
2. `R -- uptime` — local, exit 0.
3. `R -- 'ssh host-a uptime'` — remote, exit 0.
4. `R -- 'ssh host-a "sudo true"'` — sudo refuses with the fixture's two lines, exit 1, and the driver prints `retry: ssh -tt host-a "sudo true"`.
5. `ssh -tt host-a sudo -K`, then `R -- 'ssh -tt host-a "sudo true"'` — the prompt appears, the password is typed, nothing echoes, exit 0.
6. `ssh -tt host-a sudo -K`, then as 5 with a wrong password three times — exit 1.
7. `R -- 'ssh -tt host-a "sudo smartctl -H /dev/sdb"'` — the health line, readable, exit 0 (no prompt: smartctl is NOPASSWD on host-a).
8. `R -- 'ssh -tt host-a "sleep 300"'`, Control-C once — ssh ends, status 255. Then `ssh host-a 'pgrep -af "sleep 300"'` shows only the foreign `sleep 300` that always runs there. Never `pkill` it.
9. `R -- 'sh -c "trap \"\" INT; sleep 300"'`, Control-C once (survives), Control-C again — signal 9, and `ps -o pid= -g <pgid>` empty.
10. `R -- 'ssh -o ConnectTimeout=3 192.0.2.1 uptime'` — timeout text, status 255, no offer.

The practitioner pastes the transcripts; the orchestrator records them in Reflect with host names redacted per the project's map.

### Done means

- The core interaction's steps 3 through 7 pass as tests with no UI, as listed in Decision 4.
- No orphan after interrupt and after force-kill, asserted by a test that reads the process table; the normal-exit grandchild case recorded as Discovery.
- The retry rule's fixture is sudo's real bytes, and the table-driven test covers every guard.
- `IssokuCore` line coverage at or above 90%, with `execInChild` the only intended uncovered lines.
- The six verification commands pass with output recorded; no warning suppressed, no force unwrap without `// FORCE:`.
- Run's source at or under the spike harness's size, or the excess named and accepted.
- The run sheet's ten items recorded, including the practitioner's three sudo runs.
- Two commits on `main`: `ho-02: run — open; delete the spike` (this document, the spike removal) and `ho-02: run — the production process model` (everything else, the build-record entry). No trailers.
- The closing hash is recorded; ho-02x is authored from the x template over `ee95ee7`'s successor range, `<open commit>..<close commit>`.

---

## Phase 3 — Reflect

*To be filled in after execution.*

- **Did the design hold?** Where did the real processes surface things the Think phase did not anticipate?
- **The Discovery results.** The grandchild after a normal exit; the driver under `swift run`.
- **The run sheet.** The practitioner's ten transcripts, redacted.
- **Size.** Run's line count against the spike's, and what the difference is.
- **For ho-03 and ho-04.** Facts only: what Panel must call and in what order; what Transcript receives and when `resize` should be called. ho-03's first commit deletes `Sources/IssokuRunCLI/` and the `issoku-run` product.
