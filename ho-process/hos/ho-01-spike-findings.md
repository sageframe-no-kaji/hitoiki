---
created: 2026-10-25
type: findings
project: issoku
ho: "01"
harness-commit: "the ho-01.1 closing commit (ho-01.1: fix pass for the spike — answer ho-01x run 1); hash recorded in the build record"
---

# ho-01 — Spike Findings

The evidence for the six process-model decisions the System Design deferred to ho-01. Every run below used the release build of `spike/` (`swift build -c release --package-path spike`), from the repository root.

**Machine and conditions.** <mac>: MacBook Pro (MacBookPro18,3, Apple M1 Pro), macOS 27.0.1 (26A434), Apple Swift 6.4. The subagent's runs came from a non-interactive zsh with stdin not a terminal, launched by Claude Code inside Ghostty, so the harness read nothing from its stdin. Runs started with `&` were signalled from that same shell. The pseudoterminal's window size is unset (0 rows by 0 columns), because the harness passes nil to `forkpty`. Raw captures are in `spike/captures/`, which is gitignored; the excerpts below are copied from them. Two builds were used in ho-01. Every run before the Decision 6 amendment used the harness without the 1 MiB line cap. The second memory run and item 13's amended form used the capped build, which is the one at the closing commit. The cap changes nothing for a line under 1 MiB, and no item-18 output has one (the largest capture is 4,860 bytes). A third build, at the ho-01.1 closing commit, changes only `--plain`: the harness writes the line in progress as it grows, and the parser gained two bounds (Corrected in ho-01.1, below). The ho-01.1 demonstrations, the two reruns of run 10, and run 11 use it. The plain outputs `cmd-<n>.plain` came from the earlier build; for a line that only grows, the third build writes the same bytes in more writes, and none of those captures holds an overwriting CR or a line over 1 MiB. The raw path is the same in all three builds.

**Practitioner's half.** The practitioner ran items 7, 8, 9, and 10 from a login terminal at the repository root, and in ho-01.1 two reruns of 10 and run 11, and judged all twenty command-set outputs readable. Item 9 was run twice; the second run is the evidence. The invocations are under each decision and gathered at the end of this document.

## Corrected in ho-01.1

ho-01x run 1 (`ho-process/reviews/ho-01x-report-1.md`) returned this document; `ho-process/hos/ho-01.1-fix-pass.md` answers it. What changed, and why:

- **M1.** The plain model committed a line only at LF and the harness wrote the line in progress only after the child exited, so a prompt without LF was invisible under `--plain` until answered; section 1 claimed the raw captures settled this. The harness now writes the line in progress as it grows, and section 1 rests the claim on run 11, `sudo true` under `--plain`, whose prompt was on screen before anything was typed. Section 1 also first said run 10 took no prompt because sudo's credential cache was warm; smartctl is permitted without a password for <user> on host-a (`sudo -n -l`: NOPASSWD for `/usr/sbin/smartctl` among other admin binaries; `Defaults timestamp_timeout=60`), so run 10 cannot prompt.
- **M2.** Status 255 does not by itself identify an ssh failure, because a remote command that exits 255 returns 255 as well; section 3 and For ho-02 now say so.
- **M3.** `spike/captures/` is gitignored and the harness does not create it, so every reproduction block that writes there now begins with `mkdir -p spike/captures`.
- **M4.** The fresh-connection condition rested on a grep of the top-level config for `ControlMaster`; section 5 now cites the effective configuration from `ssh -G host-a`, the system and included config files, and a check for control sockets.
- **M5.** The scrubbed-launch note inferred that ssh read the key from disk; it now records the effective agent and identity configuration and says how ssh authenticated is not traced.
- **N6.** ho-01's captures number 23 (nineteen command-set captures, `smartctl.raw`, and three sudo captures), not 24. ho-01.1 adds `smartctl-2.raw` and `sudo-plain.raw`, so the sequence table now has 25.
- **Parser bounds.** From the efficiency audit (`ho-process/reviews/ho-01-efficiency-audit.md`): an unfinished escape sequence and the pending SGR could grow without bound outside the line cap; the model now abandons a sequence past 256 bytes and keeps at most 4,096 bytes of pending SGR (section 6, For ho-04).

---

## 1. Spawn mechanism

**Answer.** `forkpty`, candidate 1, called from Swift through `import Darwin` with no C shim. It builds in release under language mode 6 with strict concurrency and produces no warnings. The local probe shows that the pseudoterminal is the child's controlling terminal and that the child leads a new process group. It meets the sudo criterion: `ssh -tt host-a "sudo true"` prompted, the password was answered by keystroke, nothing echoed, and the run exited 0, both from a terminal (item 7) and under the scrubbed parent (item 8). Through the plain model the prompt is on screen before anything is typed (run 11, ho-01.1). `posix_spawn` with `POSIX_SPAWN_SETSID` was not built, because the spec builds it only if `forkpty` fails that criterion. The path calls `fork`.

**Evidence.**

Spawn path: `spike/Sources/IssokuSpike/Spawn.swift`. `forkpty(&master, nil, nil, nil)`; in the child, every signal disposition is reset to default and the signal mask cleared, then `execve(<shell>, [<shell>, "-c", <line>], <captured environment>)`; `_exit(127)` if exec fails. The argument and environment arrays are allocated before the fork.

Build (verification command 6):

```text
$ swift build -c release --package-path spike
Building for production...
Build complete! (5.19 sec)
```

The clean build printed no warning lines. Package settings: `swiftLanguageModes: [.v6]` and `.enableExperimentalFeature("StrictConcurrency")`.

Local probe, run-sheet item 1:

```text
$ spike/.build/release/issoku-spike -- 'tty; ps -o pid,pgid,sess,tty -p $$'
/dev/ttys001
  PID  PGID   SESS TTY
25279 25279      0 ttys001
spike: exit 0 · spawn→first-byte 21.7 ms · spawn→exit 26.2 ms
```

`tty` names a `/dev/ttys*` device, and `ps` reports the same device as the process's controlling terminal. PID equals PGID, so the group is new and the child leads it. On macOS, `ps -o sess` prints 0 for every process; that column carries no evidence.

Sudo criterion, control (item 7), run by the practitioner:

```text
$ spike/.build/release/issoku-spike --capture spike/captures/sudo-control.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
[sudo] password for <user>:
Connection to <lan-ip-a> closed.
spike: exit 0 · spawn→first-byte 421.1 ms · spawn→exit 3323.2 ms
harness exit 0
```

Sudo criterion, scrubbed parent (item 8), run by the practitioner. `ssh` authenticated:

```text
$ env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin spike/.build/release/issoku-spike --capture spike/captures/sudo-scrubbed.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
[sudo] password for <user>:
Connection to <lan-ip-a> closed.
spike: exit 0 · spawn→first-byte 541.6 ms · spawn→exit 3521.8 ms
harness exit 0
```

Spawn to exit includes the time spent typing the password.

Hexdump of each capture from the sudo prompt to the next newline. The `xxd` invocation below prints the same prompt bytes for every prompt in the three captures: once each in `sudo-control.raw` and `sudo-scrubbed.raw`, and three times in `sudo-wrong.raw`. The captures themselves differ: the control and scrubbed captures are 68 bytes, the wrong-password capture 207. The practitioner confirmed that each excerpt holds only the prompt. The user name is redacted here; in the files the prompt is 34 bytes.

```text
00000000: 5b73 7564 6f5d 2070 6173 7377 6f72 6420  [sudo] password
00000010: 666f 7220 3c75 7365 723e 3a20 0d0a        for <user>: ..
```

The orchestrator verified these facts on the files:
- `sudo-control.raw` and `sudo-scrubbed.raw` are each exactly 68 bytes: the prompt ending CR LF, then `Connection to <lan-ip-a> closed.` ending CR CR LF.
- `sudo-wrong.raw` is 207 bytes. In order: three prompts, each ending CR LF; two `Sorry, try again.` lines, each ending CR LF; `sudo: 3 incorrect password attempts` ending CR LF; then `Connection to <lan-ip-a> closed.` ending CR CR LF.
- No typed byte appears in any capture.
- The capture files are mode 0600.

