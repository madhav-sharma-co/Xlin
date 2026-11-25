#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Summarise the XTILE research boots: one row per boot, nothing is judged here, values are quoted."""
import re, sys, pathlib

def val(t, pat, default="-"):
    m = re.search(pat, t)
    g = [x for x in m.groups() if x] if m else []
    return g[0] if g else default

rows = []
for d in sorted(pathlib.Path(sys.argv[1]).glob("*/")):
    s = d / "serial.log"
    if not s.is_file():
        continue
    t = s.read_text(errors="replace")
    meta = (d / "meta.txt").read_text() if (d / "meta.txt").exists() else ""
    rows.append(dict(
        boot=d.name, done="yes" if "XTILE-GUEST: DONE" in t else "NO",
        cpu=val(meta, r"cpu=(\S+)"), accel=val(meta, r"accel=(\S+)"),
        model=val(t, r"XTILE-GUEST: model name\s*:\s*(.*)"),
        check="FIRED" if re.search(r"XFEATURE_XTILE_DATA: (calculated size|struct is)", t) else "not fired",
        maxleaf=val(t, r"XTILE: vendor=\S+ max_basic_leaf=(\S+)"),
        c7=val(t, r"decoded cpuid7 (amx_bf16=\d+ amx_tile=\d+ amx_int8=\d+)"),
        xcr0bits=val(t, r"decoded leaf0xd.0 supported_xcr0=\S+ (tile_cfg\(bit17\)=\d tile_data\(bit18\)=\d)"),
        l1d=val(t, r"decoded leaf0x1d (max_palette=\d+ palette1 total_tile_bytes=\d+)|decoded leaf0x1d (NOT REACHABLE.*)"),
        amx=val(t, r"AMX_RESULT (\S+)"),
        amxnote=val(t, r"amx test after permission: (.*)|XTILE: (amx test cpuid7.edx amx_tile=0)"),
    ))
print("| boot | accel | -cpu | guest CPU | max leaf | cpuid7 amx bits | leaf 0xd bits 17/18 | leaf 0x1d | kernel check | AMX test |")
print("|---|---|---|---|---|---|---|---|---|---|")
for r in rows:
    print(f"| {r['boot']} | {r['accel']} | `{r['cpu']}` | {r['model']} | {r['maxleaf']} | {r['c7']} | {r['xcr0bits']} | {r['l1d']} | {r['check']} | {r['amx']} ({r['amxnote'][:60]}) |")
