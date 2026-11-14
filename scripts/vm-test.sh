#!/usr/bin/env bash
#
# Runs the verification stack inside a macOS guest under Tart, so the Panel
# suite's windows open on the guest's screen and never on the practitioner's.
# Run from anywhere; no arguments.
#
#   HITOIKI_VM       the guest's Tart name   (default: hitoiki-test)
#   HITOIKI_VM_USER  the guest's user        (default: admin, Tart's published default)
#
# What it does: starts the guest headless, copies the working tree in with
# rsync (leaving out .build, .swiftpm, .git and spike/captures), runs the six
# commands of CLAUDE.md's Verification rhythm inside, each in its own SSH
# session, streams the output and saves it to .build/vm-test/<UTC stamp>.log,
# stops the guest on every exit path, and prints a summary and the log's path.
# The exit is 0 only when all six commands exit 0.
#
# The guest is found by `tart ip` at each run; the script holds no address,
# no host name, no key path and no password. It connects by key with
# BatchMode=yes, so it can never prompt.
#
# Window server: a plain SSH session is enough. The image logs `admin` in
# automatically at boot, so the console session belongs to the same user as
# the SSH session, and a test process started over SSH reaches that session's
# window server: the Panel suite creates its windows and makes them key (its
# #expect(window.isKeyWindow) checks pass). Neither `launchctl asuser` nor a
# LaunchAgent is needed (ho-04.7 Discovery 3).
#
# Provisioning record. The guest is made once, by hand, from these steps; this
# script does not make it (ho-04.7 Decision 9).
#
#   1. Tart, from the openai/tools tap (the project moved from Cirrus Labs to
#      OpenAI; the old cirruslabs/cli tap does not install under Homebrew 7,
#      and Homebrew 7 wants explicit trust for the tap's network helper):
#        brew trust --formula openai/tools/softnet
#        brew install openai/tools/tart
#      (Tart 2.41.1, softnet 0.25.0 at ho-04.7.)
#   2. The base image, kept generic under its published name so other
#      projects can clone it (macOS 27.2, 26B123; 38 GB on disk, ASIF):
#        tart pull ghcr.io/cirruslabs/macos-golden-gate-base:latest
#   3. This project's guest, 6 GB of memory and four cores:
#        tart clone ghcr.io/cirruslabs/macos-golden-gate-base:latest hitoiki-test
#        tart set hitoiki-test --memory 6144 --cpu 4
#   4. Key access. Boot it and push the public keys of the SSH agent, typing
#      Tart's published password for `admin` once, in your own terminal:
#        tart run --no-graphics hitoiki-test &
#        ssh-copy-id admin@"$(tart ip hitoiki-test --wait 120)"
#   5. The toolchain: the host's own Xcode, copied into the guest. No
#      download, no Apple ID (ho-04.7 Decision 2, rung 3, ruled by the
#      practitioner). The image's own Command Line Tools 27.2 (Swift 6.4.2),
#      tried first, left swift-testing's macro plugin (TestingMacros) out of
#      about half of all test builds, at random. The copy is streamed with ditto, which keeps
#      the bundle's attributes and signature and its APFS compression (rsync
#      would land it uncompressed, 9.6 GB against 4.0 GB, past the guest's
#      free space). With the guest running:
#        ditto -c --keepParent /Applications/Xcode.app - \
#          | ssh admin@"$(tart ip hitoiki-test)" \
#              'sudo -n ditto -x --hfsCompression - /Applications'
#      Then, inside the guest:
#        sudo xcode-select -s /Applications/Xcode.app
#        sudo xcodebuild -license accept
#        sudo xcodebuild -runFirstLaunch
#      (Xcode 27.1, 27A9275; Swift 6.4, swiftlang-6.4.0.34.1, as on the host.)
#      The Command Line Tools stay in the image, unselected.
#   6. SwiftLint and swift-format, inside the guest, with the image's
#      Homebrew (swift-format from Homebrew, as on the host):
#        eval "$(/opt/homebrew/bin/brew shellenv)"
#        brew install swiftlint swift-format
#      (SwiftLint 0.65.1, swift-format 604.0.0 at ho-04.7.)
#   7. Shut it down from inside, never by `tart stop` alone (see stop_guest):
#        ssh admin@"$(tart ip hitoiki-test)" 'sudo shutdown -h now'

