---
created: 2026-10-25
status: complete
type: ho-document
project: issoku
ho: "01"
kamae: 5
shape: ha
phase: 1 — The Process Model
title: The Spike — prove the pseudoterminal process model
description: A throwaway command-line harness that answers the six process-model decisions the System Design deferred, with evidence recorded in a findings document that ho-01x reviews.
builds-on:
  - kamae-1-issoku-seed
  - kamae-2-issoku-system-design
  - kamae-4-issoku-ho-overview
  - ho-process/hos/ho-00-orientation.md
model: claude-opus-5-5
opening-hash: ee95ee71f25877574df7302f5e88e8908e6458eb
---

# ho-01 — The Spike

This session builds a command-line harness under `spike/`, outside the package the app is built from, and runs it against real commands and real hosts to answer the six decisions the System Design assigned here: spawn mechanism, process ownership, failure legibility, memory ceiling, latency, and terminal-control depth. The harness is discarded by ho-02. What survives is `ho-process/hos/ho-01-spike-findings.md`, one section per decision, each with an answer, the evidence behind it, and the exact commands that reproduce it. ho-01x reads that document and nothing else.

**Out of scope:** reusable code; anything under `Sources/` or `Tests/`; any UI; error presentation beyond what the harness prints; environment-capture policy (which variables are kept is ho-02's decision — this ho records what the capture yields); the `-tt` retry rule (ho-02); the Transcript buffer's real ceiling (ho-04).

**Resolves deferred decisions** (from the overview's ho-01 entry):
- Spawn mechanism
- Process ownership
- Failure legibility
- Memory ceiling
- Latency
- Terminal-control depth

**Every command in this ho reads. None writes.** No `brew upgrade`, no `systemctl restart`, no `git pull`, no `zfs` or `zpool` verb other than `status` and `list`, no file written on any host. The sudo criterion uses `sudo true` and `sudo smartctl -H`, which change nothing. The practitioner's ruling, 2026-10-25: the subagent may run `ssh` against the real hosts for the commands this spec lists; nothing destructive, ever. This revises the project CLAUDE.md hard rule that only the practitioner drives remote runs; the amended rule is in the Execute phase under Files.

---

## Phase 1 — Think

Eleven decisions, settled 2026-10-25 between the practitioner and the orchestrator. The overview wrote the six questions; these decisions fix how the harness asks them so the evidence is clean.

### Decision 1 — `spike/` is committed: yes, as its own package, deleted by ho-02

The harness lives at `spike/` with its own `spike/Package.swift`: one executable target `issoku-spike`, `swiftLanguageModes: [.v6]`, `StrictConcurrency` enabled, no dependencies. The root package never references it, so `swift build` at the root does not compile it; the hooks' `Sources Tests` scope and SwiftLint's `included:` list never lint it. It is committed at this ho's close so that ho-01x can rerun every command in the findings document from the closing commit. ho-02's spec deletes `spike/` in its first commit. No tests on the harness: it is throwaway by design, and the evidence is the transcripts, not a suite. A C target inside `spike/` is permitted if a POSIX declaration is not reachable from `import Darwin`; that is a shim, not a dependency.

### Decision 2 — Spawn candidates: `forkpty` first, `posix_spawn` with `POSIX_SPAWN_SETSID` second

`forkpty` opens the pair, forks, calls `setsid`, and makes the slave the controlling terminal in one call. The harness tries it first. The second candidate, `posix_spawn` with the `POSIX_SPAWN_SETSID` and `POSIX_SPAWN_SETPGROUP` attribute flags and the slave opened as the child's three standard descriptors through file actions, is built only if `forkpty` fails the sudo criterion. Whichever is chosen, the findings record for ho-02 whether the path calls `fork`, because ho-02 spawns from a multithreaded GUI process and the harness is a single-threaded CLI; the spike does not resolve that, it names it.

Before any remote command, the harness proves its own claim with a local probe: `sh -c 'tty; ps -o pid,pgid,sess,tty -p $$'` must print a `/dev/ttys*` device and a process group id equal to the child's pid. That line is the evidence that the PTY is the controlling terminal and the group is new.

### Decision 3 — Environment: captured from the login shell, invocation recorded, policy deferred

At start the harness reads the login shell from `getpwuid(getuid())`, runs it as `<shell> -l -c 'env -0'`, parses the result into a dictionary, and spawns every command with that dictionary and nothing inherited. The invocation and the variable names it yields are recorded as evidence. Which variables ho-02 keeps is ho-02's decision.

The sudo criterion runs twice: once from the terminal, as a control, and once with the harness launched under a scrubbed parent (`env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin`), which approximates what launchd hands a GUI app. The findings record the variables present in each capture, whether `SSH_AUTH_SOCK` is among them under the scrubbed launch, and whether `ssh host-a` authenticates under it. That is the evidence ho-02 needs and the spike does not interpret it beyond stating it.

### Decision 4 — Harness stdin: raw mode when it is a terminal, not forwarded when it is not

When the harness's stdin is a terminal it is switched to raw mode with local echo off for the life of the child and restored on every exit path, including signals. Every byte read is written to the PTY master and nowhere else; the harness never logs, captures, or prints its own stdin. Any character that appears on screen therefore came back from the child, which makes "nothing echoes" an observation. When stdin is not a terminal (the subagent's runs), nothing is read from it and nothing is forwarded.

### Decision 5 — Interrupt and kill: signals to the harness, `killpg` to the group

`SIGINT` delivered to the harness sends `SIGINT` to the child's process group with `killpg`. `SIGTERM` delivered to the harness sends `SIGKILL` to the group. The harness never exits before it has reported the child's status; after a force-kill it reports the signal. Both are driven from a second shell with `kill -INT` and `kill -TERM` against the harness pid, which is what makes the test scriptable and reproducible. The harness never forwards `0x03` as a keystroke; Run sends `SIGINT` to the group, so that is what the spike tests.

Orphan checks follow every termination test. Locally: `ps -o pid,pgid,ppid,stat,command -g <pgid>` must print nothing. Remotely: `ssh <host> 'pgrep -af "sleep 300"'` must print nothing. The remote test runs with `-tt` and without, because closing the local `ssh` hangs up a remote pseudoterminal but does nothing to a remote process that was never given one; the findings record both outcomes as facts for ho-02.

### Decision 6 — Memory: a 10,000-line ring buffer, fixed read buffer, peak resident size measured

The harness reads the master into a fixed 64 KiB buffer and keeps the last 10,000 lines in a ring, standing in for Transcript's ceiling. The number is a stand-in; ho-04 sets the real one. Memory is measured from outside with `/usr/bin/time -l`, whose "maximum resident set size" line is the number recorded, for fifty megabytes produced locally and fifty megabytes produced remotely. The pass condition is that the figure does not scale with the output: the findings also record the same measurement for one megabyte, and the two must be within the same order.

**Amended during execution, 2026-10-25.** The first run showed a line-count ring is not a byte ceiling: macOS `base64` emits fifty megabytes as one unbroken line, and the ring held it whole (174.5 MB peak against 10.0 MB for one megabyte). The ring now also caps the line in progress at 1 MiB, dropping its oldest bytes, in both the raw path and the plain model. Items 14 to 16 run again; the findings record both runs, the first as the fact that a line ceiling alone does not bound memory, the second as the ceiling holding. How Transcript treats an over-long line (truncate or wrap) is ho-04's decision; the spike shows only that a byte cap holds.

### Decision 7 — Latency: monotonic timestamps, five runs, conditions named

The harness takes `ContinuousClock` instants immediately before the spawn call, at the first byte read from the master, and at the exit report, and prints the two intervals in milliseconds on its status line. Five runs each for local `uptime` and for `ssh <host> uptime` against host-a, host-b, and host-c. The findings report all five values and the median per case, name the machine, the network path to each host (LAN or Tailscale, from `~/.ssh/config` and the Tailscale status), and whether `ControlMaster` is set in the practitioner's SSH config, since a multiplexed connection would make the remote number a different measurement. Hotkey-to-panel latency has no panel to measure yet and is ho-03's.

### Decision 8 — Terminal-control: a plain-text model of what Transcript will show

Writing the child's bytes to a real terminal would let the terminal render every sequence and hide the question. The harness therefore has a `--plain` mode that models the minimal handling the System Design commits to: SGR sequences (`ESC [ … m`) pass through unchanged; every other escape sequence (other CSI finals, OSC, single-character ESC sequences) is removed; a carriage return rewinds the current line so later bytes overwrite from column zero; a line feed commits the line. Only committed lines and the final partial line are written. What appears is what Transcript would show, colours aside. The practitioner judges each command's output as readable or not; the list of unreadable commands is the finding, and an empty list is a finding.

Every run writes the child's raw bytes to `spike/captures/<name>.raw`, gitignored, so the sequences that occurred can be tabulated. The findings include a table of distinct non-SGR sequences seen per command, which is ho-04's input for "stripped versus honoured".

### Decision 9 — Failure cases: three commands, status and last lines recorded

- Unreachable host: `ssh -o ConnectTimeout=3 192.0.2.1 uptime` (a reserved documentation address that never answers).
- Rejected key: `ssh -F /dev/null -o HostKeyAlias=host-a.lan -o IdentitiesOnly=yes -o IdentityFile=/dev/null -o BatchMode=yes <user>@<lan-ip-a> uptime`. **Amended during execution, 2026-10-25:** the first form, without `-F /dev/null`, authenticated, because a command-line `IdentityFile` adds to the identities `~/.ssh/config` names rather than replacing them. `-F /dev/null` drops the config, so the host, user, and host-key alias are given explicitly.
- Wrong sudo password: `ssh -tt host-a 'sudo true'` with the practitioner typing a wrong password three times.

For each, the findings record the exit status and the final lines. ssh exits 255 for its own failures and passes a remote command's status through unchanged, so a remote command that itself exits 255 cannot be told from an ssh failure by the status alone. **Corrected in ho-01.1, 2026-10-25:** this sentence first said that anything other than 255 is the remote command's and implied the converse; ho-01x run 1 (M2) returned it. The three must be distinguishable from the status and the text together; that is the criterion.

### Decision 10 — Who runs what: one subagent runs everything except the password

One Opus subagent builds the harness and runs the whole run sheet below, local and remote, including `ssh` to host-a, host-b, and host-c for the read-only commands listed. The subagent cannot type the practitioner's password, so the three sudo runs (control, scrubbed, wrong password) are the practitioner's: the subagent prepares the exact invocations, the practitioner runs them in a terminal and hands back the transcripts and capture excerpts, and the subagent writes them into the findings. No separate agent-task files; this document is the subagent's instruction.

### Decision 11 — The real command set

The practitioner's list, 2026-10-25, every item read-only. The practitioner may add to it during the run; additions are recorded in the findings.

| # | Command | Where | Exercises |
|---|---|---|---|
| 1 | `uptime` | local | baseline, latency |
| 2 | `df -h` | local | columns |
| 3 | `ls -G ~` | local | SGR colour |
| 4 | `brew update` | local | progress output, carriage returns |
| 5 | `brew outdated` | local | plain lines |
| 6 | `diskutil info disk0` | local | columns, no sudo |
| 7 | `git -C ~/Vaults/sageframe-no-kaji-dev/issoku status` | local | colour, plain |
| 8 | `ping -c 3 host-a` | local | timed lines |
| 9 | `ssh host-a uptime` | host-a | latency |
| 10 | `ssh host-a 'zpool status pool-a'` | host-a | the pool the practitioner connects to; columns |
| 11 | `ssh host-a 'zfs list -r pool-a'` | host-a | columns |
| 12 | `ssh host-a 'zpool list'` | host-a | columns |
| 13 | `ssh -tt host-a 'sudo smartctl -H /dev/sdb'` | host-a | disk health, sudo with password (practitioner) |
| 14 | `ssh host-b uptime` | host-b | latency |
| 15 | `ssh host-b 'docker ps --format "table {{.Names}}\t{{.Status}}"'` | host-b | table output |
| 16 | `ssh host-b 'zpool status rpool'` | host-b | columns |
| 17 | `ssh host-c uptime` | host-c | latency, Tailscale path |
| 18 | `ssh host-c 'docker ps --format "table {{.Names}}\t{{.Status}}"'` | host-c | table output |
| 19 | `ssh host-c 'systemctl status docker --no-pager'` | host-c | colour, bullet glyph, UTF-8 |
| 20 | `ssh host-c 'journalctl -u docker -n 20 --no-pager'` | host-c | plain lines, UTF-8 |

### Discovery (deferred to execution) — three things only the run can show

- **What the login-shell capture yields under a scrubbed parent.** Especially `SSH_AUTH_SOCK`, `PATH`, and anything `.zprofile` exports. Recorded as a variable list, not interpreted.
- **Whether a remote process survives the local kill without `-tt`.** Expected yes; recorded either way.
- **Which non-SGR sequences the command set emits.** Tabulated from the raw captures.

---

## Phase 2 — Execute

One subagent, two halves: build and run, then write the findings once the practitioner's three sudo transcripts are in hand.

### The harness

`spike/Package.swift` declares one executable target, `issoku-spike`, sources under `spike/Sources/IssokuSpike/`. File layout within that directory is the subagent's, with the constraint that the spawn path, the plain-text model, and the ring buffer are each readable in one place. Invocation:

```bash
spike/.build/release/issoku-spike [--plain] [--capture <path>] -- <command line>
```

- `<command line>` is one argument, passed to the login shell as `<shell> -c <line>` with the captured environment, under the PTY, in a new process group, with the working directory inherited.
- `--plain` renders through the model in Decision 8; without it, bytes pass through unchanged.
- `--capture <path>` writes the child's raw bytes to the path; never the harness's stdin.
- Exit: the harness prints one status line to stderr and exits with the child's status (or 128 plus the signal number):

```text
spike: exit <n> | signal <n> · spawn→first-byte <ms> ms · spawn→exit <ms> ms
```

- `SIGINT` → `killpg(pgid, SIGINT)`. `SIGTERM` → `killpg(pgid, SIGKILL)`. Terminal state restored on every exit path.
- Built with `swift build -c release --package-path spike`.

### The run sheet

Run from the repository root with the release binary. `T` is `/usr/bin/time -l`. Every run records the full terminal output, the status line, and the capture path. Record each command exactly as run.

**A. Spawn and ownership (subagent)**

1. Probe: `issoku-spike -- 'tty; ps -o pid,pgid,sess,tty -p $$'`.
2. Local interrupt: `issoku-spike -- 'sleep 300' &`, then `kill -INT <harness pid>`; status line; `ps -o pid,pgid,ppid,stat,command -g <child pgid>`.
3. Local ignore-then-force: `issoku-spike -- 'sh -c "trap \"\" INT; sleep 300"' &`, `kill -INT`, observe it survives, `kill -TERM`, status line, orphan check as in 2.
4. Remote interrupt with a pty: `issoku-spike -- 'ssh -tt host-a "sleep 300"' &`, `kill -INT`, status line, local orphan check, `ssh host-a 'pgrep -af "sleep 300"'`.
5. Remote ignore-then-force with a pty: `issoku-spike -- 'ssh -tt host-a "trap \"\" INT; sleep 300"' &`, `kill -INT`, `kill -TERM`, status line, both orphan checks.
6. Remote without a pty: `issoku-spike -- 'ssh host-a "sleep 300"' &`, `kill -INT`, status line, both orphan checks. If the remote `sleep` survives, `ssh host-a 'pkill -f "sleep 300"'` cleans it up and the survival is recorded.

**B. The sudo criterion (practitioner at the keyboard)**

7. Control: `issoku-spike --capture spike/captures/sudo-control.raw -- 'ssh -tt host-a "sudo true"'`. Type the password. Expect: the prompt, nothing echoed, exit 0.
8. Scrubbed: `env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin spike/.build/release/issoku-spike --capture spike/captures/sudo-scrubbed.raw -- 'ssh -tt host-a "sudo true"'`. Record whether `ssh` authenticates and, if it does, the same expectations as 7.
9. Wrong password: as 7 with `--capture spike/captures/sudo-wrong.raw`, a wrong password typed three times. Record status and last lines.
10. Disk health (command set item 13): `issoku-spike --plain --capture spike/captures/smartctl.raw -- 'ssh -tt host-a "sudo smartctl -H /dev/sdb"'`.

The evidence for "nothing echoes" is `xxd` of the capture from the prompt to the newline that follows it, showing no password bytes, pasted into the findings. The subagent prepares the exact `xxd` invocation; the practitioner runs it and confirms the excerpt holds nothing but the prompt before it is pasted.

**C. Environment (subagent)**

11. `issoku-spike -- 'env | sort'` from the terminal, and the same under the scrubbed `env -i` launch. Record the variable names (values omitted for anything that looks like a token or a socket path beyond its directory), and the diff of the two lists.

**D. Failure legibility (subagent for 12 and 13; practitioner's run 9 covers the third)**

12. `issoku-spike -- 'ssh -o ConnectTimeout=3 192.0.2.1 uptime'`.
13. `issoku-spike -- 'ssh -F /dev/null -o HostKeyAlias=host-a.lan -o IdentitiesOnly=yes -o IdentityFile=/dev/null -o BatchMode=yes <user>@<lan-ip-a> uptime'` (amended; see Decision 9).

**E. Memory (subagent)**

14. `T issoku-spike -- 'head -c 1000000 /dev/urandom | base64' > /dev/null`.
15. `T issoku-spike -- 'head -c 50000000 /dev/urandom | base64' > /dev/null`.
16. `T issoku-spike -- 'ssh host-a "head -c 50000000 /dev/urandom | base64"' > /dev/null`.
Record the maximum resident set size line from each.

**F. Latency (subagent)**

17. Five runs each: `issoku-spike -- uptime`, `issoku-spike -- 'ssh host-a uptime'`, `issoku-spike -- 'ssh host-b uptime'`, `issoku-spike -- 'ssh host-c uptime'`. Record every status line. Record `grep -i controlmaster ~/.ssh/config` and `tailscale status` for the three hosts.

**G. Terminal-control depth (subagent runs all but 13; practitioner judges)**

18. Each command-set item through `issoku-spike --plain --capture spike/captures/cmd-<n>.raw -- '<command>'`. Save the plain output per command to `spike/captures/cmd-<n>.plain`. The practitioner reads each plain output and marks it readable or unreadable. The subagent tabulates distinct non-SGR sequences per capture with a short script over the raw files (the script lives in `spike/` and is listed in the findings).

### The findings document

`ho-process/hos/ho-01-spike-findings.md`. Frontmatter: `created`, `type: findings`, `project: issoku`, `ho: "01"`, `harness-commit: <hash of the closing commit, filled by the orchestrator>`. Then one section per decision, in the overview's order, each with exactly three parts:

- **Answer** — one paragraph, the decision stated.
- **Evidence** — the transcript, table, or hexdump excerpt. Numbers carry units; hosts and the machine are named; conditions are stated.
- **Reproduce** — the exact commands, copyable, from the repository root at the closing commit.

Followed by three sections of facts for later hos, each a list with no recommendations: **For ho-02** (fork-based or not; the capture invocation and what it yielded; remote survival without `-tt`; the status-255 distinction), **For ho-04** (the non-SGR sequence table; the unreadable list), **Additions to the command set** (anything the practitioner added during the run, or "none"). The document recommends nothing the six decisions did not ask for; ho-01x flags anything that does.

### Files

The subagent creates or modifies only:

| Path | Action |
|---|---|
| `spike/Package.swift` | create |
| `spike/Sources/IssokuSpike/**` | create |
| `spike/<sequence-tabulation script>` | create |
| `ho-process/hos/ho-01-spike-findings.md` | create |

The orchestrator, not the subagent, edits:

| Path | Change |
|---|---|
| `.gitignore` | append under Project-specific: `spike/captures/` with the comment "ho-01 raw captures: evidence excerpts live in the findings document" |
| `CLAUDE.md` | the hard rule "Tests never touch live hosts. The ho-01 spike runs against real hosts only with the practitioner driving and only the commands its spec lists." becomes "Tests never touch live hosts. The ho-01 spike runs against real hosts only the commands its spec lists, every one read-only; the sudo password is typed by the practitioner and by no one else." |
| `ho-process/hos/ho-01-the-spike.md` | Reflect, status, frontmatter at close |
| `ho-process/kamae-4-issoku-ho-overview.md` | build-record entry |
| `ho-process/kamae-6-issoku-state-memory.md` | state-summary block |
| `metadata/ho-status.md`, `metadata/ho-status.json` | roster |

### Rules for the subagent

- No commits. The orchestrator commits.
- No files outside the table above. Nothing under `Sources/`, `Tests/`, or `Package.swift` at the root.
- No dependencies, in `spike/Package.swift` or anywhere.
- Only the commands this spec lists, exactly as listed, against only host-a, host-b, and host-c. Nothing that writes to a host. If a listed command turns out to need sudo, it moves to the practitioner's half; the subagent does not type or script a password, ever.
- No reading of the harness's own stdin into any file, log, or variable that outlives the write to the PTY.
- If `forkpty` is not reachable from Swift, or `POSIX_SPAWN_SETSID` is not declared, halt and report the exact compiler message before adding a C shim.
- If a run produces something off-spec (a host unreachable, a command that hangs past sixty seconds, a result that contradicts an expectation in Decisions 2 through 9), stop that run, record what happened, and report it. Do not work around it.
- Report back with: every file written, every command run with its full output, the status line of every harness run, and the findings document with the practitioner's sections marked `PENDING PRACTITIONER` until the transcripts arrive.

### Verification

The root stack is unchanged by this ho and must still pass; the spike is additionally built in release. Run from the repository root, in this order:

```bash
swift-format lint --recursive --strict Sources Tests
swiftlint lint --strict
swift build
swift test
swift test --enable-code-coverage && scripts/coverage-floor.sh
swift build -c release --package-path spike
swift-format lint --recursive --strict spike/Sources
```

The orchestrator then runs `pre-commit run --all-files` with the ho-01 paths staged.

### Done means

- The harness builds in release under language mode 6 with strict concurrency, with no suppressed warnings.
- Every run-sheet item has a recorded transcript, including the practitioner's four.
- The findings document has an Answer, Evidence, and Reproduce for all six decisions; no section says "works" without a transcript, number, or listing under it.
- The sudo criterion is met and shown: prompt, no echo in the hexdump, exit 0.
- The orphan checks after runs 2 through 6 are recorded, empty or not.
- The seven verification commands pass with output recorded.
- One commit on `main`, `ho-01: the spike — prove the pseudoterminal process model`, containing `spike/`, the findings, this document, the CLAUDE.md and `.gitignore` edits, and the build-record entry. No trailers.
- The closing hash is recorded; ho-01x is authored from the x template against the findings document's path.

---

## Phase 3 — Reflect

Filled 2026-10-25, after the run sheet, from `ho-process/hos/ho-01-spike-findings.md`. The findings document carries the evidence; this section carries the reading of it.

**Did the harness design hold?** Two of Decisions 2 through 9 changed during the run, and both forms are recorded in the findings. Decision 6 gained a 1 MiB cap on the line in progress after the first fifty-megabyte run peaked at 174.5 MB: macOS `base64` writes one unbroken line, and a ring that counts lines holds that line whole. Decision 9's rejected-key command gained `-F /dev/null` after the first form authenticated: a command-line `IdentityFile` adds to the identities the SSH config names rather than replacing them. Decision 10 held with two wrinkles. Item 9's first attempt typed the correct password and was rerun after `sudo -k`. Item 10 took no password prompt. **Corrected in ho-01.1:** this paragraph first blamed sudo's credential cache and said the raw captures settled the prompt-through-plain-model question; both were wrong. `smartctl` is permitted without a password for the user on host-a, so item 10 can never prompt, and the plain model as built in ho-01 emitted only at LF, so a prompt would have been invisible until the password was typed (ho-01x run 1, M1). ho-01.1 renders the line in progress and proves it with `sudo true` under `--plain`. Decisions 2, 3, 4, 5, 7, and 8 held as written.

**The spawn path.** `forkpty`, candidate 1, on the first attempt, called through `import Darwin` with no C shim and no warnings in the release build under language mode 6 with strict concurrency. The local probe printed `/dev/ttys001` from `tty`, and `ps` showed the process on that same device with PID equal to PGID: the pseudoterminal is the controlling terminal, the process group is new, and the child leads it. `posix_spawn` was never built.

**The numbers.** Return-to-first-byte medians over five runs: 14.5 ms local, 202.1 ms host-a (LAN), 383.2 ms host-b (LAN), 602.3 ms host-c (Tailscale). The sudo runs saw first bytes between 362 and 542 ms. Peak resident size: 10.0 MB at one megabyte of output; 174.5 MB at fifty megabytes before the line cap; after it, 9,699,328, 9,732,096, and 8,437,760 bytes for items 14, 15, and 16. The cap's cost is time on an unbroken line: item 15 takes 1755.9 ms instead of 394.3 ms, because every read past the cap shifts the kept megabyte.

**The lists.** The unreadable list is empty: nineteen plain captures and run 10's output, all judged readable by the practitioner. Remote survival: without `-tt`, the remote `sleep` survived the local interrupt; with `-tt`, the interrupt reached the remote even with INT trapped, and ssh ended with status 255 before a force-kill could be sent, so the force path was exercised locally only. The scrubbed launch loses `SSH_AUTH_SOCK`, `SHELL`, `TERM`, and `TMPDIR`, and `LANG` is `C.UTF-8` instead of `en_US.UTF-8`; ssh still authenticates, reading the key from disk.

**What the replan checkpoint needs.** Spawn cost: 14.5 ms median from spawn to first byte for a local command, 26 ms to exit for the probe, no shim, no dependency, no warning. Terminal-control list: empty. Across the 24 captures, every escape sequence was SGR, no C0 control other than CR, LF, and TAB appeared, and no carriage return overwrote a line. Whether that cost is one the seed accepts is the checkpoint's call, after ho-01x.

**Followups for ho-02.** Facts only; ho-02's Think phase decides.

- `forkpty` calls `fork`. The app process spawns from a place where that is affordable.
- The spike sets no window size; the child sees 0×0. ho-02 sets a real one.
- Status 255 is ssh's own, for a connection failure and for an interrupt alike. Any other status is the remote command's: sudo's 1 after three wrong passwords came through unchanged.
- `-tt` is what carries an interrupt to the remote command.
- sudo's echo suppression holds through the pseudoterminal: no typed byte appears in any capture. The prompt ends CR LF; ssh's own lines end CR CR LF.
- Capture files are created mode 0600 and the harness never logs its stdin.
- The 1 MiB line cap holds the ceiling and costs about 1.4 s per 50 MB of unbroken line.
- The login-shell environment comes from `<shell> -l -c 'env -0'` through Foundation's `Process`; the subagent's capture included the agent socket under `/var/run/com.apple.launchd.<id>/`.
- A foreign `sleep 300` runs on host-a. Nothing in this project kills processes by pattern.
- `spike/` is deleted by ho-02. The redaction map and the practitioner's real invocations live under the gitignored `spike/captures/` and are copied into the State Memory at this close so they survive the deletion.

**ho-01x run 1 returned this ho** with five Must-fix findings (`ho-process/reviews/ho-01x-report-1.md`); `ho-process/hos/ho-01.1-fix-pass.md` answers them. The sentence in Decision 9 about status 255 is corrected above; nothing else in this document changes.

**Closing hash.** By the convention ho-00's build-record entry states, the closing commit carries this document and cannot be named inside it; the hash is recorded as the opening hash of ho-01x's entry and in the State Memory.

### Closing this ho

Closing is five moves, together: fill this Reflect; flip `status: complete` in the frontmatter and add `closing-hash`; write the state-summary block to `ho-process/kamae-6-issoku-state-memory.md`; append the build-record entry to `ho-process/kamae-4-issoku-ho-overview.md`, which carries ho-00's closing hash as this ho's opening hash and this ho's closing hash once known; refresh `metadata/ho-status.md` and `metadata/ho-status.json` by hand. The block, verbatim labels and order:

**STATE-SUMMARY**
- **COMPLETED** — ho-01. <the harness, the findings, the six answers in one line each>
- **NEXT** — ho-01x: author `ho-process/hos/ho-01x-review-of-the-spike.md` from the x template with the findings document's path on the commit-range line, commit it, hand off to Codex.
- **ACTION ITEMS / BLOCKS** — <open items; blocks loudly, or `none`>
- **PROJECT LIFECYCLE** — kamae

---

_Authored: 2026-10-25 (Think phase)._
_Executed and closed: 2026-10-25._
