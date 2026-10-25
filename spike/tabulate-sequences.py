#!/usr/bin/env python3
"""Tabulate the terminal-control sequences in ho-01 raw captures.

Usage: python3 -I spike/tabulate-sequences.py spike/captures/cmd-{1..12}.raw spike/captures/cmd-{14..20}.raw

One Markdown row per capture: the distinct non-SGR escape sequences with their counts,
the distinct C0 controls other than CR, LF, and TAB, the number of overwriting carriage
returns (a CR followed by anything but CR or LF), and the number of distinct SGR sequences.
The grammar is the plain-text model's (spike/Sources/IssokuSpike/PlainModel.swift).
"""

import collections
import re
import sys

ESC = 0x1B


def show(seq: bytes) -> str:
    out = []
    for b in seq:
        if b == ESC:
            out.append("ESC ")
        elif b < 0x20 or b == 0x7F:
            out.append(f"<{b:02X}>")
        else:
            out.append(chr(b))
    return "`" + "".join(out).replace("|", "\\|") + "`"


def scan(data: bytes):
    non_sgr = collections.Counter()
    sgr = set()
    controls = collections.Counter()
    overwrites = 0
    i, n = 0, len(data)
    while i < n:
        b = data[i]
        if b == ESC and i + 1 < n:
            nxt = data[i + 1]
            if nxt == ord("["):
                m = re.compile(rb"\x1b\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]").match(data, i)
                if m:
                    seq = m.group(0)
                    if seq.endswith(b"m") and not re.search(rb"[\x20-\x2f]", seq[2:-1]):
                        sgr.add(seq)
                    else:
                        non_sgr[seq] += 1
                    i = m.end()
                    continue
            elif nxt in b"]PX^_":
                m = re.compile(rb"\x1b[\]PX^_].*?(\x07|\x1b\\)", re.S).match(data, i)
                terminator = b"BEL" if m and m.group(1) == b"\x07" else b"ST"
                non_sgr[data[i:i + 2] + b"...(" + terminator + b")"] += 1
                i = m.end() if m else n
                continue
            m = re.compile(rb"\x1b[\x20-\x2f]*[\x30-\x7e]").match(data, i)
            if m:
                non_sgr[m.group(0)] += 1
                i = m.end()
                continue
        if b == 0x0D:
            if i + 1 < n and data[i + 1] not in (0x0A, 0x0D):
                overwrites += 1
        elif b < 0x20 and b not in (0x0A, 0x09, ESC):
            controls[bytes([b])] += 1
        i += 1
    return non_sgr, sgr, controls, overwrites


def cell(counter) -> str:
    if not counter:
        return "none"
    return ", ".join(f"{show(k)} ×{v}" for k, v in sorted(counter.items()))


def main(paths) -> None:
    print("| Capture | Bytes | Non-SGR escape sequences | Other C0 controls | Overwriting CR | Distinct SGR |")
    print("|---|---|---|---|---|---|")
    for path in paths:
        with open(path, "rb") as f:
            data = f.read()
        non_sgr, sgr, controls, overwrites = scan(data)
        name = path.rsplit("/", 1)[-1]
        print(f"| {name} | {len(data)} | {cell(non_sgr)} | {cell(controls)} | {overwrites} | {len(sgr)} |")


if __name__ == "__main__":
    main(sys.argv[1:])