set -uo pipefail

VM="${HITOIKI_VM:-hitoiki-test}"
VM_USER="${HITOIKI_VM_USER:-admin}"
HO="ho-04.7 (ho-process/hos/ho-04.7-virtual-mac-for-test-runs.md)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUEST_TREE="hitoiki" # under the guest user's home
LOG_DIR="$ROOT/.build/vm-test"
LOG="$LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ).log"

# The guest is a local clone whose address changes from run to run; its host
# key is not pinned, and nothing is written to the known_hosts file.
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=30
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# A non-login SSH shell reads no profile, so Homebrew's bin, which holds
# swiftlint and swift-format, is put on PATH here. Everything else comes
# from the selected Xcode through the /usr/bin shims.
# Single quotes: $PATH is expanded by the guest's shell, not this one.
# shellcheck disable=SC2016
GUEST_ENV='export PATH="/opt/homebrew/bin:$PATH";'

STEPS=(
    "swift-format lint --recursive --strict Sources Tests"
    "swiftlint lint --strict"
    "swift build"
    "swift test"
    "swift test --enable-code-coverage && scripts/coverage-floor.sh"
    "swift build -c release"
)

mkdir -p "$LOG_DIR"
: >"$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }

# One "Test run with N tests in M suites passed" line per test target is what
# a green `swift test` prints; the count comes from Package.swift so a new
# target is not forgotten here.
TEST_TARGETS=$(grep -c '^[[:space:]]*\.testTarget(' "$ROOT/Package.swift")

if ! command -v tart >/dev/null 2>&1; then
    echo "vm-test: tart is not installed. See the provisioning record in this script and $HO."
    exit 2
fi

STATE="$(tart list --source local 2>/dev/null | awk -v vm="$VM" '$2 == vm { print $NF }')"
if [[ -z "$STATE" ]]; then
    echo "vm-test: no Tart guest named '$VM' (tart list does not show it)."
    echo "vm-test: make it from the provisioning record in this script; see $HO."
    exit 2
fi
if [[ "$STATE" != "stopped" ]]; then
    echo "vm-test: the guest '$VM' is $STATE; stop it first (tart stop $VM)."
    exit 2
fi

RUN_START=$SECONDS
TART_PID=""
STOPPED=0
STOP_SECS=0

# Stopping. `tart stop` alone ends a macOS guest at once, without a shutdown,
# and the guest loses its last writes: that once left the guest's .build
# database corrupt, and the next run's builds failed (ho-04.7). So the guest is
# first shut down from inside (the image gives `admin` passwordless sudo) and
# given a minute to power off; `tart stop` then runs on every path, and is
# what ends the guest if it cannot be reached or does not stop in time.
stop_guest() {
    if [[ $STOPPED -eq 0 && -n "$TART_PID" ]]; then
        STOPPED=1
        local t0=$SECONDS
        if [[ -n "${IP:-}" ]]; then
            ssh -n "${SSH_OPTS[@]}" "$VM_USER@${IP}" 'sudo -n shutdown -h now' >>"$LOG" 2>&1
            local deadline=$((SECONDS + 60))
            while kill -0 "$TART_PID" 2>/dev/null && ((SECONDS < deadline)); do
                sleep 1
            done
        fi
        tart stop "$VM" >>"$LOG" 2>&1
        wait "$TART_PID" 2>/dev/null
        STOP_SECS=$((SECONDS - t0))
    fi
}
trap stop_guest EXIT
trap 'say "vm-test: interrupted"; exit 130' INT TERM

say "vm-test: guest $VM, user $VM_USER, log $LOG"

# Boot, then wait for an address and for SSH to answer: two minutes in all.
BOOT_START=$SECONDS
tart run --no-graphics "$VM" >>"$LOG" 2>&1 &
TART_PID=$!
IP=""
DEADLINE=$((SECONDS + 120))
while ((SECONDS < DEADLINE)); do
    if ! kill -0 "$TART_PID" 2>/dev/null; then
        say "vm-test: tart run exited during boot; see the log."
        break
    fi
    CANDIDATE="$(tart ip "$VM" 2>/dev/null)"
    if [[ -n "$CANDIDATE" ]] && ssh -n "${SSH_OPTS[@]}" "$VM_USER@${CANDIDATE}" true 2>/dev/null; then
        IP="$CANDIDATE"
        break
    fi
    sleep 2
