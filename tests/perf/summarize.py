#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Median of each XLIN-BENCH metric per kernel (xlin / arch) across the run logs. Informational."""
import glob, os, re, statistics, sys
d = sys.argv[1]
data = {}
for f in sorted(glob.glob(os.path.join(d, "*.log"))):
    k = os.path.basename(f).split("-")[0]
    for l in open(f, errors="replace"):
        m = re.match(r"XLIN-BENCH: (\S+) ([\d.]+) (\S+)", l)
        if m: data.setdefault(m.group(1), {}).setdefault(k, []).append((float(m.group(2)), m.group(3)))
print("### Performance baseline (medians; informational, shared runner, no claim of faster or slower)\n")
print("| metric | unit | Xlin 6.18.64 | Arch linux-lts | samples (xlin/arch) |\n|---|---|---|---|---|")
for n, kv in data.items():
    def med(k):
        v = kv.get(k, []); return statistics.median(x[0] for x in v) if v else None
    u = (kv.get("xlin") or kv.get("arch"))[0][1]
    x, a = med("xlin"), med("arch")
    print(f"| {n} | {u} | {x if x is None else round(x, 2)} | {a if a is None else round(a, 2)} | {len(kv.get('xlin', []))}/{len(kv.get('arch', []))} |")
if not data or "xlin" not in next(iter(data.values())): print("\n**No Xlin benchmark output was found.**"); sys.exit(1)
