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

`tests/runtime/dmesg-allowlist.txt` lists reviewed lines, each with the reason it is accepted. A kernel-log line that looks like a warning or error and matches no entry fails the run. Entries starting `FINDING:` are real open issues that are reviewed but **not** explained away: they are listed as open findings in every summary.

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

**TCG (software emulation):** reduced matrix, 2 boots each (8 boots). Across the CI runs, two kernel-log notices appeared only under TCG and were reviewed and allowlisted with reasons: inconsistent MTRR notices with more than one vCPU, and `tsc: Unable to calibrate against PIT`. The latter appeared in **1 of 8** TCG boots in one run (a flake of the test environment, not observed under KVM). Boots took about 14–16 s.

**Hardening probes:** see `tests/runtime/probes.tsv` for each probe and its required options. In the approved configuration all 44 probes map to existing Kconfig symbols and, for the checks listed, to options that are set. Deviations, reported rather than fixed:

* `CONFIG_SECURITYFS` is not set, so `/sys/kernel/security/lsm` and `/sys/kernel/security/lockdown` do not exist. The two probes that use them are reported *not tested: UNSUPPORTED by this kernel's configuration*. The LSM list is verified from the boot log instead (`capability,landlock,lockdown,yama,selinux`). Arch's `linux-lts` has securityfs. Whether Xlin should enable it (systemd and tools read these files) is a configuration decision for the maintainer; it was not changed here.
* `CONFIG_SHUFFLE_PAGE_ALLOCATOR=y` is configured but not active at runtime (reported as such).
* The LSM list contains SELinux and no `bpf` LSM, as the approved configuration implies.
* Config-only probes are labelled as such.

**Open finding.** In some runs the kernel prints `CPA detected W^X violation: ... range: 0xffffffffc0200000 ...` once during early boot. It appeared in the first CI runs and in one later run, and not in others; the CI job's host CPU differs between runs and was not recorded, so the dependency on the host is a suspicion, not a result. The Arch kernel's baseline runs showed no such line. It is kept visible as a finding in every summary. It has not been diagnosed and has not been shown to be harmless.

**Other reviewed notices** (allowlisted with reasons in `tests/runtime/dmesg-allowlist.txt`): split-lock informational notice; missing `regulatory.db` (no firmware in the test initramfs); the PCI `pci=nocrs` hint; AMD "Speculative Return Stack Overflow" microcode notice and `amd_pstate` missing `_CPC` (depend on the CI host CPU as seen by the VM).

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
