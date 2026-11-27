#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tabulate kselftest results. usage: report.py results.txt not-built.txt expected.txt

expected.txt lines: "<target>/<program> <PASS|FAIL|SKIP|TIMEOUT> <reason>" for every result that is
not a plain PASS, each with the reason it is understood. Exit 1 if a result differs from its
expectation (a new failure, or an expected one that changed), or if nothing ran."""
import re, sys
res, nb, exp = sys.argv[1:4]
got = {}
for l in open(res, errors="replace"):
    m = re.match(r"XLIN-KSELFTEST: (\S+/\S+) (PASS|FAIL|SKIP|TIMEOUT) rc=(\d+)", l)
    if m: got[m.group(1)] = (m.group(2), m.group(3))
expected = {}
try:
    for l in open(exp):
        l = l.strip()
        if l and not l.startswith("#"):
            p = l.split(None, 2); expected[p[0]] = (p[1], p[2] if len(p) > 2 else "")
except FileNotFoundError:
    pass
cnt = {}
for v in got.values(): cnt[v[0]] = cnt.get(v[0], 0) + 1
print("### kselftest results (Xlin Kernel, QEMU)\n")
print("| result | programs |\n|---|---|")
for k in ("PASS", "SKIP", "FAIL", "TIMEOUT"): print(f"| {k} | {cnt.get(k, 0)} |")
print(f"\n{len(got)} programs ran.\n")
bad = []
rows = []
for k, (r, rc) in sorted(got.items()):
    e = expected.get(k)
    if r == "PASS":
        if e: bad.append(f"{k}: expected {e[0]} but PASSED")
        continue
    if not e: bad.append(f"{k}: {r} rc={rc}, not in expected.txt"); rows.append(f"| {k} | {r} | rc={rc} | **UNEXPECTED** |")
    elif e[0] != r: bad.append(f"{k}: {r}, expected {e[0]}"); rows.append(f"| {k} | {r} | rc={rc} | **expected {e[0]}** |")
    else: rows.append(f"| {k} | {r} | rc={rc} | {e[1]} |")
for k in expected:
    if k not in got: bad.append(f"{k}: listed in expected.txt but did not run")
if rows: print("| program | result | exit | understanding |\n|---|---|---|---|"); print("\n".join(rows))
print("\n#### Not built / not run\n"); print("```"); print(open(nb).read().strip() or "(none)"); print("```")
if not got: bad.append("no kselftest program ran")
print("\n**" + ("MATCHES expected.txt" if not bad else "DIFFERS from expected.txt") + "**")
for b in bad: print("-", b)
sys.exit(1 if bad else 0)
