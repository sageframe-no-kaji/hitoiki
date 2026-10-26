#!/usr/bin/env bash
# Enforces the line-coverage floor on IssokuCore. Assumes
# `swift test --enable-code-coverage` has already run.
#
#   IssokuCore ≥ $1 (default 90) — the headless library: Run and the
#   Transcript model. The truth lives in the core.
#
# Sources/Issoku, the surface, is excluded from the floor: its views cannot
# be driven headless. The Theme palette in that target is tested regardless,
# through its pure `resolved(dark:)` seam. Whether an application-logic floor
# is added for Sources/Issoku is a ho-03 decision.

set -euo pipefail

FLOOR="${1:-90}"
PROFDATA=.build/debug/codecov/default.profdata

# Swift 6.4's default build system (Swift Build) writes one bundle per test
# target (.build/debug/<Target>Tests.xctest), not a single
# <Package>PackageTests.xctest. Every bundle's binary is handed to llvm-cov:
# the first as the positional binary, the rest as `-object`.
BINARIES=()
for binary in .build/debug/*.xctest/Contents/MacOS/*; do
    if [[ -f "$binary" ]]; then
        BINARIES+=("$binary")
    fi
done
if [[ ${#BINARIES[@]} -eq 0 ]]; then
    echo "coverage-floor: no test binaries under .build/debug/*.xctest — run swift test --enable-code-coverage first"
    exit 1
fi
OBJECTS=()
for binary in "${BINARIES[@]:1}"; do
    OBJECTS+=(-object "$binary")
done

# Sources/IssokuRunCLI, the ho-02 run-sheet driver, is excluded like the surface: it is a driver
# with no tests of its own, and ho-03 deletes it.
IGNORE='(Tests/|\.build/|Sources/Issoku/|Sources/IssokuRunCLI/)'

echo "== IssokuCore =="
xcrun llvm-cov report "${BINARIES[0]}" ${OBJECTS[@]+"${OBJECTS[@]}"} \
    -instr-profile "$PROFDATA" \
    -ignore-filename-regex="$IGNORE"

echo
xcrun llvm-cov export "${BINARIES[0]}" ${OBJECTS[@]+"${OBJECTS[@]}"} \
    -instr-profile "$PROFDATA" \
    -ignore-filename-regex="$IGNORE" \
    -summary-only \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)['data'][0]
files = [f['filename'] for f in data['files']]
# ho-02 turns this into a failure once IssokuCore holds code.
if not files:
    print('IssokuCore: nothing to measure yet; the floor applies from the first code in Sources/IssokuCore')
    sys.exit(0)
percent = data['totals']['lines']['percent']
print(f'IssokuCore line coverage: {percent:.2f}% over {len(files)} files (floor: $FLOOR%)')
sys.exit(0 if percent >= $FLOOR else 1)
"
