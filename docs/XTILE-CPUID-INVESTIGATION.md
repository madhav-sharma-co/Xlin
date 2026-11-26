# XTILE-CPUID investigation record

Reproduced from the research branch `research/xtile-cpuid` (commit `cce518c5bc6791c4be4122f96f64eb60509a25c8`, kept unchanged). The research
workflow, probe and scripts (`.github/workflows/xtile-research.yml`, `tests/research/xtile/`) exist **only on that branch**, not in this PR. The archived CI job logs
(`xtile-cpuid-evidence.tar.gz`) were delivered separately in the session; per-boot serial logs are CI artifacts (30-day retention).
This investigation is **not closed**.

Status of the finding in `tests/runtime/known-findings.txt`: **EXPLAINED-OPEN (unchanged)**. Nothing was allowlisted,
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

- QEMU 8.2.2 (Ubuntu `1:8.2.2+ds-0ubuntu1.18`, runner package) and 11.1.3 (Arch container package) (`target/i386/cpu.c`, `if (index > limit) index = env->cpuid_level`, and `case 0x1D` is generated purely from the guest AMX-TILE bit)
  do not raise the guest's maximum leaf for AMX: the level is only raised for PT (0x14), 0x1F, 0x24, 0x29, 0x12 in both versions.
- Under `-cpu host` the guest level equals the level the runner's KVM offers, which equals the runner's own CPUID level
  (observed: 6975P-C 0x24 -> guest 0x24; EPYC 9V74 0x1c -> guest 0x1c; Xeon Platinum 8573C 0x1c -> guest 0x1c).
- Reproduction: on 6975P-C hosts (AMX exposed, level 0x24), forcing `-cpu host,level=0x1c` makes the check fire; `level=0x1d` or the default does not;
  `level=0x1c,-amx-tile` does not. 212 of 212 boots with AMX-TILE=1 and level 0x1c fired; 0 of all boots with AMX-TILE=1 and level >= 0x1d, and 0 with AMX-TILE=0
  (parsed from CI job logs, 1686 boots). It holds for four kernels (Xlin 6.18.64 pinned, vanilla 6.18.65, mainline 8d7fe9885c62, Arch linux-lts 6.18.x)
  and two QEMU versions (8.2.2 and 11.1.3). Table in section 5.

Conclusion on origin: not attributable to Xlin code or Xlin configuration (the same behaviour appears on vanilla and Arch kernels). The experiments support a VMM-layer
explanation: the runner presents level 0x1c with AMX enabled and QEMU copies the level without lifting it for AMX. **Responsibility is not conclusively assigned** among the
hypervisor (an inconsistent CPUID), QEMU (not raising the level when AMX is enabled), and the kernel (not validating the maximum leaf before reading leaf 0x1d); that is a judgement, not a measurement.

## 3. What is NOT established

- **The original failure is not conclusively explained.** The historical host state of the failing runners is not directly established (the old logs do not record the guest CPUID level).
- **TCG counts (corrected 2026-11-26).** The earlier claims of the message in "1 of 136" (`docs/RUNTIME-VALIDATION.md`) and "1 of 56" (`known-findings.txt`) TCG boots are **unsupported and unreproducible**. Per-boot evidence is **0 of 248 TCG boots across 31 runs** (46 Kernel build runs' `runtime-test` job logs inspected, 31 with TCG scenarios, 8 TCG boots each; a boot = one `serial.log .../run-tcg/<name>/` block). Scope: Xlin kernel, QEMU TCG on any assigned runner host (including the 8573C run 45329083569, whose 8 TCG blocks did not fire while its 40 KVM blocks all did), job logs only, 15 older runs without TCG scenarios excluded, the 68 research TCG boots (also 0) not included. The old denominators (7 and 17 jobs) came from unrecorded, unrebuildable log sets and are kept only as superseded history. The origin of the stray "1" is unknown; a section-based parse that credits post-run serial dumps to the last TCG header of run 45329083569 yields exactly 1, which is plausible but unproven (the original script was not preserved). This is consistent with the mechanism: QEMU TCG `-cpu max` advertises no AMX.

- **No natural reproduction in this investigation.** The real failing class (Xeon Platinum 8573C with AMX exposed: 43 boot events in runtime-test run 45329083569 on 2026-11-24 = 40 VM boots plus 3 warm reboots of one VM, and Arch linux-lts under QEMU 11.1.3, 6 of 6 boots in run 45167768437 on 2026-11-23) did not occur again:
  all 3 Xeon Platinum 8573C runners that landed on 2026-11-25 (64 research jobs over 4 runs) exposed no AMX (leaf 7 EDX=0x20000010, leaf 0xd EAX=0xe7, level 0x1c) and did not fire.
  That the earlier failing runners had level 0x1c is **inferred** (same CPU model reports level 0x1c today; the old logs do not record the guest level; QEMU 8.2.2 gives no other route to an empty leaf 0x1d with AMX-TILE set).
- Why the 8573C runners exposed AMX on 11-23/24 but not on 11-25 (fleet/host configuration): unknown, not visible from inside the runner.
- AMX functional testing (see section 4) was done only in guests with AMX on 6975P-C/6973P-C hosts, including guests where the check fired by `level=0x1c` on 6975P-C/6973P-C hosts (arch_prctl permission, ldtilecfg/tilezero/tilestored, and in the last run a TDPBSSD int8 multiply with a known result; the TDPBSSD test exists only from run 45618759770, earlier runs had the zero/store test only). Not tested: bf16/fp16 paths, context switch / signal frames / ptrace / XFD with several threads, long-running load, performance, real failing hosts, bare metal.
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

Methodology: GitHub Actions `ubuntu-24.04` runner jobs (image 20261116.376.1) sample whatever host class is assigned; each job records the runner's native CPUID (static probe),
the KVM-offered CPUID (`KVM_GET_SUPPORTED_CPUID`), then boots the kernels under test with a throw-away static BusyBox + probe initramfs, same QEMU, OVMF, q35, 2 vCPU, 1024 MiB. Boots were counted per serial log; the counts above
were parsed from the **CI job logs** (the artifacts were not downloadable from the session). Lines interleaved with kernel output can be lost in that parsing, so every count is a **lower bound** on the boots that happened.

## 6. Smallest next experiment

Re-run `xtile-research.yml` until a runner with `leaf 7 EDX bit 24 = 1` **and** `max leaf 0x1c` appears (the probe's first lines show it). Expected if the inference is right: guest level 0x1c under plain `-cpu host`, check fires, and `host,level=0x1d` removes it.
If a failing runner shows level >= 0x1d, the inference is wrong and the leaf 0x1d content itself must be examined.

## 7. Follow-up status

- Applied in PR #5 (documentation and finding text only): this record, the updated XTILE-CPUID summary in `tests/runtime/known-findings.txt`, and `docs/RUNTIME-VALIDATION.md`. The status remains EXPLAINED-OPEN; scanner, allowlist and self-test expectations are unchanged.
- Still to decide with Madhav (not done): moving the research workflow/probe into the main tree, adding the guest maximum leaf to the scanner's informational finding text, and whether any upstream follow-up is wanted (for example kernel-side validation of the maximum leaf before reading leaf 0x1d). Nothing is sent upstream.
- Re-open for confirmation when a runner with AMX set and maximum leaf 0x1c appears (section 6).