`smartctl.raw` (run 10) contains no sudo prompt. smartctl is permitted without a password for <user> on host-a (`sudo -n -l`: NOPASSWD for `/usr/sbin/smartctl` among other admin binaries; `Defaults timestamp_timeout=60`), so run 10 cannot prompt; it never took a prompt through the plain model. This paragraph first gave the reason as sudo's credential cache, still warm from the previous run; that was wrong (corrected in ho-01.1). The orchestrator confirmed it on host-a, non-interactively. The `sudo -n -l` lines are the excerpt relevant here, as the orchestrator recorded them, not the full listing; the other NOPASSWD binaries beyond those named are omitted:

```text
$ ssh -tt host-a 'sudo -n smartctl -H /dev/sdb >/dev/null 2>&1; echo "status $?"' 2>/dev/null | tr -d '\r'
status 0
$ ssh -tt host-a 'sudo -n true 2>&1; echo "status $?"' 2>/dev/null | tr -d '\r'
sudo: a password is required
status 1
$ ssh -tt host-a 'sudo -n -l 2>&1' 2>/dev/null | tr -d '\r'
Matching Defaults entries for <user> on host-a:
    use_pty, env_reset,
    secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin,
    timestamp_timeout=60

User <user> may run the following commands on host-a:
    (ALL : ALL) ALL
    (lines elided)
    (ALL) NOPASSWD: /usr/bin/zfs
    (lines elided)
    (ALL) NOPASSWD: /usr/bin/zpool
    (lines elided)
    (ALL) NOPASSWD: /usr/bin/systemctl
    (lines elided)
    (ALL) NOPASSWD: /usr/sbin/smartctl
    (lines elided)
```

The first command sends smartctl's report to `/dev/null`; its status is the evidence. The orchestrator ran these three from the Mac; ssh's own `Connection to … closed.` lines went to stderr and are not shown. With `-n`, sudo refuses rather than prompts: the first command needed no password and the second did. A typed password stays cached on host-a for 60 minutes, not the five-minute default.

**Corrected in ho-01.1 (M1).** The paragraph above first said the raw captures answer whether a prompt works through the plain model, because the prompt bytes carry no escape sequence. That was wrong. The plain model committed a line only at LF, and the harness wrote the line in progress only after the child exited, so under `--plain` a prompt that ends without LF, such as `[sudo] password for <user>: `, stayed invisible until the password had been typed. The harness now writes the line in progress after every read: `LineEcho` in `spike/Sources/IssokuSpike/main.swift`, over `PlainModel.lineInProgress`, which renders the line exactly as a commit would. The claim now rests on run 11 below: under `--plain`, sudo's prompt was on screen before anything was typed, in both of its runs. Run 10 cannot supply this evidence. The local `printf` demonstrations that follow are the harness-level evidence for the same mechanism. Items 7 and 8 ran without `--plain` and are unaffected.

Harness-level demonstration, ho-01.1, local, no host. Each line is one read of the harness's stdout, with its arrival time measured from when the reader started; the reader starts with the pipeline, so its clock also counts the environment capture that precedes the spawn. `prompt: ` arrives at 0.099 s and the newline at 2.107 s:

```text
$ spike/.build/release/issoku-spike --plain -- 'printf "prompt: "; sleep 2; printf "\n"' 2>&1 | python3 -I -c $'import os, time\nt0 = time.monotonic()\nwhile b := os.read(0, 65536):\n    print(f"{time.monotonic() - t0:6.3f} s  {b!r}", flush=True)'
 0.099 s  b'prompt: '
 2.107 s  b'\n'
 2.108 s  b'spike: exit 0 \xc2\xb7 spawn\xe2\x86\x92first-byte 8.1 ms \xc2\xb7 spawn\xe2\x86\x92exit 2016.9 ms\n'
```

The CR path. When `aaaa` and `\rbb\n` arrive together, the line is committed whole as `bbaa`: the CR returns to column zero, `bb` overwrites the first two columns, and the line was never partly written. With a second between them, the harness first writes `aaaa`; at the next read the line no longer starts with what was written, so it writes CR, the whole line `bbaa`, and `ESC [ K`, then the LF. A terminal shows the one line `bbaa`:

```text
$ spike/.build/release/issoku-spike --plain -- 'printf "aaaa\rbb\n"' 2>&1 | python3 -I -c $'import os, time\nt0 = time.monotonic()\nwhile b := os.read(0, 65536):\n    print(f"{time.monotonic() - t0:6.3f} s  {b!r}", flush=True)'
 0.092 s  b'bbaa\n'
 0.092 s  b'spike: exit 0 \xc2\xb7 spawn\xe2\x86\x92first-byte 7.3 ms \xc2\xb7 spawn\xe2\x86\x92exit 7.6 ms\n'
$ spike/.build/release/issoku-spike --plain -- 'printf "aaaa"; sleep 1; printf "\rbb\n"' 2>&1 | python3 -I -c $'import os, time\nt0 = time.monotonic()\nwhile b := os.read(0, 65536):\n    print(f"{time.monotonic() - t0:6.3f} s  {b!r}", flush=True)'
 0.086 s  b'aaaa'
 1.095 s  b'\rbbaa\x1b[K\n'
 1.097 s  b'spike: exit 0 \xc2\xb7 spawn\xe2\x86\x92first-byte 7.6 ms \xc2\xb7 spawn\xe2\x86\x92exit 1017.7 ms\n'
```

Run 10 again, ho-01.1, practitioner, twice under `--plain` with the rebuilt harness: once after `ssh host-a sudo -k`, once after `ssh -tt host-a sudo -K`. No prompt appeared either time, as the NOPASSWD rule above requires. Both captures are 291 bytes with no `[sudo` in them, spawn→exit was 246–247 ms, and both outputs were readable and identical in content to run 10 (`smartctl-2.raw`, 291 bytes).

Run 11, ho-01.1, practitioner: a prompt through the plain model. Two runs back to back from a login terminal at the repository root, each after `ssh -tt host-a sudo -K`, which removes sudo's timestamps for <user> on host-a so that `sudo true` prompts. The first typed a wrong password at each of the three prompts, the second the right one:

```text
$ ssh -tt host-a sudo -K
Connection to <lan-ip-a> closed.
$ spike/.build/release/issoku-spike --plain --capture spike/captures/sudo-plain.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
[sudo] password for <user>:
Sorry, try again.
[sudo] password for <user>:
Sorry, try again.
[sudo] password for <user>:
sudo: 3 incorrect password attempts
Connection to <lan-ip-a> closed.
spike: exit 1 · spawn→first-byte 207.4 ms · spawn→exit 12334.3 ms
harness exit 1

$ ssh -tt host-a sudo -K
Connection to <lan-ip-a> closed.
$ spike/.build/release/issoku-spike --plain --capture spike/captures/sudo-plain.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
[sudo] password for <user>:
Connection to <lan-ip-a> closed.
spike: exit 0 · spawn→first-byte 192.0 ms · spawn→exit 2165.0 ms
harness exit 0
```

In both runs the prompt was on screen before anything was typed: the practitioner typed at it. Spawn to exit, 12.3 s and 2.2 s, is typing time. The plain model rendered the prompt lines, the two `Sorry, try again.` lines, and the status line correctly, and the practitioner judged the output readable. The first run's status 1 and last lines match item 9's. The capture holds the second run; the first was overwritten. The orchestrator verified it: 68 bytes, the 34-byte prompt ending CR LF, then `Connection to <lan-ip-a> closed.` ending CR CR LF, and no typed byte.

```bash
mkdir -p spike/captures
ssh -tt host-a sudo -K
spike/.build/release/issoku-spike --plain --capture spike/captures/sudo-plain.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
```

