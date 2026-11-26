<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin Kernel runtime validation (Phase B, Step 6)

This document describes what the expanded runtime validation checks, how, and — equally important — what it does **not** show.

**Scope statement.** Everything here runs in QEMU virtual machines booted through OVMF with the kernel loaded directly (`-kernel`/`-initrd`, so the EFI stub runs). It does not test Xlin Boot, physical hardware, drivers whose hardware QEMU cannot emulate, or XlinOS userspace. A pass is evidence about the Xlin Kernel in those virtual machines, nothing more. It is not a statement of hardware compatibility or production readiness.

The existing source, configuration, build and boot checks (Steps 2–5) are unchanged and still run.

## Layout

| Part | File |
|---|---|
| Probe table (what is checked, expected value, required kernel options) | `tests/runtime/probes.tsv` |
| Probe-to-option map tool | `scripts/xlin-probe-map` |
| Guest `/init`, helpers, suites | `tests/runtime/` |
| Reviewed kernel-log allowlist | `tests/runtime/dmesg-allowlist.txt` |
| Known unresolved findings | `tests/runtime/known-findings.txt` |
| Test disk images builder | `scripts/xlin-test-images` |
| Initramfs builder (`--runtime`, `--kmod`) | `scripts/xlin-initramfs` |
| Host runner and judge | `scripts/xlin-runtime-test` |
| Informational comparison | `scripts/xlin-runtime-compare` |
| Simulated-guest self-test | `tests/runtime-selftest.sh` |
| CI | `runtime-test`, `arch-baseline`, `runtime-compare` jobs in `.github/workflows/kernel-build.yml` |

Run locally (needs a build, QEMU, OVMF, static BusyBox and `kmod`):

```sh
scripts/xlin-initramfs --runtime --kmod /usr/bin/kmod --out build/runtime-test/initramfs.cpio.zst
scripts/xlin-test-images --out build/runtime-test/images --modules-tar build/xlin-x86_64/report/modules-*.tar.zst
scripts/xlin-runtime-test --config build/xlin-x86_64/report/config-final --scenarios all --repeat 1
scripts/xlin-runtime-test --scenarios base --matrix auto --repeat 3
```

## How a result is decided

The guest prints one line per check, `XLIN-TEST: <suite> <name> PASS|FAIL|SKIP|INFO <detail>`, and `XLIN-METRIC:` lines for measurements. The host runner decides a run **passes** only if all of these hold: the kernel reports the expected release; it booted through UEFI; there was no panic, oops or BUG; `/init` ran and printed `XLIN-RUNTIME: DONE`; every requested suite ran to its end; no check failed; every suite produced a pass (or an explained skip); QEMU exited with status 0 within the time limit; and, for the `config` suite, the guest's `/proc/config.gz` is byte-identical (SHA-256) to the final `.config` of the build.

* **SKIP means not tested**, always with a reason. It is never counted as a pass.
* A scenario whose required kernel options are not set in the build's `.config`, or whose disk image could not be built, is reported **NOT TESTED** with the reason, never as a pass and never silently dropped.
* A failing run keeps its full `serial.log`, the QEMU command line, and is classified (firmware / kernel before `/init` / kernel panic / runtime check failed / timeout / test) with the earliest error line.
* `--repeat N` boots each run N times; the summary shows the flake rate (failed boots / boots).
* Measurements are **informational** and never gate a result.

`tests/runtime-selftest.sh` checks the judge itself with a simulated guest (fake `qemu` printing canned logs): that a failed check, a missing `DONE`, a missing suite end, a panic, a wrong config hash, a wrong release or a non-zero QEMU exit each fail a run, that NOT TESTED and findings are reported, and that the flake rate is computed. It is not a boot test.

## `/proc/config.gz`

The approved configuration contains `CONFIG_IKCONFIG=y` and `CONFIG_IKCONFIG_PROC=y` (verified before the test was designed; the configuration was not changed for this step). The guest decompresses `/proc/config.gz`, prints its SHA-256, and the runner compares it with the SHA-256 of the build's `report/config-final`.

## Hardening and systemd probes

Every probe in `tests/runtime/probes.tsv` names the kernel options it depends on. CI runs `scripts/xlin-probe-map` against the real final `.config` and against the pinned Kconfig (so a misspelled option fails), and the guest checks the same options in its own `/proc/config.gz` before running a probe: a probe whose option is absent is **SKIP — UNSUPPORTED by this kernel's configuration**, with the option named.

