#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
"""XTILE sampler verdict (research only, non-gating).

usage: verdict.py OUT_DIR
  OUT_DIR/runner-probe.txt        native CPUID + KVM_GET_SUPPORTED_CPUID of the runner (xtile-probe cpuid + kvm)
  OUT_DIR/guests/<label>-<n>/serial.log   guests: labels host-<kernel>, level1d-pinned (control)
Writes OUT_DIR/verdict.txt and prints it. Exit code is always 0: this is evidence, not a gate.

A natural reproduction is CONFIRMED only if ALL of these are directly observed on this runner:
  R1 runner native CPUID: AMX-TILE (leaf 7 EDX bit 24) = 1 and max basic leaf < 0x1d
  R2 the runner's KVM offers max leaf equal to the native one (no function 0x1d entry)
  G1 every plain `-cpu host` guest boot completed and reports guest max leaf == runner max leaf, AMX-TILE = 1, leaf 0x1d unreachable
  G2 every one of those guest boots printed the kernel check ("XFEATURE_XTILE_DATA: calculated size is 0 bytes, cpu state 8192 bytes")
  G3 every control boot (`-cpu host,level=0x1d`) reports guest max leaf 0x1d and did NOT print the check
Anything else is reported as NOT CONFIRMED with the failing items, or NO HIT when R1 is false.
The verdict deliberately says nothing about the historical 8573C runners: it only describes this runner.
"""
import glob, os, re, sys

def txt(p):
    try:
        return open(p, errors="replace").read()
    except OSError:
        return ""

def native(probe):
    m = re.search(r"XTILE: vendor=\S+ max_basic_leaf=(0x[0-9a-f]+)", probe)
    a = re.search(r"decoded cpuid7 amx_bf16=\d+ amx_tile=(\d) amx_int8=\d+", probe)
    model = re.search(r"model name\s*:\s*(.*)", probe)
    k0 = re.search(r"kvm supported function=0x0 index=0 .*?eax=([0-9a-f]{8})", probe)
    k1d = re.search(r"kvm supported function=0x1d ", probe)
    return dict(level=int(m.group(1), 16) if m else None, amx=int(a.group(1)) if a else None,
                model=(model.group(1).strip() if model else "?"),
                kvm_level=int(k0.group(1), 16) if k0 else None, kvm_has_1d=bool(k1d))

def guest(path):
    t = txt(path)
    m = re.search(r"XTILE: vendor=\S+ max_basic_leaf=(0x[0-9a-f]+)", t)
    a = re.search(r"decoded cpuid7 amx_bf16=\d+ amx_tile=(\d) amx_int8=\d+", t)
    chk = re.search(r"XFEATURE_XTILE_DATA: (calculated size is \d+ bytes, cpu state \d+ bytes|struct is \d+ bytes, cpu xtile \d+ bytes)", t)
    return dict(done="XTILE-GUEST: DONE" in t, level=int(m.group(1), 16) if m else None,
                amx=int(a.group(1)) if a else None, unreachable="NOT REACHABLE" in t,
                fired=bool(chk), check=(chk.group(0) if chk else None))

def main(out):
    probe = txt(os.path.join(out, "runner-probe.txt"))
    n = native(probe)
    lines = [f"runner: {n['model']}  max_basic_leaf={hex(n['level']) if n['level'] is not None else '?'}  amx_tile={n['amx']}  "
             f"kvm_max_leaf={hex(n['kvm_level']) if n['kvm_level'] is not None else '?'}  kvm_offers_0x1d={n['kvm_has_1d']}"]
    if n["level"] is None or n["amx"] is None:
        lines.append("VERDICT: NO DATA (the native probe produced no CPUID lines)")
    elif not (n["amx"] == 1 and n["level"] < 0x1d):
        lines.append("VERDICT: NO HIT (R1 false: this runner does not have AMX-TILE set with a max basic leaf below 0x1d)")
    else:
        fails = []
        if n["kvm_level"] != n["level"] or n["kvm_has_1d"]:
            fails.append("R2: the runner's KVM does not offer the same max leaf / offers function 0x1d")
        plain = sorted(glob.glob(os.path.join(out, "guests", "host-*-*", "serial.log")))
        ctrl = sorted(glob.glob(os.path.join(out, "guests", "level1d-*-*", "serial.log")))
        if not plain:
            fails.append("G1: no plain -cpu host guest logs")
        if not ctrl:
            fails.append("G3: no control (level=0x1d) guest logs")
        for p in plain:
            g, b = guest(p), os.path.basename(os.path.dirname(p))
            lines.append(f"  guest {b}: done={g['done']} level={hex(g['level']) if g['level'] is not None else '?'} amx_tile={g['amx']} "
                         f"leaf0x1d_unreachable={g['unreachable']} check={'FIRED: ' + g['check'] if g['fired'] else 'not fired'}")
            if not g["done"]: fails.append(f"G1 {b}: guest did not complete")
            if g["level"] != n["level"]: fails.append(f"G1 {b}: guest max leaf {g['level']} != runner {n['level']}")
            if g["amx"] != 1: fails.append(f"G1 {b}: guest AMX-TILE is {g['amx']}")
            if not g["unreachable"]: fails.append(f"G1 {b}: leaf 0x1d reachable in guest")
            if not (g["fired"] and g["check"] and "calculated size is 0 bytes, cpu state 8192 bytes" in g["check"]):
                fails.append(f"G2 {b}: expected check message not printed (found: {g['check']})")
        for p in ctrl:
            g, b = guest(p), os.path.basename(os.path.dirname(p))
            lines.append(f"  control {b}: done={g['done']} level={hex(g['level']) if g['level'] is not None else '?'} amx_tile={g['amx']} "
                         f"check={'FIRED: ' + g['check'] if g['fired'] else 'not fired'}")
            if not g["done"]: fails.append(f"G3 {b}: guest did not complete")
            if g["level"] != 0x1d: fails.append(f"G3 {b}: control guest max leaf {g['level']} != 0x1d")
            if g["fired"]: fails.append(f"G3 {b}: check fired although the guest max leaf is 0x1d")
        if fails:
            lines.append("VERDICT: NOT CONFIRMED (runner HIT, but) " + "; ".join(fails))
        else:
            lines.append("VERDICT: NATURAL REPRODUCTION CONFIRMED on this runner (R1, R2, G1, G2, G3 all observed)")
    lines.append("NOTE: this describes only this runner; it does not by itself show that the earlier failing 8573C runners were configured the same way.")
    s = "\n".join(lines) + "\n"
    open(os.path.join(out, "verdict.txt"), "w").write(s)
    print(s, end="")

if __name__ == "__main__":
    main(sys.argv[1])