**Reproduce.**

`spike/captures/` is gitignored, so a fresh checkout does not have it, and the harness does not create it; it must exist before any run with `--capture`, so every block below that writes there begins with `mkdir -p spike/captures`.

```bash
swift build -c release --package-path spike
spike/.build/release/issoku-spike -- 'tty; ps -o pid,pgid,sess,tty -p $$'
spike/.build/release/issoku-spike --plain -- 'printf "prompt: "; sleep 2; printf "\n"' 2>&1 | python3 -I -c $'import os, time\nt0 = time.monotonic()\nwhile b := os.read(0, 65536):\n    print(f"{time.monotonic() - t0:6.3f} s  {b!r}", flush=True)'
spike/.build/release/issoku-spike --plain -- 'printf "aaaa"; sleep 1; printf "\rbb\n"' 2>&1 | python3 -I -c $'import os, time\nt0 = time.monotonic()\nwhile b := os.read(0, 65536):\n    print(f"{time.monotonic() - t0:6.3f} s  {b!r}", flush=True)'
```

Practitioner, in a terminal at the repository root (type the password at the prompt; nothing else is typed):

```bash
mkdir -p spike/captures
# item 7, control
spike/.build/release/issoku-spike --capture spike/captures/sudo-control.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
# item 8, scrubbed parent
env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin spike/.build/release/issoku-spike --capture spike/captures/sudo-scrubbed.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
```

The excerpt: every sudo prompt in a capture, from its first byte to the newline after it, with true file offsets:

```bash
for f in spike/captures/sudo-control.raw spike/captures/sudo-scrubbed.raw spike/captures/sudo-wrong.raw spike/captures/smartctl.raw; do echo "== $f"; for s in $(LC_ALL=C /usr/bin/grep -abo '\[sudo' "$f" | cut -d: -f1); do tail -c +$((s+1)) "$f" | head -n 1 | xxd -o "$s"; done; done
```

---

## 2. Process ownership

**Answer.** Locally, interrupt reaches the whole group, a group that ignores interrupt yields to force-kill, and the process table is empty afterwards in both paths. Remotely with `-tt`, interrupt ends the local `ssh` (exit 255) and the remote process is gone afterwards, whether or not the remote command traps `INT`. The force-kill step of item 5 did not happen, because `ssh` had already exited on interrupt. Remotely without `-tt`, the local group is gone but the remote `sleep` survives the local kill.

**Evidence.**

Item 2, local interrupt:

```text
$ spike/.build/release/issoku-spike -- 'sleep 300' > spike/captures/item2.out 2> spike/captures/item2.err &
$ ps -o pid,pgid,ppid,stat,command -g 25353          # harness pid 25341; child 25353 from pgrep -P
  PID  PGID  PPID STAT COMMAND
25353 25353 25341 SNs+ sleep 300
$ kill -INT 25341
$ wait 25341 → harness exit 130
spike: signal 2 · spawn→first-byte none · spawn→exit 1944.4 ms
$ ps -o pid,pgid,ppid,stat,command -g 25353
  PID  PGID  PPID STAT COMMAND
```

Item 3, local ignore-then-force:

```text
$ spike/.build/release/issoku-spike -- 'sh -c "trap \"\" INT; sleep 300"' > spike/captures/item3.out 2> spike/captures/item3.err &
$ ps -o pid,pgid,ppid,stat,command -g 25435          # harness pid 25423
  PID  PGID  PPID STAT COMMAND
25435 25435 25423 SNs+ sh -c trap "" INT; sleep 300
25436 25435 25435 SN+  sleep 300
$ kill -INT 25423
# two seconds later, both still present, no status line yet:
$ ps -o pid,pgid,ppid,stat,command -g 25435
  PID  PGID  PPID STAT COMMAND
25435 25435 25423 SNs+ sh -c trap "" INT; sleep 300
25436 25435 25435 SN+  sleep 300
$ kill -TERM 25423
$ wait 25423 → harness exit 137
spike: signal 9 · spawn→first-byte none · spawn→exit 3977.2 ms
$ ps -o pid,pgid,ppid,stat,command -g 25435
  PID  PGID  PPID STAT COMMAND
```

Before the remote items, `ssh host-a 'pgrep -af "sleep 300"'` printed `68353 sleep 300`. That process predates every run in this document. A second foreign process, `72998 sleep 300`, appeared on host-a at about 14:36 EDT, after the last remote run here. Neither was started by the harness.

Item 4, remote interrupt with a pty:

```text
$ spike/.build/release/issoku-spike -- 'ssh -tt host-a "sleep 300"' > spike/captures/item4.out 2> spike/captures/item4.err &
$ ps -o pid,pgid,ppid,stat,command -g 25516          # harness pid 25504
  PID  PGID  PPID STAT COMMAND
25516 25516 25504 SNs+ ssh -tt host-a sleep 300
$ kill -INT 25504
$ wait 25504 → harness exit 255
Connection to <lan-ip-a> closed.^M
spike: exit 255 · spawn→first-byte 3933.8 ms · spawn→exit 3934.5 ms
$ ps -o pid,pgid,ppid,stat,command -g 25516
  PID  PGID  PPID STAT COMMAND
$ ssh host-a 'pgrep -af "sleep 300"'                    # two seconds later
68353 sleep 300
```

Only the pre-existing 68353 remains.

Item 5, remote ignore-then-force with a pty:

```text
$ spike/.build/release/issoku-spike -- 'ssh -tt host-a "trap \"\" INT; sleep 300"' > spike/captures/item5.out 2> spike/captures/item5.err &
$ ps -o pid,pgid,ppid,stat,command -g 25647          # harness pid 25635
  PID  PGID  PPID STAT COMMAND
25647 25647 25635 SNs+ ssh -tt host-a trap "" INT; sleep 300
$ ssh host-a 'pgrep -af "sleep 300"'
68353 sleep 300
69109 sleep 300
$ kill -INT 25635
# two seconds later the harness had already exited:
spike: exit 255 · spawn→first-byte 4201.1 ms · spawn→exit 4202.4 ms
$ kill -TERM 25635
kill 25635 failed: no such process
$ wait 25635 → harness exit 255
Connection to <lan-ip-a> closed.^M
$ ps -o pid,pgid,ppid,stat,command -g 25647
  PID  PGID  PPID STAT COMMAND
$ ssh host-a 'pgrep -af "sleep 300"'                    # two seconds later
68353 sleep 300
```

The remote `sleep`, 69109, is gone. The remote trap could not shield the local `ssh`, which received `SIGINT` from `killpg` and exited, so the force path was not exercised for a remote command.

Item 6, remote without a pty:

```text
$ spike/.build/release/issoku-spike -- 'ssh host-a "sleep 300"' > spike/captures/item6.out 2> spike/captures/item6.err &
$ ps -o pid,pgid,ppid,stat,command -g 25750          # harness pid 25738
  PID  PGID  PPID STAT COMMAND
25750 25750 25738 SNs+ ssh host-a sleep 300
$ ssh host-a 'pgrep -af "sleep 300"'
68353 sleep 300
69335 sleep 300
$ kill -INT 25738
$ wait 25738 → harness exit 255
spike: exit 255 · spawn→first-byte none · spawn→exit 4178.2 ms
$ ps -o pid,pgid,ppid,stat,command -g 25750
  PID  PGID  PPID STAT COMMAND
$ ssh host-a 'pgrep -af "sleep 300"'                    # two seconds later, 14:31:40 EDT
68353 sleep 300
69335 sleep 300
```

The remote `sleep`, 69335, survived. The cleanup `ssh host-a 'pkill -f "sleep 300"'` was **not** run, because the pattern also matches 68353, which this run did not start. 69335 was left to finish its 300 seconds:

```text
14:34:46  $ ssh host-a 'pgrep -af "sleep 300"'  → 68353, 69335
14:35:29  $ ssh host-a 'pgrep -af "sleep 300"'  → 68353, 69335
14:36:26  $ ssh host-a 'pgrep -af "sleep 300"'  → 69335, 72998
14:36:55  $ ssh host-a 'pgrep -af "sleep 300"'  → 72998
```

