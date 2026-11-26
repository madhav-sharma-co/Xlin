# XTILE-CPUID investigation (research record; branch `research/xtile-cpuid`, not part of PR #5)

Status of the finding in `tests/runtime/known-findings.txt`: **unchanged, EXPLAINED-OPEN**. Nothing was allowlisted,
suppressed or weakened; no kernel source, configuration or pin was touched. This document records what was
measured, what is inferred, and what is still untested.

## 1. The check, expected and observed values

- Code: `check_xtile_data_against_struct()` in `arch/x86/kernel/fpu/xstate.c` (pinned 6.18.64, same in 6.18.65 and mainline),
  called from `xfeature_enabled`/size validation for `XFEATURE_XTILE_DATA`. It reads **CPUID leaf 0x1d**: subleaf 0 `eax` = highest
  palette id; for each palette `eax[31:16]` = bytes per tile (kernel expects `sizeof(struct xtile_data)` = 1024) and
  `ebx[31:16]` = number of tiles; it then compares `bytes_per_tile * tiles` with the size leaf 0xd advertises (8192).
  The return value is ignored by the caller (the kernel continues and enables AMX); it only logs.
- Expected (healthy AMX CPU, e.g. 6975P-C guest): leaf 0x1d.0 `eax`=1; 0x1d.1 `eax`=0x04002000 (1024 B/tile, 8192 total), `ebx`=0x00080040 (8 tiles, 64 B/row), `ecx`=16.
- Observed in the failing guests: `XFEATURE_XTILE_DATA: calculated size is 0 bytes, cpu state 8192 bytes` followed by the leaf dump
  (`CPUID[0d, 12]: eax=00002000 ... `, leaf 0xd.0 `eax`=000600e7 i.e. tile config+data advertised). The mismatch occurs
  at the very first read: leaf 0x1d.0 `eax` = 0, so the palette loop never runs and the calculated size is 0.

## 2. Mechanism (established by controlled reproduction)

The guest's CPUID maximum basic leaf was below 0x1d while `CPUID.7.0:EDX[24]` (AMX-TILE) was set. Per the Intel SDM (and as QEMU
implements it) a query above the maximum leaf returns the data of the maximum leaf, so leaf 0x1d reads as leaf 0x1c data (eax=0 here).

- QEMU 8.2.2 and 11.1.3 (`target/i386/cpu.c`, `if (index > limit) index = env->cpuid_level`, and `case 0x1D` is generated purely from the guest AMX-TILE bit)
  do not raise the guest's maximum leaf for AMX: the level is only raised for PT (0x14), 0x1F, 0x24, 0x29, 0x12 in both versions.
- Under `-cpu host` the guest level equals the level the runner's KVM offers, which equals the runner's own CPUID level
  (observed: 6975P-C 0x24 -> guest 0x24; EPYC 9V74 0x1c -> guest 0x1c; Xeon Platinum 8573C 0x1c -> guest 0x1c).
- Reproduction: on 6975P-C hosts (AMX exposed, level 0x24), forcing `-cpu host,level=0x1c` makes the check fire; `level=0x1d` or the default does not;
  `level=0x1c,-amx-tile` does not. 212 of 212 boots with AMX-TILE=1 and level 0x1c fired; 0 of all boots with AMX-TILE=1 and level >= 0x1d, and 0 with AMX-TILE=0
  (parsed from CI job logs, 1686 boots). It holds for four kernels (Xlin 6.18.64 pinned, vanilla 6.18.65, mainline 8d7fe9885c62, Arch linux-lts 6.18.x)
  and two QEMU versions (8.2.2 and 11.1.3). Table in section 5.

Conclusion on origin (QEMU / host / guest config / Xlin code): **not Xlin code or Xlin configuration** (identical on vanilla and Arch kernels).
The inconsistent CPUID (AMX-TILE advertised, leaf 0x1d unreachable) comes from the VMM layer: the runner presents level 0x1c, QEMU copies it and does not lift it for AMX.
Which party is "at fault" (Hyper-V/Azure presenting an inconsistent CPUID, QEMU not raising the level, or the kernel not checking the max leaf) is a judgement, not a measurement.

## 3. What is NOT established