done
BOOT_SECS=$((SECONDS - BOOT_START))

guest() { ssh -n "${SSH_OPTS[@]}" "$VM_USER@${IP}" "$@"; }

COPY_SECS=0
COPY_STATUS=1
if [[ -z "$IP" ]]; then
    say "vm-test: the guest did not answer SSH within two minutes of boot."
else
    say "vm-test: guest up after ${BOOT_SECS}s; copying the tree"
    COPY_START=$SECONDS
    rsync -a --delete \
        --exclude .build --exclude /.swiftpm --exclude /.git --exclude /spike/captures \
        -e "ssh ${SSH_OPTS[*]}" \
        "$ROOT/" "$VM_USER@${IP}:$GUEST_TREE/" 2>&1 | tee -a "$LOG"
    COPY_STATUS=${PIPESTATUS[0]}
    COPY_SECS=$((SECONDS - COPY_START))
    if [[ $COPY_STATUS -ne 0 ]]; then
        say "vm-test: the copy failed (rsync exit $COPY_STATUS)."
    fi
fi

STATUS=()
SECS=()
for i in "${!STEPS[@]}"; do
    STATUS[i]="-"
    SECS[i]=0
done

if [[ $COPY_STATUS -eq 0 ]]; then
    for i in "${!STEPS[@]}"; do
        say ""
        say "== [$((i + 1))/${#STEPS[@]}] ${STEPS[i]}"
        T0=$SECONDS
        LOG_BEFORE=$(wc -l <"$LOG")
        guest "$GUEST_ENV cd $GUEST_TREE && ${STEPS[i]}" 2>&1 | tee -a "$LOG"
        STATUS[i]=${PIPESTATUS[0]}
        SECS[i]=$((SECONDS - T0))
        # `swift test` exits 0 when the test process dies partway through a
        # suite: an AppKit run loop ended and the runtime called exit(0)
        # mid-test (ho-05.1). So its exit code alone is not the verdict. A test
        # step passes only if every test target reported its own run passing.
        if [[ "${STATUS[i]}" == "0" && "${STEPS[i]}" == "swift test"* ]]; then
            PASSED=$(tail -n +"$((LOG_BEFORE + 1))" "$LOG" | grep -c "Test run with .* passed")
            if [[ "$PASSED" -ne "$TEST_TARGETS" ]]; then
                STATUS[i]=1
                say "== [$((i + 1))/${#STEPS[@]}] exited 0 but only $PASSED of $TEST_TARGETS test runs reported passing: the test process ended early; counted as a failure"
            fi
        fi
        say "== [$((i + 1))/${#STEPS[@]}] exit ${STATUS[i]} after ${SECS[i]}s"
    done
fi

stop_guest

FAILED=0
[[ $COPY_STATUS -eq 0 ]] || FAILED=1
say ""
say "== vm-test summary"
say "$(printf '  %-6s %5ss  %s' boot "$BOOT_SECS" "guest up and answering SSH")"
say "$(printf '  %-6s %5ss  %s' copy "$COPY_SECS" "rsync, exit $COPY_STATUS")"
for i in "${!STEPS[@]}"; do
    [[ "${STATUS[i]}" == "0" ]] || FAILED=1
    say "$(printf '  exit %-2s %4ss  %s' "${STATUS[i]}" "${SECS[i]}" "${STEPS[i]}")"
done
say "$(printf '  %-6s %5ss  %s' stop "$STOP_SECS" "shutdown in the guest, then tart stop")"
say "$(printf '  %-6s %5ss  %s' total "$((SECONDS - RUN_START))" "boot, copy, six commands, stop")"
if [[ $FAILED -eq 0 ]]; then
    say "vm-test: all six green"
else
    say "vm-test: FAILED"
fi
say "$LOG"
exit "$FAILED"