**Reproduce.**

```bash
# item 2
spike/.build/release/issoku-spike -- 'sleep 300' & hp=$!; sleep 2; child=$(pgrep -P $hp); ps -o pid,pgid,ppid,stat,command -g $child; kill -INT $hp; wait $hp; echo "harness exit $?"; ps -o pid,pgid,ppid,stat,command -g $child
# item 3
spike/.build/release/issoku-spike -- 'sh -c "trap \"\" INT; sleep 300"' & hp=$!; sleep 2; child=$(pgrep -P $hp); kill -INT $hp; sleep 2; ps -o pid,pgid,ppid,stat,command -g $child; kill -TERM $hp; wait $hp; echo "harness exit $?"; ps -o pid,pgid,ppid,stat,command -g $child
# baseline, then items 4, 5, 6
ssh host-a 'pgrep -af "sleep 300"'
spike/.build/release/issoku-spike -- 'ssh -tt host-a "sleep 300"' & hp=$!; sleep 4; child=$(pgrep -P $hp); kill -INT $hp; wait $hp; echo "harness exit $?"; ps -o pid,pgid,ppid,stat,command -g $child; sleep 2; ssh host-a 'pgrep -af "sleep 300"'
spike/.build/release/issoku-spike -- 'ssh -tt host-a "trap \"\" INT; sleep 300"' & hp=$!; sleep 4; child=$(pgrep -P $hp); kill -INT $hp; sleep 2; kill -TERM $hp; wait $hp; echo "harness exit $?"; ps -o pid,pgid,ppid,stat,command -g $child; sleep 2; ssh host-a 'pgrep -af "sleep 300"'
spike/.build/release/issoku-spike -- 'ssh host-a "sleep 300"' & hp=$!; sleep 4; child=$(pgrep -P $hp); kill -INT $hp; wait $hp; echo "harness exit $?"; ps -o pid,pgid,ppid,stat,command -g $child; sleep 2; ssh host-a 'pgrep -af "sleep 300"'
```

---

## 3. Failure legibility

**Answer.** All three cases can be told apart from the status and the text alone:
- The unreachable host ends with status 255 and `ssh: connect to host 192.0.2.1 port 22: Operation timed out`.
- The rejected key, in the amended form that drops the SSH config with `-F /dev/null`, ends with status 255 and `<user>@<lan-ip-a>: Permission denied (publickey).`
- The wrong password ends with status 1 and `sudo: 3 incorrect password attempts`. That status is the remote sudo's, carried through ssh to the harness unchanged.

The first two share a status and differ in their text. The first rejected-key form, without `-F /dev/null`, authenticated with status 0: a command-line `IdentityFile` adds to the identities the config names. ssh exits 255 for its own failures and passes a remote command's status through unchanged (`ssh(1)`, EXIT STATUS), so a remote command that itself exits 255 cannot be told from an ssh failure by the status alone. In the cases recorded here the origin is known apart from the status: the timeout and the rejected key carry ssh's own message, and the interrupted `ssh` runs (items 4, 5, 6), which also ended with 255, were interrupted by the experiment itself; items 4 and 5 printed `Connection to <lan-ip-a> closed.` and item 6 printed nothing. No recorded remote command exited 255. The wrong password's status 1 is not 255, so it is the remote command's.

**Evidence.**

Item 12, unreachable host:

```text
$ spike/.build/release/issoku-spike -- 'ssh -o ConnectTimeout=3 192.0.2.1 uptime'
ssh: connect to host 192.0.2.1 port 22: Operation timed out
spike: exit 255 · spawn→first-byte 3020.9 ms · spawn→exit 3022.5 ms
```

Raw bytes from a run with a capture (`--capture spike/captures/fail-unreachable.raw`, status line `spike: exit 255 · spawn→first-byte 3022.6 ms · spawn→exit 3023.0 ms`):

```text
00000000: 7373 683a 2063 6f6e 6e65 6374 2074 6f20  ssh: connect to
00000010: 686f 7374 2031 3932 2e30 2e32 2e31 2070  host 192.0.2.1 p
00000020: 6f72 7420 3232 3a20 4f70 6572 6174 696f  ort 22: Operatio
00000030: 6e20 7469 6d65 6420 6f75 740d 0d0a       n timed out...
```

Item 13, rejected key, first form (superseded by the Decision 9 amendment). **Authenticated:**

```text
$ spike/.build/release/issoku-spike -- 'ssh -o IdentitiesOnly=yes -o IdentityFile=/dev/null -o BatchMode=yes host-a uptime'
 14:32:29 up 2 days, 21:57,  0 user,  load average: 2.21, 1.82, 1.54
spike: exit 0 · spawn→first-byte 205.5 ms · spawn→exit 206.2 ms
```

A run with `--capture spike/captures/fail-rejected-key.raw` gave the same result (`spike: exit 0 · spawn→first-byte 200.1 ms · spawn→exit 202.9 ms`). `~/.ssh/config` has `Host !github-* *` with `IdentityFile ~/.ssh/<key>`. That block matches host-a. An `IdentityFile` on the command line adds to the identities the config names and does not replace them, so `IdentitiesOnly=yes` still offered `<key>`, and host-a accepted it.

Item 13, rejected key, amended form (Decision 9 as amended), run after the line-cap rebuild:

```text
$ spike/.build/release/issoku-spike -- 'ssh -F /dev/null -o HostKeyAlias=host-a.lan -o IdentitiesOnly=yes -o IdentityFile=/dev/null -o BatchMode=yes <user>@<lan-ip-a> uptime'
Load key "/dev/null": invalid format
<user>@<lan-ip-a>: Permission denied (publickey).
spike: exit 255 · spawn→first-byte 163.6 ms · spawn→exit 165.1 ms
```

Item 9, wrong password, run by the practitioner after clearing sudo's credential cache with `sudo -k`. A wrong password was typed at each of the three prompts:

```text
$ spike/.build/release/issoku-spike --capture spike/captures/sudo-wrong.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
[sudo] password for <user>:
Sorry, try again.
[sudo] password for <user>:
Sorry, try again.
[sudo] password for <user>:
sudo: 3 incorrect password attempts
Connection to <lan-ip-a> closed.
spike: exit 1 · spawn→first-byte 377.8 ms · spawn→exit 11404.8 ms
harness exit 1
```

Status 1 is the remote sudo's, carried through ssh to the harness unchanged. A first attempt at item 9 is superseded. The correct password was typed, so its capture was identical to the control (68 bytes, exit 0) and the wrong-password path was not exercised.

**Reproduce.**

```bash
spike/.build/release/issoku-spike -- 'ssh -o ConnectTimeout=3 192.0.2.1 uptime'
spike/.build/release/issoku-spike -- 'ssh -F /dev/null -o HostKeyAlias=host-a.lan -o IdentitiesOnly=yes -o IdentityFile=/dev/null -o BatchMode=yes <user>@<lan-ip-a> uptime'
# the first form, kept as the record that a command-line IdentityFile adds to the config's
spike/.build/release/issoku-spike -- 'ssh -o IdentitiesOnly=yes -o IdentityFile=/dev/null -o BatchMode=yes host-a uptime'
grep -n -A1 '^Host !github-\* \*' ~/.ssh/config
```

Practitioner, item 9 (type a wrong password at each of the three prompts):

```bash
mkdir -p spike/captures
spike/.build/release/issoku-spike --capture spike/captures/sudo-wrong.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"
```

---

## 4. Memory ceiling

**Answer.** With the amended ring, which caps the line in progress at 1 MiB, fifty megabytes stays within a fixed ceiling: 9.7 MB peak resident locally and 8.4 MB from host-a, against 9.7 MB for one megabyte. The first run, with a line-count ring alone, shows that a line ceiling does not bound memory. Local `base64` on macOS writes fifty megabytes as one unbroken line, and that ring held it whole: 174.5 MB peak against 10.0 MB for one megabyte, a factor of 17.5. host-a's `base64` wraps at 76 columns, so the remote run stayed at 8.5 MB under both rings.