Probes are *behavioural* where the kernel exposes behaviour (KASLR moved `_text`; `dmesg_restrict`; Yama's `ptrace_scope`; unprivileged BPF disabled; `init_on_alloc` in the boot log; no `[vsyscall]` mapping; `/dev/mem` refuses to read system RAM above 1 MiB; user, net, UTS, IPC and PID namespaces can be created; cgroup v2 mounts with controllers; seccomp, PSI, inotify, DMI, efivarfs). Where the kernel has no runtime view, the probe is **config only** and is labelled so in its result (stack protector, FORTIFY_SOURCE, hardened usercopy, VMAP_STACK, slab hardening, kernel-stack offset randomisation, module signing, and several systemd-required options): it proves the option is in the running kernel's own configuration, not that the mechanism works.

`SHUFFLE_PAGE_ALLOCATOR` is reported as *configured, not active*: the option is compiled in, but the runtime switch (`page_alloc.shuffle`) is off unless set on the command line or enabled by memory-side-cache hardware.

## Scenarios

`scripts/xlin-runtime-test --list` prints them. One QEMU boot each.

| Scenario | What is checked |
|---|---|
| `base` | `/proc/config.gz` identity, hardening and systemd probes, kernel-log scan, measurements |
| `modules` | every module loaded and unloaded with kmod; all signed; tampered module refused; unsigned-module behaviour with `sig_enforce` |
| `blk-virtio`, `blk-scsi`, `blk-ahci`, `blk-nvme`, `blk-usb` | disk appears, bound to the expected driver chain, ext4 read, write, sync, remount, checksum |
| `rng` | virtio-rng registered as the hardware RNG and produces data |
| `net-virtio`, `net-e1000e`, `net-igb` | NIC driver, link, DHCP lease and ICMP echo to the QEMU gateway (user-mode networking) |
| `gfx-std`, `gfx-virtio` | `/dev/fb0`, DRM card, framebuffer console messages (pixel contents are **not** checked) |
| `fs` | ext4, FAT, squashfs, overlayfs (squashfs lower + tmpfs upper), ISO 9660, UDF, Btrfs, XFS, NTFS3, tmpfs; FUSE availability |
| `stress` | short CPU, memory, fork and I/O stress, then a kernel-log and taint check |
| `reboot` | three warm reboots of one VM (counter on a scratch disk), then the base checks |

The boot matrix runs `base` over vCPU counts 1, 2, 4, 8 and memory 256 MiB to 4 GiB under KVM (3 boots each), and a reduced matrix under software emulation (TCG, 2 boots each).

## Kernel-log scan

The `logscan` suite scans the whole kernel log. Every line that looks like a warning or error (level warning or worse, or words such as warning/error/fail/BUG/Oops/taint/lockdep) falls into exactly one of three tiers:

1. **Accepted environment notice** — listed with a reason in `tests/runtime/dmesg-allowlist.txt`. Reported as `INFO allowed`. An entry may carry the scope `tcg`, meaning it is accepted only when the guest runs under QEMU software emulation (recognised by the CPU model name `QEMU TCG CPU`); under KVM the same line fails.
2. **Known, unresolved finding** — listed in `tests/runtime/known-findings.txt` with an ID and a status (`OPEN`, `EXPLAINED-OPEN` or `EXPLAINED-UPSTREAM`; the last means upstream has analysed and consciously kept the message, and it is still reported, never accepted as normal). Reported as `FINDING` in every boot where it appears and as `INFO ... not observed in this boot` where it does not. It does not fail a run, but it is never accepted either: the run is reported as **PASS WITH OPEN FINDINGS** (not a clean pass), the summary carries the verdict, the finding, its status and the number of boots in which it appeared, CI prints a warning annotation, and `xlin-runtime-test --strict-findings` turns it into exit status 4.
3. **Unexpected** — anything else. `FAIL`.

The scanner was not relaxed to introduce tier 2; `tests/runtime-selftest.sh` runs the scanner script itself against canned logs (unknown warning fails, allowlisted notice passes, a known finding is a FINDING and not allowlisted, TCG-scoped notice fails on a KVM guest, tainted kernel fails).

## Test components and licensing

See `docs/LICENSING.md`. kmod, the filesystem tools and QEMU/OVMF are installed on the CI runner from its distribution (package versions are printed in the job summary); none of their files is committed. The test initramfs and disk images are build outputs and are not committed.

## Known gaps (honest list)

* Not tested: physical hardware; drivers for hardware QEMU cannot emulate here (r8169, tg3, igc, i915, amdgpu, Wi-Fi, TPM); Xlin Boot; XlinOS.
* exFAT is not tested: no tool can populate an exFAT image without mounting it (root).
* FUSE is checked for availability only; no userspace FUSE daemon is run.
* Framebuffer pixel contents are not checked.
* Several hardening items are config-only (see above).
* CI timings come from shared runners and are noisy; TCG is slow, so its matrix is small.
* The `modules` scenario loads modules without their hardware: modules that return `ENODEV` are classified as needing absent hardware, which is not the same as working.
* The Arch `linux-lts` baseline is optional and non-gating; it has its own configuration and build options, so a difference to it is not attributable to a specific Xlin choice.
* Results are a point-in-time observation of the pinned source and approved configuration in CI.

## Results

Observed in CI on 2026-11-22/23 with the pinned Linux 6.18.64 and the approved configuration (kernel `bzImage` 12,174,336 bytes, 39 modules, 9,729,035 bytes compressed). The runs below used a kernel built by an earlier run of this same branch's CI; the pull request's own full run (build included) is the final confirmation. QEMU/KVM on shared GitHub runners; numbers are indicative only.

**Scenarios (KVM, one boot each): all 16 passed.** Boot, `/proc/config.gz` byte-identical to the build's `.config`; 30 checks passed, 2 not tested in `base`; virtio-blk, virtio-scsi, AHCI, NVMe, USB storage (xHCI), virtio-rng, standard VGA, virtio-vga, virtio-net, e1000e and igb (module, loaded with kmod) all passed their checks; filesystems ext4, FAT, squashfs, overlayfs, ISO 9660, UDF, Btrfs, XFS, NTFS3 (read-only) and tmpfs passed, FUSE availability passed (mounting not tested); stress and three warm reboots passed.

**Modules (kmod 31 from the runner):** 39 modules, all signed; 38 loaded and unloaded cleanly; 1 (`x86_pkg_temp_thermal`) returned ENODEV because the VM has no matching device. A module with a corrupted signed body was refused ("Key was rejected by service"). `sig_enforce` is `N`, as configured (`MODULE_SIG_FORCE` is still an open decision).

**KVM boot matrix:** 1/2/4/8 vCPUs with 256 MiB to 4 GiB, 3 boots each, 24 boots, **0 failures (flake rate 0%)**; boot-to-power-off 4.0–5.0 s.

**TCG (software emulation):** reduced matrix, 2 boots each (8 boots). Across the CI runs, three kernel-log notices appeared only under TCG and were reviewed and allowlisted with reasons and with the scope `tcg` (accepted only on a guest running under software emulation): inconsistent MTRR notices with more than one vCPU, `tsc: Unable to calibrate against PIT` and `tsc: Fast TSC calibration failed`. Each of the two TSC notices appeared in **1 of 8** TCG boots in a different CI run (an intermittent flake of the software-emulated clock on a busy host; not observed under KVM). Before they were allowlisted, each made the affected run fail. Boots took about 14–16 s.

**Hardening probes:** see `tests/runtime/probes.tsv` for each probe and its required options. In the approved configuration all 44 probes map to existing Kconfig symbols and, for the checks listed, to options that are set. Deviations, reported rather than fixed:

* `CONFIG_SECURITYFS` is not set, so `/sys/kernel/security/lsm` and `/sys/kernel/security/lockdown` do not exist. The two probes that use them are reported *not tested: UNSUPPORTED by this kernel's configuration*. The LSM list is verified from the boot log instead (`capability,landlock,lockdown,yama,selinux`). Arch's `linux-lts` has securityfs. Whether Xlin should enable it (systemd and tools read these files) is a configuration decision for the maintainer; it was not changed here.
* `CONFIG_SHUFFLE_PAGE_ALLOCATOR=y` is configured but not active at runtime (reported as such).
* The LSM list contains SELinux and no `bpf` LSM, as the approved configuration implies.
* Config-only probes are labelled as such.

**Known finding W-X-CPA-ITS: `CPA detected W^X violation` (status EXPLAINED-UPSTREAM, reclassified by reviewed decision on 2026-11-25; listed in `tests/runtime/known-findings.txt`).**

*What is printed:* `CPA detected W^X violation: 8000000000000123 -> 0000000000000123 range: 0xffffffffc0400000 - 0xffffffffc0400fff PFN 2000`, about 0.45 s into boot, between `ITS: Mitigation: Aligned branch/return thunks` (0.43 s) and `Freeing SMP alternatives memory` (0.47 s). The page protections show the NX bit being cleared on one 4 KiB page of a read-write mapping (read-write → read-write-executable) in the module/execmem area (`0xffffffffc0...`, physical page 0x2000, i.e. 32 MiB).

*Code path (Linux 6.18.64, read, not modified):* `verify_rwx()` in `arch/x86/mm/pat/set_memory.c`. While `kernel_set_to_readonly` is still 0 (before `mark_rodata_ro()`), it only does `pr_warn_once()` — the comment there says "could be a false positive" — after that point the same condition would be a `WARN_ONCE` with a call trace. The caller is `its_alloc()` in `arch/x86/kernel/alternative.c`: the Indirect Target Selection (ITS) mitigation allocates a page for its aligned branch thunks and calls `set_memory_x()` on it while the page is still writable, then fills it; `its_fini_core()` later calls `execmem_restore_rox()` on these pages when `CONFIG_STRICT_KERNEL_RWX=y`. The page is therefore writable+executable for the short window of `alternative_instructions()` in single-threaded early boot (one CPU, no user space, no modules loaded yet).

*Evidence from the CI logs (all 948 boots of the Xlin kernel in 20 runtime-test job logs; each boot's own log was checked):*

| CI host CPU seen by the guest (QEMU 8.2.2, `-cpu host`) | guest Spectre-v2 mode | boots | `ITS: Mitigation: Aligned branch/return thunks` | `CPA detected W^X violation` |
|---|---|---|---|---|
| Intel Xeon 6975P-C, KVM | Enhanced / Automatic IBRS | 578 | 578 | **578** |
| Intel Xeon Platinum 8573C, KVM | Retpolines | 43 | 43 | 0 |
| AMD EPYC 7763, KVM | Retpolines | 105 | 0 | 0 |
| AMD EPYC 9V74, KVM | Retpolines | 86 | 0 | 0 |
| QEMU TCG CPU (software emulation) | Retpolines | 136 | 0 | 0 |

Reading of the table: the line is **not intermittent within a host class**; it appears in every boot on the Intel 6975P-C class and in none of the others, so the earlier wording in this document ("in some runs / one later run") and the allowlist wording ("in every QEMU/KVM boot") were both wrong. The ITS message alone is not enough (8573C prints it without the CPA line). What the 6975P-C guest has and the 8573C guest lacks is the enhanced-IBRS mode: with retpolines in use, the retpoline call sites keep their retpoline thunks; with enhanced IBRS the call sites are rewritten to plain indirect branches and the ITS mitigation has to place trampolines in an aligned thunk page, which is the `its_alloc()` path above. This is consistent with the code and with the table; it was not confirmed by tracing the kernel (no ftrace/instrumentation was added).

*It depends on the VMM, not only on the kernel:* the CI host's guest-visible CPU bits depend on the QEMU version. The CI job that boots the Arch kernel runs in an Arch container with QEMU 11.1.3 instead of the runner's QEMU 8.2.2. Complete QEMU 11.1.3 evidence (all `arch-baseline` job logs of this PR branch, counted per boot from the serial logs, guests on the Intel Xeon 6975P-C host class with "Enhanced / Automatic IBRS"): the Arch `linux-lts` kernel 6.18.64-1 (60 boots) and 6.18.65-1 (78 boots) and the Xlin 6.18.64 kernel booted by the control step (27 boots) show **neither** the ITS message **nor** the CPA notice in any of those 165 boots (0 of 165), whereas the same Xlin kernel under QEMU 8.2.2 on that class prints both in every boot (table above). On the Xeon Platinum 8573C class under QEMU 11.1.3, 12 Arch boots print the ITS message and no CPA notice. The Arch configuration has `MITIGATION_ITS=y`, `CPU_MITIGATIONS=y`, `STRICT_KERNEL_RWX=y`, `STRICT_MODULE_RWX=y`, `DEBUG_WX=y` and `ARCH_HAS_EXECMEM_ROX=y`, i.e. the same relevant options as Xlin's; the only differences in the reported mitigation options are `MITIGATION_SLS` (Arch y, Xlin n) and `MITIGATION_VMSCAPE` (Arch y; the option depends on KVM host support, which Xlin's configuration does not enable, so it is absent there), unrelated to this code path.

**Controlled comparison: Arch kernel and Xlin kernel under the same QEMU, host and job (job `arch-qemu8-control`, runs 45367126015, 45367131067, 45367136140, 45367140491, all on commit 119ca24).** In each job the Arch `linux-lts` kernel (package 6.18.65-1, `vmlinuz` taken from the Arch package in a container; not committed) and the Xlin kernel (6.18.64) were booted alternately (10 + 10 boots each) on the runner's own QEMU 8.2.2 (Debian/Ubuntu 1:8.2.2+ds-0ubuntu1.18), with the same OVMF (ovmf 2024.02-2ubuntu0.10), q35 machine, KVM, `-cpu host`, 2 vCPU, 1024 MiB, direct kernel boot, the same initramfs and the same logging. All four jobs happened to run on the Intel Xeon 6975P-C host class (guest mode "Enhanced / Automatic IBRS"). Result, counted from each boot's own serial log by `scripts/xlin-wx-compare`:

| kernel | boots | `ITS: Mitigation: Aligned branch/return thunks` | `CPA detected W^X violation` | DEBUG_WX `no W+X pages found` | rodata write-protected |
|---|---|---|---|---|---|
| Arch linux-lts 6.18.65-1-lts | 80 | 80 | 80 | 80 | 80 |
| Xlin 6.18.64-xlin | 80 | 80 | 80 | 80 | 80 |

Unavoidable differences: the kernel versions differ (6.18.65 vs 6.18.64) and so do the configurations (Arch builds most drivers as modules and the shared initramfs carries none of Arch's modules, so only the `base` scenario is used, as in the baseline job); the kernel command lines differ only in the `xlin.expect_release=` value because each kernel has its own release string; the host class (6975P-C) is the only one this comparison covers, and which runner a job gets cannot be chosen (these four were what the runner pool handed out). The Arch kernel's logscan reports an unrelated `rust_binder` line as unexpected; that is Arch-specific, informational and not part of this question.

What this comparison **establishes**: with the same QEMU on the same host class, a second, independently built kernel with a different configuration (and a different patch version) produces the same ITS message and the same CPA notice in every boot, and the same clean post-boot DEBUG_WX result. So the notice is not caused by something specific to Xlin's configuration, and it is not a rare or random event on that host class. Together with the QEMU 11 control it shows that the trigger is the combination of the ITS code in the upstream kernel and the CPU bits the VMM presents. What it **cannot** establish: that the behaviour is harmless. Arch showing it too only shows that it is upstream behaviour; Arch's kernel could carry the same weakness. It says nothing about whether the short-lived writable-and-executable page can be reached, nor about 6.18.65 vs 6.18.64 differences in this path, nor about other host classes or QEMU versions, and it is one host class and 160 boots. The security implications were assessed only by code reading (single CPU, no user space, no modules yet, page restored read-only/executable, and no W+X page left afterwards), which is an argument, not a test.

**Newer kernels (manual research workflow `W^X newer-kernel research`, runs 45415218265 and 45415295000, commit 6fec5a0, non-gating; the images are throw-away builds from the Xlin `config-final` plus `make olddefconfig`, not Xlin kernels).** Pinned Xlin 6.18.64, the newest 6.18.y at that time (6.18.65, tarball sha256 c92606f956f09dc50b5a0e2af9e86763fce27ada1647de97f8d1ac8cfc95801d, equal to kernel.org's `sha256sums.asc`; zero configuration differences from Xlin's after `olddefconfig`) and upstream mainline commit 8d7fe9885c62fc9a95bf55d9db244d9672a8aadc (7.4.0-rc4, 2026-11-23; 551 configuration diff lines because of new symbols, among them the renamed W+X check, see below) were booted alternately in the same job on the Intel Xeon 6975P-C class (both jobs), QEMU 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18), OVMF 2024.02-2ubuntu0.10, same initramfs, `-cpu host`, gcc 13.3.0 / binutils 2.42:

| kernel | boots | ITS message | CPA W^X notice | post-boot W+X check "no W+X pages found" | rodata write-protected |
|---|---|---|---|---|---|
| Xlin pinned 6.18.64 | 40 | 40 | 40 | 40 | 40 |
| 6.18.65 (newest 6.18.y) | 40 | 40 | 40 | 40 | 40 |
| mainline 7.4.0-rc4 (8d7fe9885c62) | 40 | 40 | 40 | 40 | 40 |

So the newest stable and current mainline show the same behaviour as the pinned kernel on this host class and QEMU. In mainline the option is called `CONFIG_CHECK_WX` (renamed from `DEBUG_WX`, `default STRICT_KERNEL_RWX`); its result line was present in all 40 mainline boots, but the option value itself was read from the Kconfig of the commit and not from the throw-away `.config`, which is only available as a CI artifact.

**Upstream status (found while researching this finding; primary source: the mainline git history, commit `ea6fd393cb9e`, 2026-09-13).** The kernel developers have already analysed exactly this message. Commit "x86/mm/pat: Use pr_warn() for early W^X warnings" (Mike Rapoport, signed off by Dave Hansen; Reported-by and Tested-by Nathan Chancellor, Tested-by Ihor Solodrai; Closes: lore.kernel.org/all/20260905044253.GA3816371@ax162) quotes the very same line (`8000000000000123 -> 0000000000000123 range: 0xffffffffc0400000 - 0xffffffffc0400fff`) and says: it comes from `its_alloc()` doing `set_memory_x()` during early retpoline setup; the warning "is not factually wrong but it is unproductive" because the RWX permission is temporary and fixed up by `execmem_restore_rox()`, and because at that time all kernel text is mapped RWX, "so there is not even a transient actual security issue"; the proper fix is to relax detection during boot and make a final verification pass before user space (`debug_checkwx()`, which must be enabled in Kconfig), and for now the warning is kept but made quieter with `pr_warn_once()`, to be removed once the final check is unconditional. The pinned 6.18.64 tree already contains that code (the comment "gently complain, this could be a false positive" and the `pr_warn_once()` branch), so this notice is the downgraded form of that warning. The warning only became visible after commit `ebaf7c9bbb` (mailing-list hash 038176c21617, "x86/mm/pat: Fix effective RW computation in lookup_address_in_pgd_attr()", 2026-08-13, part of the series "x86/mm/pat: CPA fixes") repaired the effective-RW computation that had previously made `verify_rwx()` never fire. The thread also contains a maintainer concern (Dave Hansen, 2026-09-09): skipping the check during boot could hide a W+X mapping created early that persists, and the final check only exists with the debug option. In this suite that final check is present and passes in every boot, in the pinned Xlin kernel (`CONFIG_DEBUG_WX=y`) and in the mainline kernel (`CHECK_WX`).

Decision (2026-11-25, reviewed): the finding is reclassified from EXPLAINED-OPEN to **EXPLAINED-UPSTREAM**, referencing upstream commit `ea6fd393cb9e`. No upstream report will be sent; the drafts (`wx-upstream-report-DRAFT*.txt`) are kept only as an internal research record. All evidence, counts and limitations in this section are unchanged, the W^X test and the scanner are unchanged, and the finding is still listed as a FINDING in every boot where it appears (the run is still PASS WITH OPEN FINDINGS, not a clean pass).

*What upstream states (their assessment, not our test):* the code path (`its_alloc()` `set_memory_x()`), that the RWX state is temporary and fixed by `execmem_restore_rox()`, and that all kernel text is RWX at that moment so there is no transient security issue. *What we verified ourselves:* the message and its ordering in the boot logs; the same behaviour in Arch 6.18.65 (80/80), Xlin 6.18.64 (80/80 and 40/40), 6.18.65 (40/40) and mainline 7.4.0-rc4 (40/40) under QEMU 8.2.2 on the 6975P-C class; its absence under QEMU 11.1.3 (0/165) and on the other host classes; and a clean post-boot W+X check in every boot. *Not verified by us:* the caller (not traced in our guests), exploitability, upstream's claim that all kernel text is RWX at that moment, the enhanced-IBRS link (inferred), bare metal and other hypervisors.

*State after boot:* in all 948 boots the kernel's own `CONFIG_DEBUG_WX` check reports `Checked W+X mappings: passed, no W+X pages found.` after rodata is protected, including all 578 boots with the CPA line, i.e. no writable+executable mapping remains once the kernel text is read-only. `Write protecting the kernel read-only data` is present as well.

*Classification (EXPLAINED-UPSTREAM):* a transient boot-time W^X window created by the upstream ITS mitigation code of 6.18.64, triggered only when the guest sees a CPU/hypervisor combination that makes the kernel allocate ITS thunks (here: QEMU 8.2.2 on a 6975P-C host); not by Xlin's configuration, which has the same relevant options as Arch's. It is not a persistent W+X mapping on the evidence above. It stays listed as a visible finding (now EXPLAINED-UPSTREAM rather than open-ended) because: (1) equality with Arch is now shown for the notice itself but says nothing about its security implications; (2) the DEBUG_WX check is a snapshot after boot and says nothing about the window itself or about whether the page could be written between `set_memory_x()` and `its_fini_core()` (single CPU, before user space, so unlikely to matter in practice, but not tested); (3) the upstream developers have already analysed and consciously kept this message (commit `ea6fd393cb9e`, see "Upstream status" below; mainline 7.4.0-rc4 and 6.18.65 behave the same), which explains the cause but is their assessment, not a test by this suite; (4) the link between enhanced IBRS and the trampoline allocation is inferred from the code and the host table, not traced. The kernel configuration and source were deliberately **not** changed to make the line disappear (for example by turning off the mitigation).

**Open finding XTILE-CPUID: `XFEATURE_XTILE_DATA: calculated size is 0 bytes, cpu state 8192 bytes` plus a `CPUID[0d, ..]` dump (status EXPLAINED-OPEN; listed in `tests/runtime/known-findings.txt`).** Found in the CI run after the three-tier scanner was introduced, when a runner with a new CPU class (Intel Xeon Platinum 8573C) was assigned: 43 of 43 boot events there (runtime-test run 45329083569, 2026-11-24: 40 VM boots plus 3 warm reboots of the `reboot` scenario's single VM), none elsewhere in the KVM boots of the Xlin kernel. **TCG: 0 of 248 TCG boots across 31 runs** (see the correction below). The first run to hit it failed the log scan as an *unexpected* error, which is the scanner working as designed; it was then reviewed rather than allowlisted. Cause by code reading (`check_xtile_data_against_struct()` in `arch/x86/kernel/fpu/xstate.c`): the kernel sums the AMX tile palette from guest CPUID leaf 0x1d and compares it with the 8192 bytes that leaf 0xd advertises for AMX tile data; with leaf 0x1d empty it computes 0 and prints the error and a dump of leaf 0xd. The result is ignored; the same boots still print `Supporting XSAVE feature 0x40000: 'AMX Tile data'` and all runtime checks pass. So it is a guest-CPUID inconsistency presented by this QEMU/host combination.

*Investigation (2026-11-25/26; full record in [`XTILE-CPUID-INVESTIGATION.md`](XTILE-CPUID-INVESTIGATION.md), research branch `research/xtile-cpuid`, commit `cce518c5bc6791c4be4122f96f64eb60509a25c8`; runs 45614681593, 45615681036, 45617083988, 45618759770):* the **forced mechanism is reproduced**. When the guest advertises AMX-TILE but its maximum CPUID leaf is `0x1c`, a query for leaf `0x1d` returns the data of leaf `0x1c` (empty), so the check computes 0 bytes. On AMX-capable Xeon 6975P-C/6973P-C runners, `-cpu host,level=0x1c` fired the check in 212 of 212 boots, while default level, `level=0x1d` and AMX disabled did not fire. This holds for Xlin 6.18.64, vanilla 6.18.65, mainline `8d7fe9885c62` and Arch linux-lts, under QEMU 8.2.2 and 11.1.3 (counts parsed from CI job logs, so **lower bounds**). Tested AMX works in these guests, including where the check fires: the `arch_prctl` permission request, tile config/zero/store, and a TDPBSSD int8 multiply with a known result (the multiply only in run 45618759770). The evidence supports a VMM-layer explanation (the runner presents level 0x1c, QEMU copies it and does not raise it for AMX), but **responsibility among the hypervisor, QEMU and the kernel's missing maximum-leaf validation is not conclusively assigned**.

*Not established:* the original failing Xeon Platinum 8573C runners **did not reproduce** (all 3 that landed on 2026-11-25 exposed no AMX, reported level 0x1c and did not fire), so their historical host state is not directly established and the original failure is not conclusively explained; untested AMX functionality: bf16/fp16 paths, context switch, signal frames, ptrace, XFD with several threads, sustained load, performance, real failing hosts and bare metal. The investigation is not closed. Because it is a hypervisor-dependent error-level kernel message, it stays a finding (status EXPLAINED-OPEN), not an accepted notice, and the scanner is unchanged.

*Correction of the TCG count (2026-11-26).* Earlier text in this document and in `known-findings.txt` said the message also appeared in "1 of 136" (here) and "1 of 56" (there) TCG boots. **Both figures are unsupported and unreproducible.** Per-boot evidence: of the 46 Kernel build runs whose `runtime-test` job log was inspected (every such run the workflow lists, 2026-11-20 to 2026-11-26), 31 ran the TCG scenarios, giving **248 TCG boots (8 per run), none of which printed the message**; a boot here is one `serial.log build/runtime-test/run-tcg/<name>/` block of the job log, and the 17 TCG boots that failed for other reasons (for example MTRR or TSC notices before they were allowlisted, or an early test-infrastructure failure) none involve this message. The only run with the message at all, 45329083569, had it in all 40 of its KVM serial blocks and in none of its 8 TCG blocks. Scope and limits of the 248: Xlin kernel only, QEMU TCG on whatever runner host was assigned (including the 8573C one), job logs only (the boots' own artifacts were not downloadable), 15 older runs had no TCG scenarios and are not in it, and the 68 TCG boots of the separate XTILE research runs (also 0) are not counted in it. The two old denominators (56 and 136 are 7 and 17 jobs of 8 TCG boots) came from log sets that were not recorded and could not be rebuilt, so they are retained here only as superseded history. How the stray "1" arose is **not known**: a section-based parse that credits the post-run serial dumps to the last `=== ... [tcg` header of run 45329083569 reproduces exactly one TCG boot, which makes that a plausible explanation, but the original aggregation script was not preserved, so it is unproven. The "136" TCG row of the W^X table above is a different claim (boots counted for the ITS and CPA messages, 0 of them) over the same unrecoverable 20-log set and is left unchanged.

**KASLR probe (found and fixed during this review).** One boot of a 1 GiB guest in the PR run for commit 0e6e0bb had `_text` exactly at the link-time address, which failed `hardening.kaslr`. With working KASLR the kernel lands on slot 0 by chance (about 1 boot in 512), so a single boot cannot prove KASLR broken, and with about 110 boots per CI run the old per-boot check was expected to fail a run now and then. The failing job was `runtime-test` of Kernel build run 45334023417 (commit 0e6e0bb; step "boot matrix", `base` on KVM with 2 vCPU and 1024 MiB, boot 2 of 3; every other check of that boot passed). This was a flaw in the test, not evidence about the kernel. The fix (commit 2b9ec37) is covered by the self-test cases above and the run 45363060151 on 2b9ec37 had no KASLR failure; because the event is random, a green run is weak evidence by itself and the self-test is the real coverage. A colliding boot is now reported as not tested (`COLLISION`) and the run fails only if every boot of a repeated run of at least three boots collides; the self-test covers both cases.

**Other reviewed notices** (tier 1, allowlisted with reasons in `tests/runtime/dmesg-allowlist.txt`): split-lock informational notice; missing `regulatory.db` (no firmware in the test initramfs); the PCI `pci=nocrs` hint; AMD "Speculative Return Stack Overflow" microcode notice, `amd_pstate` missing `_CPC` and `amd_pstate` CPPC disabled (these depend on which CPU the CI runner has, as seen by the VM; each new runner CPU type can bring a new notice, which will fail the log scan until reviewed — that fragility is inherent to scanning logs on shared runners).

**Problems found in the test setup while building it (not kernel faults):** BusyBox's shell ran its own `modprobe` applet instead of kmod; the kernel's own module requests had no helper (`kernel.modprobe`), which made Btrfs fail on `crc32c` until fixed; a virtual `sit0` interface was mistaken for a NIC; an empty CD-ROM drive made the kernel log complaints when probed.

**Arch `linux-lts` baseline (non-gating).** The baseline kernel is 6.18.64-1-lts, i.e. the same upstream version, but with Arch's configuration and build. Same guest, same CI host class, separate jobs. Single-run medians, informational only:

| Measurement | Xlin Kernel | Arch linux-lts |
|---|---|---|
| kernel start to `/init` (s) | 1.46 | 2.20 |
| idle memory in use (kB) | 68,980 | 149,764 |
| slab (kB) | 8,808 | 14,228 |
| processes at idle | 83 | 88 |
| `bzImage` | 12.2 MB (zstd) | not measured |

The Xlin kernel is much smaller in configuration, so these differences are expected; they are not a claim that Xlin is "faster" or "better". Probe differences: Arch passes the securityfs-based probes that Xlin cannot run; the `no_vsyscall` probe is not tested on Arch because its configuration does not set the option.

**Not tested / not done:** see "Known gaps".