- **No natural reproduction in this investigation.** The real failing class (Xeon Platinum 8573C with AMX exposed, 43+ boots on 2026-11-23/24, also Arch linux-lts under QEMU 11.1.3 in run 45167768437) did not occur again:
  all 3 Xeon Platinum 8573C runners that landed on 2026-11-25 (64 research jobs over 4 runs) exposed no AMX (leaf 7 EDX=0x20000010, leaf 0xd EAX=0xe7, level 0x1c) and did not fire.
  That the earlier failing runners had level 0x1c is **inferred** (same CPU model reports level 0x1c today; the old logs do not record the guest level; QEMU 8.2.2 gives no other route to an empty leaf 0x1d with AMX-TILE set).
- Why the 8573C runners exposed AMX on 11-23/24 but not on 11-25 (fleet/host configuration): unknown, not visible from inside the runner.
- AMX functional testing was done only in guests where the check fired by `level=0x1c` on 6975P-C/6973P-C hosts (arch_prctl permission, ldtilecfg/tilezero/tilestored, and in the last run a TDPBSSD int8 multiply with a known result). Not tested: bf16/fp16 paths, context switch / signal frames / ptrace / XFD with several threads, long-running load, performance, real failing hosts, bare metal.
- Whether the kernel should check the maximum leaf (a possible upstream improvement) was not researched upstream; no report is sent.

## 4. Effect on AMX

In every boot where the check fired (212) the guest kernel nevertheless enabled AMX (`Supporting XSAVE feature 0x40000`) and user space could use it:
`arch_prctl(ARCH_REQ_XCOMP_PERM, 18)` succeeded, tile config/zero/store gave correct bytes, and the TDPBSSD multiply (run 45618759770, 256 AMX guests) was correct.
So within the limits above the message is a log-level inconsistency check; no functional AMX loss was observed.

## 5. Reproducible evidence

Workflow `.github/workflows/xtile-research.yml` (branch-scoped push trigger, non-gating), probe `tests/research/xtile/xtile-probe.c`, runs on branch `research/xtile-cpuid`:
45614681593 (6 jobs), 45615681036 (10), 45617083988 (12 Ubuntu + 12 Arch/QEMU 11), 45618759770 (same). Per-boot serial logs are CI artifacts `xtile-research-*` (30 days).
Job logs were also archived (see the evidence tarball delivered with the report).

| QEMU | -cpu | guest AMX-TILE | guest max leaf | boots | check fired |
|---|---|---|---|---|---|
| 8.2.2 / 11.1.3 | host | 1 | 0x24 | 456 (all 4 kernels) | 0 |
| 8.2.2 / 11.1.3 | host,level=0x1c | 1 | 0x1c | 212 | **212** |
| 8.2.2 / 11.1.3 | host,level=0x1d | 1 | 0x1d | 68 | 0 |
| 8.2.2 / 11.1.3 | host,level=0x1c,-amx-tile | 0 | 0x1c | 116 | 0 |
| 8.2.2 | SapphireRapids | 1 | 0x20 | 63 | 0 |
| 8.2.2 | host,+amx-tile,+amx-int8,+amx-bf16 | 1 | 0x24 | 63 | 0 |
| 8.2.2 | max (TCG) | 0 | 0xd | 68 | 0 |

(Rows exclude hosts without AMX; counts parsed from logs, so a few rows interleaved with kernel output may be missing; treat as lower bounds.)

## 6. Smallest next experiment

Re-run `xtile-research.yml` until a runner with `leaf 7 EDX bit 24 = 1` **and** `max leaf 0x1c` appears (the probe's first lines show it). Expected if the inference is right: guest level 0x1c under plain `-cpu host`, check fires, and `host,level=0x1d` removes it.
If a failing runner shows level >= 0x1d, the inference is wrong and the leaf 0x1d content itself must be examined.

## 7. Proposed (not applied) changes

- Keep XTILE-CPUID EXPLAINED-OPEN until the natural reproduction above; then update its summary with this mechanism (and decide the status with Madhav).
- Optionally teach the scanner's finding text to include the guest max leaf (informational; no weakening).
- Optional upstream follow-up (kernel could skip/qualify the check when the max leaf < 0x1d) is a separate decision; nothing is sent.