**Evidence.** Maximum resident set size from `/usr/bin/time -l`. The read buffer is fixed at 64 KiB (`spike/Sources/IssokuSpike/main.swift`).

First run: the ring holds 10,000 lines and keeps the line in progress whole.

| Item | Command | Output | Lines in output | Maximum resident set size | Peak memory footprint | Status line |
|---|---|---|---|---|---|---|
| 14 | local, 1,000,000 bytes → base64 | 1.33 MB (computed) | 1 (from `man base64`; not counted) | 9,977,856 bytes | 5,489,120 bytes | `spike: exit 0 · spawn→first-byte 13.7 ms · spawn→exit 22.4 ms` |
| 15 | local, 50,000,000 bytes → base64 | 66.7 MB | 1 | 174,505,984 bytes | 170,115,696 bytes | `spike: exit 0 · spawn→first-byte 10.3 ms · spawn→exit 394.3 ms` |
| 16 | host-a, 50,000,000 bytes → base64 | 68.4 MB as received | 877,193 | 8,470,528 bytes | 3,981,792 bytes | `spike: exit 0 · spawn→first-byte 216.0 ms · spawn→exit 1274.9 ms` |

The line counts for items 15 and 16 come from one supplementary capture each, counted with `wc -lc`. Items 14 to 16 were not themselves captured:

```text
$ wc -lc spike/captures/mem-local-50mb.raw spike/captures/mem-remote-50mb.raw
       1 66666670 spike/captures/mem-local-50mb.raw
  877193 68421246 spike/captures/mem-remote-50mb.raw
```

The remote capture holds 78 bytes per line: 76 characters plus CR LF. The local line count matches `man base64` on macOS: "-b count … The default is 0, which generates an unbroken stream" (FreeBSD base64). The two captures were deleted after counting.

Second run, after the Decision 6 amendment: the ring holds 10,000 lines and keeps at most 1,048,576 bytes of the line in progress, dropping the oldest (`LineRing.extendLineInProgress`). The plain model caps its current line the same way (`PlainModel.dropOldestColumnsOverLimit`), but items 14 to 16 run without `--plain` and do not exercise it.

| Item | Command | Maximum resident set size | Peak memory footprint | Instructions retired | Status line |
|---|---|---|---|---|---|
| 14 | local, 1,000,000 bytes → base64 | 9,699,328 bytes | 5,210,592 bytes | 141,125,589 | `spike: exit 0 · spawn→first-byte 23.2 ms · spawn→exit 42.6 ms` |
| 15 | local, 50,000,000 bytes → base64 | 9,732,096 bytes | 5,243,360 bytes | 15,045,199,631 | `spike: exit 0 · spawn→first-byte 11.2 ms · spawn→exit 1755.9 ms` |
| 16 | host-a, 50,000,000 bytes → base64 | 8,437,760 bytes | 3,949,024 bytes | 3,343,395,586 | `spike: exit 0 · spawn→first-byte 413.4 ms · spawn→exit 1296.6 ms` |

Items 14 and 15 are within 0.4% of each other. The cap is not free for an unbroken line: item 15 took 1755.9 ms and 15.0 billion instructions, against 394.3 ms in the first run. The first run's instruction count was 2,625,349,129. Each 64 KiB read past the cap shifts the retained megabyte forward.

**Reproduce.**

```bash
mkdir -p spike/captures
# at the closing commit these reproduce the second run (the 1 MiB cap is in the harness)
/usr/bin/time -l spike/.build/release/issoku-spike -- 'head -c 1000000 /dev/urandom | base64' > /dev/null
/usr/bin/time -l spike/.build/release/issoku-spike -- 'head -c 50000000 /dev/urandom | base64' > /dev/null
/usr/bin/time -l spike/.build/release/issoku-spike -- 'ssh host-a "head -c 50000000 /dev/urandom | base64"' > /dev/null
spike/.build/release/issoku-spike --capture spike/captures/mem-local-50mb.raw -- 'head -c 50000000 /dev/urandom | base64' > /dev/null
spike/.build/release/issoku-spike --capture spike/captures/mem-remote-50mb.raw -- 'ssh host-a "head -c 50000000 /dev/urandom | base64"' > /dev/null
wc -lc spike/captures/mem-local-50mb.raw spike/captures/mem-remote-50mb.raw
```

---

## 5. Latency

**Answer.** Return-to-first-byte medians over five runs: 14.5 ms for local `uptime`, 202.1 ms for host-a, 383.2 ms for host-b, and 602.3 ms for host-c. Spawn-to-exit medians: 14.8, 204.6, 383.9, and 608.2 ms. host-a and host-b are reached over the LAN, host-c over Tailscale. The recorded configuration supports that every remote run opened a fresh SSH connection: the effective configuration for host-a sets `controlmaster false`, `controlpersist no`, and no `ControlPath`; no config file ssh reads sets `ControlMaster`, `ControlPath`, or `ControlPersist` for any host; and `~/.ssh` holds no control socket. The configuration was recorded in ho-01.1, after the runs, from files last changed before them; the connections themselves were not traced. Hotkey-to-panel has no panel to measure yet and belongs to ho-03.

**Evidence.** Intervals from `ContinuousClock`: from just before `forkpty` to the first byte read from the master, and from just before `forkpty` to the exit report. Both include the login shell's `-c` startup. The environment capture runs before the first instant and is not counted.

| Case | spawn→first-byte, runs 1–5 (ms) | Median | spawn→exit, runs 1–5 (ms) | Median |
|---|---|---|---|---|
| local `uptime` | 16.1, 9.2, 14.9, 11.2, 14.5 | 14.5 | 16.4, 9.5, 15.3, 11.5, 14.8 | 14.8 |
| `ssh host-a uptime` | 211.3, 201.4, 201.7, 202.1, 232.2 | 202.1 | 211.8, 201.9, 202.3, 204.6, 234.6 | 204.6 |
| `ssh host-b uptime` | 786.7, 383.2, 380.6, 375.2, 461.8 | 383.2 | 791.1, 383.9, 381.2, 376.3, 462.6 | 383.9 |
| `ssh host-c uptime` | 1457.1, 602.3, 627.0, 600.5, 582.6 | 602.3 | 1458.1, 608.2, 640.3, 604.4, 590.8 | 608.2 |

All twenty runs exited 0. Every status line had the form `spike: exit 0 · spawn→first-byte <ms> ms · spawn→exit <ms> ms` with the values above. Runs were back to back at 14:32 EDT. The first run to host-b and the first to host-c were the slowest of their five.

Network path:

| Host | `~/.ssh/config` HostName | Route from <mac> | Tailscale status |
|---|---|---|---|
| host-a | <lan-ip-a> | LAN, interface en7 | peer listed `active; offers exit node; direct`, but the SSH HostName is the LAN address, not the tailnet address |
| host-b | <lan-ip-b> | LAN, interface en7 | peer listed `-` (idle) |
| host-c | <tailscale-ip-c> | Tailscale, interface utun18 | peer listed `active; direct` (endpoint omitted) |

The ho-01 run recorded only this, which reads the top-level user config and nothing it includes, nor the system config:

```text
$ grep -i controlmaster ~/.ssh/config
(no output, exit 1)
```

Effective configuration, recorded in ho-01.1 from the subagent's shell. `ssh -G` prints the configuration ssh would use, after every file and `Include`, and opens no connection. OpenSSH_10.3p1, LibreSSL 3.3.6. It prints no `controlpath` and no `identityagent` line, so neither is set. The first line is ssh's own, on stderr:

