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
2. **Known, unresolved finding** — listed in `tests/runtime/known-findings.txt` with an ID and a status (`OPEN` or `EXPLAINED-OPEN`). Reported as `FINDING` in every boot where it appears and as `INFO ... not observed in this boot` where it does not. It does not fail a run, but it is never accepted either: the run is reported as **PASS WITH OPEN FINDINGS** (not a clean pass), the summary carries the verdict, the finding, its status and the number of boots in which it appeared, CI prints a warning annotation, and `xlin-runtime-test --strict-findings` turns it into exit status 4.
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

**Open finding W-X-CPA-ITS: `CPA detected W^X violation` (status EXPLAINED-OPEN; listed in `tests/runtime/known-findings.txt`).**

*What is printed:* `CPA detected W^X violation: 8000000000000123 -> 0000000000000123 range: 0xffffffffc0400000 - 0xffffffffc0400fff PFN 2000`, about 0.45 s into boot, between `ITS: Mitigation: Aligned branch/return thunks` (0.43 s) and `Freeing SMP alternatives memory` (0.47 s). The page protections show the NX bit being cleared on one 4 KiB page of a read-write mapping (read-write → read-write-executable) in the module/execmem area (`0xffffffffc0...`, physical page 0x2000, i.e. 32 MiB).

*Code path (Linux 6.18.64, read, not modified):* `verify_rwx()` in `arch/x86/mm/pat/set_memory.c`. While `kernel_set_to_readonly` is still 0 (before `mark_rodata_ro()`), it only does `pr_warn_once()` — the comment there says "could be a false positive" — after that point the same condition would be a `WARN_ONCE` with a call trace. The caller is `its_alloc()` in `arch/x86/kernel/alternative.c`: the Indirect Target Selection (ITS) mitigation allocates a page for its aligned branch thunks and calls `set_memory_x()` on it while the page is still writable, then fills it; `its_fini_core()` later calls `execmem_restore_rox()` on these pages when `CONFIG_STRICT_KERNEL_RWX=y`. The page is therefore writable+executable for the short window of `alternative_instructions()` in single-threaded early boot (one CPU, no user space, no modules loaded yet).

*Evidence from the CI logs (10 runtime-test jobs, 438 serial logs of boots):*

| CI host CPU seen by the guest | boots | boots with the line | boots with `ITS: Mitigation: Aligned branch/return thunks` |
|---|---|---|---|
| Intel Xeon 6975P-C (model 0xad), KVM | 277 (7 CI runs) | 277 | 277 |
| AMD EPYC 9V74, KVM | 86 (2 runs) | 0 | 0 |
| AMD EPYC 7763, KVM | 19 (1 run) | 0 | 0 |
| QEMU TCG CPU (software emulation) | 56 | 0 | 0 |

The line is **not intermittent within a host type**: it appears in every boot on the Intel host class and in none elsewhere, and it tracks the ITS message exactly. Whether a given CI job shows it depends on which runner CPU the job was given (an earlier wording in this document, "in some runs / one later run", and the allowlist wording "in every QEMU/KVM boot", were both wrong; the first because the host CPU was not looked at, the second because AMD and TCG boots never show it). Because the guest runs with `-cpu host`, the ITS mitigation is selected from the host CPU's vulnerability bits.

*State after boot:* in the same 277 boots the kernel's own `CONFIG_DEBUG_WX` check reports `Checked W+X mappings: passed, no W+X pages found.` (as it does in all 438 boots), i.e. no writable+executable mapping is left once the kernel text is read-only. `Write protecting the kernel read-only data` is also present.

*Classification:* a transient boot-time W^X window created by the upstream ITS mitigation code of 6.18.64, not by Xlin's configuration (`CONFIG_CPU_MITIGATIONS=y` is the only related option set in Xlin's configuration, and ITS is a default-on part of it). It is not a persistent W+X mapping on the evidence above. It is nevertheless kept as an **open** finding because: (1) the Arch `linux-lts` baseline job has so far run on AMD hosts only, so the same kernel version with Arch's configuration has **not** been compared on an ITS-affected CPU (not shown to be the same; expected to be, since the code is upstream, but not verified); (2) the DEBUG_WX check is a snapshot after boot and says nothing about the window itself; (3) it has not been checked against, or reported to, the upstream kernel developers; (4) it has not been demonstrated on any CPU other than the one Intel model above. The kernel configuration and source were deliberately **not** changed to make the line disappear (e.g. by turning off the mitigation).

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