```text
$ ssh -G host-a | /usr/bin/grep -E '^(controlmaster|controlpath|controlpersist|identityagent|identityfile|identitiesonly) '
Pseudo-terminal will not be allocated because stdin is not a terminal.
controlmaster false
identitiesonly no
identityfile ~/.ssh/<key>
controlpersist no
```

`ssh -G` was run for host-a only. For host-b and host-c, the config files themselves: `~/.ssh/config`, `/etc/ssh/ssh_config`, which includes `/etc/ssh/ssh_config.d/*`, its one file `100-macos.conf`, and the `/etc/ssh/crypto.conf` that file includes. None sets `ControlMaster`, `ControlPath`, `ControlPersist`, or `IdentityAgent`; the only matches are the two `Include` lines. `~/.ssh/config` was last modified 2026-10-19 and the system files 2025-07-19, all before the runs on 2026-10-25.

```text
$ /usr/bin/grep -ciE '^[[:space:]]*(control(master|path|persist)|include|identityagent)' ~/.ssh/config /etc/ssh/ssh_config /etc/ssh/ssh_config.d/* /etc/ssh/crypto.conf
/Users/<user>/.ssh/config:0
/etc/ssh/ssh_config:1
/etc/ssh/ssh_config.d/100-macos.conf:1
/etc/ssh/crypto.conf:0
```

Control sockets: `ls ~/.ssh` shows no control socket (no `cm-*`, `*.sock`, or ControlPath-style entry). A search for sockets under it finds one, an ssh-agent socket in `~/.ssh/agent/`, created 2026-10-15; its name is replaced here:

```text
$ find ~/.ssh -type s
~/.ssh/agent/<socket>
```

**Reproduce.**

```bash
for cmd in uptime 'ssh host-a uptime' 'ssh host-b uptime' 'ssh host-c uptime'; do for i in 1 2 3 4 5; do spike/.build/release/issoku-spike -- "$cmd"; done; done
grep -i controlmaster ~/.ssh/config
ssh -G host-a | /usr/bin/grep -E '^(controlmaster|controlpath|controlpersist|identityagent|identityfile|identitiesonly) '
/usr/bin/grep -ciE '^[[:space:]]*(control(master|path|persist)|include|identityagent)' ~/.ssh/config /etc/ssh/ssh_config /etc/ssh/ssh_config.d/* /etc/ssh/crypto.conf
find ~/.ssh -type s
tailscale status | grep -E 'host-a|host-b|host-c'
route -n get <lan-ip-a> | grep interface; route -n get <lan-ip-b> | grep interface; route -n get <tailscale-ip-c> | grep interface
```

---

## 6. Terminal-control depth

**Answer.** The 19 command-set items the subagent ran emitted no escape sequence other than SGR, no C0 control other than CR, LF, and TAB, and no carriage return that overwrites a line. Through the plain-text model, all 19 exited 0 and produced their output. The practitioner judged all nineteen readable. Command-set item 13 (`sudo smartctl -H`), the practitioner's run 10, exited 0 through the plain model, has no escape sequence in its capture, and was judged readable. smartctl is permitted without a password for <user> on host-a (`sudo -n -l`: NOPASSWD for `/usr/sbin/smartctl` among other admin binaries; `Defaults timestamp_timeout=60`), so run 10 cannot prompt; the two ho-01.1 reruns under `--plain` were readable and identical in content to run 10, and the prompt question is answered by run 11, `sudo true` under `--plain`, recorded under Spawn mechanism and judged readable. The unreadable list is empty.

**Evidence.**

The model (`spike/Sources/IssokuSpike/PlainModel.swift`) passes SGR through, removes every other escape sequence, rewinds the line on CR, and commits the line on LF. Other bytes are characters, and UTF-8 continuation bytes join the character before them. Since ho-01.1 it also abandons an escape or control sequence longer than 256 bytes, ESC included, dropping its bytes and returning to ground, and keeps at most 4,096 bytes of SGR not yet attached to a character, dropping the oldest whole sequences; and the harness writes the line in progress as it grows (section 1). None of the runs below reached either bound: no capture holds a non-SGR sequence, and the three that hold SGR are each under 4,096 bytes in all. Captures: `spike/captures/cmd-<n>.raw`. Plain output: `spike/captures/cmd-<n>.plain`.

Conditions: the commands ran with the environment captured in the subagent's shell, which includes `TERM=xterm-ghostty` (see For ho-02). The window size is 0 by 0. The remote commands ran without `-tt`, so on the remote side their output went to a pipe, not a terminal.

Status lines, item 18:

| # | Command | Status line |
|---|---|---|
| 1 | `uptime` | `spike: exit 0 · spawn→first-byte 22.7 ms · spawn→exit 23.0 ms` |
| 2 | `df -h` | `spike: exit 0 · spawn→first-byte 17.0 ms · spawn→exit 17.4 ms` |
| 3 | `ls -G ~` | `spike: exit 0 · spawn→first-byte 14.3 ms · spawn→exit 14.7 ms` |
| 4 | `brew update` | `spike: exit 0 · spawn→first-byte 2209.5 ms · spawn→exit 10040.6 ms` |
| 5 | `brew outdated` | `spike: exit 0 · spawn→first-byte 1196.7 ms · spawn→exit 1234.3 ms` |
| 6 | `diskutil info disk0` | `spike: exit 0 · spawn→first-byte 61.5 ms · spawn→exit 182.0 ms` |
| 7 | `git -C ~/Vaults/sageframe-no-kaji-dev/issoku status` | `spike: exit 0 · spawn→first-byte 20.7 ms · spawn→exit 21.3 ms` |
| 8 | `ping -c 3 host-a` | `spike: exit 0 · spawn→first-byte 20.6 ms · spawn→exit 2041.1 ms` |
| 9 | `ssh host-a uptime` | `spike: exit 0 · spawn→first-byte 254.4 ms · spawn→exit 256.0 ms` |
| 10 | `ssh host-a 'zpool status pool-a'` | `spike: exit 0 · spawn→first-byte 221.1 ms · spawn→exit 222.3 ms` |
| 11 | `ssh host-a 'zfs list -r pool-a'` | `spike: exit 0 · spawn→first-byte 210.2 ms · spawn→exit 214.1 ms` |
| 12 | `ssh host-a 'zpool list'` | `spike: exit 0 · spawn→first-byte 221.1 ms · spawn→exit 221.8 ms` |
| 13 | `ssh -tt host-a 'sudo smartctl -H /dev/sdb'` | `spike: exit 0 · spawn→first-byte 218.6 ms · spawn→exit 242.4 ms` (practitioner's run 10) |
| 14 | `ssh host-b uptime` | `spike: exit 0 · spawn→first-byte 500.5 ms · spawn→exit 502.8 ms` |
| 15 | `ssh host-b 'docker ps --format "table {{.Names}}\t{{.Status}}"'` | `spike: exit 0 · spawn→first-byte 439.0 ms · spawn→exit 443.0 ms` |
| 16 | `ssh host-b 'zpool status rpool'` | `spike: exit 0 · spawn→first-byte 382.8 ms · spawn→exit 387.8 ms` |
| 17 | `ssh host-c uptime` | `spike: exit 0 · spawn→first-byte 727.5 ms · spawn→exit 730.0 ms` |
| 18 | `ssh host-c 'docker ps --format "table {{.Names}}\t{{.Status}}"'` | `spike: exit 0 · spawn→first-byte 543.9 ms · spawn→exit 555.2 ms` |
| 19 | `ssh host-c 'systemctl status docker --no-pager'` | `spike: exit 0 · spawn→first-byte 661.8 ms · spawn→exit 666.3 ms` |
| 20 | `ssh host-c 'journalctl -u docker -n 20 --no-pager'` | `spike: exit 0 · spawn→first-byte 1002.8 ms · spawn→exit 1007.0 ms` |

The sequence table is in For ho-04.

Readability, per command, as judged by the practitioner from each `spike/captures/cmd-<n>.plain` and, for item 13, from run 10's terminal output:

| # | Readable? |
|---|---|
| 1–12, 14–20 | Readable |
| 13 | Readable (from run 10's terminal output) |
| Run 11, `sudo true` under `--plain` | Readable (from run 11's terminal output) |

SGR passes through by design. No plain capture contained any other escape sequence or an overwriting CR.

Run 10, the practitioner's terminal output through `--plain`:

```text
$ spike/.build/release/issoku-spike --plain --capture spike/captures/smartctl.raw -- 'ssh -tt host-a "sudo smartctl -H /dev/sdb"'; echo "harness exit $?"
smartctl 7.3 2022-02-28 r5338 [x86_64-linux-6.8.12-43-pve] (local build)
Copyright (C) 2002-22, Bruce Allen, Christian Franke, www.smartmontools.org

=== START OF READ SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED

Connection to <lan-ip-a> closed.
spike: exit 0 · spawn→first-byte 218.6 ms · spawn→exit 242.4 ms
harness exit 0
```

**Reproduce.**

```bash
mkdir -p spike/captures
while IFS='|' read -r n cmd; do spike/.build/release/issoku-spike --plain --capture spike/captures/cmd-$n.raw -- "$cmd" > spike/captures/cmd-$n.plain < /dev/null; done <<'LIST'
1|uptime
2|df -h
3|ls -G ~
4|brew update
5|brew outdated
6|diskutil info disk0
7|git -C ~/Vaults/sageframe-no-kaji-dev/issoku status
8|ping -c 3 host-a
9|ssh host-a uptime
10|ssh host-a 'zpool status pool-a'
11|ssh host-a 'zfs list -r pool-a'
12|ssh host-a 'zpool list'
14|ssh host-b uptime
15|ssh host-b 'docker ps --format "table {{.Names}}\t{{.Status}}"'
16|ssh host-b 'zpool status rpool'
17|ssh host-c uptime
18|ssh host-c 'docker ps --format "table {{.Names}}\t{{.Status}}"'
19|ssh host-c 'systemctl status docker --no-pager'
20|ssh host-c 'journalctl -u docker -n 20 --no-pager'
LIST
python3 -I spike/tabulate-sequences.py spike/captures/cmd-{1..12}.raw spike/captures/cmd-{14..20}.raw
```

Practitioner, run 10 (command-set item 13; no prompt appears, because smartctl is NOPASSWD for <user> on host-a):

```bash
mkdir -p spike/captures
spike/.build/release/issoku-spike --plain --capture spike/captures/smartctl.raw -- 'ssh -tt host-a "sudo smartctl -H /dev/sdb"'; echo "harness exit $?"
python3 -I spike/tabulate-sequences.py spike/captures/smartctl.raw spike/captures/sudo-control.raw spike/captures/sudo-scrubbed.raw spike/captures/sudo-wrong.raw
```

---

## For ho-02

- The `forkpty` path calls `fork`. The harness is a command-line process. Its environment capture runs through Foundation's `Process` in the same process before the fork. Between fork and exec the child calls only `signal`, `sigemptyset`, `sigprocmask`, `execve`, and `_exit`.
- The harness resets every signal disposition to default and clears the signal mask in the child before exec. Exec keeps a disposition that is set to ignore, so without the reset the child inherits whatever its parent ignores.
- The harness sets its own `SIGINT` and `SIGTERM` to ignore, and receives them as dispatch signal sources, only after the fork.
- Capture invocation: `getpwuid(getuid())` gives `/bin/zsh`. The capture runs `/bin/zsh -l -c 'env -0'` with the harness's own environment and stdin from `/dev/null`. zsh login, non-interactive, reads `~/.zshenv` (`. "$HOME/.cargo/env"`) and `~/.zprofile` (`eval "$(/opt/homebrew/bin/brew shellenv)"`). There is no `~/.zlogin`.
- Variable names the capture yielded from the subagent's shell (51): `__CF_USER_TEXT_ENCODING __CFBundleIdentifier _ AI_AGENT BUN_INSTALL CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_SESSION_ID CLAUDE_EFFORT CLAUDE_PID CLAUDECODE COLORTERM COMMAND_MODE COREPACK_ENABLE_AUTO_PIN EDITOR FPATH GHOSTTY_BIN_DIR GHOSTTY_RESOURCES_DIR GHOSTTY_SHELL_FEATURES GIT_EDITOR HOME HOMEBREW_CELLAR HOMEBREW_PREFIX HOMEBREW_REPOSITORY INFOPATH LANG LOGNAME MANPATH NoDefaultCurrentDirectoryInExePath OLDPWD OSLogRateLimit PATH PWD SHELL SHLVL SSH_AUTH_SOCK TERM_PROGRAM_VERSION TERM_PROGRAM TERM TERMINFO TMPDIR USER UV_NO_ANALYTICS VISUAL XDG_DATA_DIRS XPC_FLAGS XPC_SERVICE_NAME`. This shell is Claude Code's, inside Ghostty, not Terminal.app.
- Variable names the capture yielded under `env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin` (15): `__CF_USER_TEXT_ENCODING _ FPATH HOME HOMEBREW_CELLAR HOMEBREW_PREFIX HOMEBREW_REPOSITORY INFOPATH LANG LOGNAME OLDPWD PATH PWD SHLVL USER`. Every one is also in the first list.
- In the first list and not in the scrubbed one: `AI_AGENT BUN_INSTALL CLAUDECODE CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_SESSION_ID CLAUDE_EFFORT CLAUDE_PID COLORTERM COMMAND_MODE COREPACK_ENABLE_AUTO_PIN EDITOR GHOSTTY_BIN_DIR GHOSTTY_RESOURCES_DIR GHOSTTY_SHELL_FEATURES GIT_EDITOR MANPATH NoDefaultCurrentDirectoryInExePath OSLogRateLimit SHELL SSH_AUTH_SOCK TERM TERMINFO TERM_PROGRAM TERM_PROGRAM_VERSION TMPDIR UV_NO_ANALYTICS VISUAL XDG_DATA_DIRS XPC_FLAGS XPC_SERVICE_NAME __CFBundleIdentifier`.
- `SSH_AUTH_SOCK` is absent from the scrubbed capture. In the subagent's capture it is under `/var/run/com.apple.launchd.<id>/`. Under the scrubbed launch, `ssh -tt host-a` authenticated (item 8). The effective configuration for host-a names no `IdentityAgent` and one `IdentityFile`, `~/.ssh/<key>`, with `identitiesonly no` (Latency, `ssh -G host-a`); an ssh-agent socket exists under `~/.ssh/agent/`. How ssh authenticated is not traced.
- Values that differ: `LANG` is `en_US.UTF-8` in the subagent's capture and `C.UTF-8` in the scrubbed one. `PATH` in the scrubbed capture is `/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:` + the three cryptexd bootstrap paths + `/pkg/env/global/bin:/Library/Apple/usr/bin:/opt/homebrew/bin:/Users/<user>/.cargo/bin`. The subagent's adds `~/.local/bin`, `~/bin`, `~/.bun/bin`, a Python 3.12 framework path, and a Ghostty build path. `SHELL`, `TERM`, and `TMPDIR` are not set under the scrubbed launch.
- Remote survival without `-tt`: yes. `ssh host-a "sleep 300"`, interrupted locally, left the remote `sleep` running until it finished on its own (item 6).
- Remote with `-tt`: `SIGINT` to the group ends the local `ssh` with status 255 and `Connection to <lan-ip-a> closed.`, and the remote process ends, including one that traps `INT` (items 4, 5).
- The status-255 distinction: ssh exits 255 for its own failures and passes a remote command's status through unchanged, so a remote command that itself exits 255 cannot be told from an ssh failure by the status alone (`ssh(1)`, EXIT STATUS). Recorded with 255: connection failure (item 12) and rejected key (item 13, amended form), which carry ssh's own text, `Operation timed out` against `Permission denied (publickey).`; and every `ssh` ended by `SIGINT` from the harness (items 4, 5, 6). No recorded remote command exited 255. The wrong password (item 9) ended with status 1 from the remote sudo, carried through ssh unchanged.
- `ssh -o IdentitiesOnly=yes -o IdentityFile=/dev/null` does not remove the identities `~/.ssh/config` names. Under this config it authenticated to host-a. With `-F /dev/null` added, it was rejected.
- sudo's timestamp on host-a is keyed to the terminal device and lasts 60 minutes (`Defaults timestamp_timeout=60`), and some admin binaries, smartctl among them, are NOPASSWD for <user>. A prompt is therefore not guaranteed on every remote sudo; the app cannot assume one.
- The pseudoterminal's window size is 0 rows by 0 columns when `forkpty` is given nil.
- With stdin a terminal, the harness uses `cfmakeraw` with `ISIG` and `OPOST | ONLCR` turned back on. Control-C therefore reaches the harness as `SIGINT` and never as a `0x03` byte. Items 7–10 are the first runs with stdin a terminal.

## For ho-04

- Non-SGR sequences per capture, 25 captures: the nineteen from `python3 -I spike/tabulate-sequences.py spike/captures/cmd-{1..12}.raw spike/captures/cmd-{14..20}.raw`, `smartctl.raw` with the three sudo captures from the practitioner's invocation, and, from ho-01.1, `smartctl-2.raw` and `sudo-plain.raw` (Practitioner's runs, gathered):

| Capture | Bytes | Non-SGR escape sequences | Other C0 controls | Overwriting CR | Distinct SGR |
|---|---|---|---|---|---|
| cmd-1.raw | 68 | none | none | 0 | 0 |
| cmd-2.raw | 2095 | none | none | 0 | 0 |
| cmd-3.raw | 962 | none | none | 0 | 4 |
| cmd-4.raw | 1944 | none | none | 0 | 3 |
| cmd-5.raw | 4326 | none | none | 0 | 0 |
| cmd-6.raw | 1002 | none | none | 0 | 0 |
| cmd-7.raw | 464 | none | none | 0 | 2 |
| cmd-8.raw | 423 | none | none | 0 | 0 |
| cmd-9.raw | 70 | none | none | 0 | 0 |
| cmd-10.raw | 326 | none | none | 0 | 0 |
| cmd-11.raw | 1457 | none | none | 0 | 0 |
| cmd-12.raw | 441 | none | none | 0 | 0 |
| cmd-14.raw | 70 | none | none | 0 | 0 |
| cmd-15.raw | 765 | none | none | 0 | 0 |
| cmd-16.raw | 281 | none | none | 0 | 0 |
| cmd-17.raw | 70 | none | none | 0 | 0 |
| cmd-18.raw | 411 | none | none | 0 | 0 |
| cmd-19.raw | 4324 | none | none | 0 | 0 |
| cmd-20.raw | 4860 | none | none | 0 | 0 |
| smartctl.raw | 291 | none | none | 0 | 0 |
| sudo-control.raw | 68 | none | none | 0 | 0 |
| sudo-scrubbed.raw | 68 | none | none | 0 | 0 |
| sudo-wrong.raw | 207 | none | none | 0 | 0 |
| smartctl-2.raw | 291 | none | none | 0 | 0 |
| sudo-plain.raw | 68 | none | none | 0 | 0 |

- The script is `spike/tabulate-sequences.py`. It follows the plain-text model's grammar: CSI, OSC and the other string sequences, single-character ESC sequences, C0 controls other than CR, LF, and TAB, and CRs followed by anything but CR or LF.
- SGR occurred in `ls -G ~` (4 distinct), `brew update` (3), and `git status` (2), under `TERM=xterm-ghostty`.
- `brew update` printed no progress line in this run. It had nothing to download, and its capture holds no overwriting CR.
- `systemctl status` on host-c, run without `-tt`, printed no SGR. Its `●` and `├─`/`└─` glyphs arrived as UTF-8 and are intact in the plain output.
- The plain model's parser bounds (ho-01.1): an escape or control sequence longer than 256 bytes, ESC included, is abandoned, its bytes dropped and the parser back at ground, so the rest of an over-long OSC or DCS string reads as text; SGR not yet attached to a character is held to 4,096 bytes, oldest whole sequences dropped first. No capture here reaches either bound.
- ssh's own messages arrive as `CR CR LF` (item 12's hexdump): ssh writes CR LF, and the pseudoterminal's output processing adds a CR before the LF.
- A single line with no LF is held whole by a line-count ring: 66.7 MB in one line gave 174.5 MB peak resident (Memory ceiling, item 15, first run). With the line in progress capped at 1 MiB, oldest bytes dropped, the same output peaked at 9.7 MB and took 1755.9 ms against 394.3 ms (second run).
- The unreadable list: none. The practitioner judged all nineteen plain captures (items 1–12 and 14–20), run 10's output (item 13), and run 11's output readable.

## Additions to the command set

None. The subagent added none, and the practitioner's transcript holds only items 7 to 10 as listed.

---

## Practitioner's runs, gathered

The practitioner ran these from a login terminal at the repository root, after `swift build -c release --package-path spike`, typing only at sudo prompts. Item 9 ran after `sudo -k`; each of run 11's two runs ran after `ssh -tt host-a sudo -K`. The transcripts are under Spawn mechanism (items 7 and 8, the ho-01.1 reruns of item 10, and run 11), Failure legibility (item 9), and Terminal-control depth (item 10). Item 10 takes no prompt: smartctl is permitted without a password for <user> on host-a (`sudo -n -l`: NOPASSWD for `/usr/sbin/smartctl` among other admin binaries; `Defaults timestamp_timeout=60`), so run 10 cannot prompt.

```bash
mkdir -p spike/captures

# 7 — control
spike/.build/release/issoku-spike --capture spike/captures/sudo-control.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"

# 8 — scrubbed parent
env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin:/usr/sbin:/sbin spike/.build/release/issoku-spike --capture spike/captures/sudo-scrubbed.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"

# 9 — wrong password at each of three prompts
spike/.build/release/issoku-spike --capture spike/captures/sudo-wrong.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"

# 10 — disk health (command-set item 13)
spike/.build/release/issoku-spike --plain --capture spike/captures/smartctl.raw -- 'ssh -tt host-a "sudo smartctl -H /dev/sdb"'; echo "harness exit $?"

# 10 again (ho-01.1), twice; no prompt either time, because smartctl is NOPASSWD
ssh host-a sudo -k
spike/.build/release/issoku-spike --plain --capture spike/captures/smartctl-2.raw -- 'ssh -tt host-a "sudo smartctl -H /dev/sdb"'; echo "harness exit $?"
ssh -tt host-a sudo -K
spike/.build/release/issoku-spike --plain --capture spike/captures/smartctl-2.raw -- 'ssh -tt host-a "sudo smartctl -H /dev/sdb"'; echo "harness exit $?"

# 11 — a prompt through --plain (ho-01.1): remove sudo's timestamps, then sudo true prompts
ssh -tt host-a sudo -K
spike/.build/release/issoku-spike --plain --capture spike/captures/sudo-plain.raw -- 'ssh -tt host-a "sudo true"'; echo "harness exit $?"

# each sudo prompt to the newline after it
for f in spike/captures/sudo-control.raw spike/captures/sudo-scrubbed.raw spike/captures/sudo-wrong.raw spike/captures/smartctl.raw spike/captures/smartctl-2.raw spike/captures/sudo-plain.raw; do echo "== $f"; for s in $(LC_ALL=C /usr/bin/grep -abo '\[sudo' "$f" | cut -d: -f1); do tail -c +$((s+1)) "$f" | head -n 1 | xxd -o "$s"; done; done

# the sequence table rows for these captures
python3 -I spike/tabulate-sequences.py spike/captures/smartctl.raw spike/captures/sudo-control.raw spike/captures/sudo-scrubbed.raw spike/captures/sudo-wrong.raw spike/captures/smartctl-2.raw spike/captures/sudo-plain.raw
```
