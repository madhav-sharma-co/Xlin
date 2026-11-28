<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin Kernel v1.0.0 release-readiness report

**Verdict: READY as Xlin v1.0.0 for development in QEMU + OVMF (the foundation for XlinOS). NOT production-ready, and NOT validated on physical hardware.** The kernel builds reproducibly, boots under OVMF, passes the automated validation described below and ships as a verified package with a launcher. It has never run on physical hardware, has no production release-signing key (the maintainer creates it later) and no security-update process. Physical-hardware validation is the remaining external limitation.

Updated 2026-11-28 against the pinned Linux 6.18.64 (`fd7cfd39c88596fec816639ad83cbf3e9d316372`). PR #5, #6, #7 (hardening of the new tests) and #8 are merged; the release-engineering work (reproducible build, package, `xlin-run`, kselftest, performance baseline) is PR #9. Every number below comes from a CI run named in the text; QEMU on shared GitHub runners cannot show physical-hardware behaviour.

## 1. Test classification

### 1.1 Actually passed (real boots of the built kernel, QEMU + OVMF, KVM unless stated)

| Area | Evidence |
|---|---|
| Source identity and pin | Source verification workflow; negative tests reject wrong pins |
| Configuration | `xlin-config-check` against real Kconfig; negative tests; `/proc/config.gz` of the running kernel byte-identical to the build's `.config` |
| Build | Linux 6.18.64 compiles to `6.18.64-xlin`, 0 warnings, artifact checks pass; `build-negative.sh` |
| Boot (QEMU + OVMF, UEFI) | `boot-test` job; boot negative tests (broken init must fail) |
| Runtime matrix | 1/2/4/8 vCPUs x 256 MiB-4 GiB, 3 boots each, 24 boots, 0 failures |
| Storage | virtio-blk, virtio-scsi, AHCI, NVMe, USB mass storage: driver binding, ext4 read/write/sync/remount/checksum |
| Filesystems | ext4, FAT, squashfs, overlayfs, ISO 9660, UDF, Btrfs, XFS, NTFS3 (read-only), tmpfs |
| Networking (virtual NICs only) | virtio-net, e1000e, igb: link, DHCP lease, ICMP echo to the QEMU gateway |
| Modules | 39 modules all signed; 38 load/unload cleanly, 1 ENODEV without its device; tampered module refused |
| Hardening probes | 44 probes mapped to real Kconfig symbols; behavioural ones (KASLR, dmesg_restrict, Yama, unprivileged BPF off, init_on_alloc, no vsyscall, /dev/mem restriction, namespaces, seccomp) pass; config-only ones are labelled as such |
| Stress and reboot | CPU/memory/fork/I-O stress, no BUG/Oops/lockup, not tainted; 3 warm reboots of one VM |
| SMP | `smp` scenario (PR #6), 4 vCPUs: CPU count, work pinned to each CPU, IPI counters, hot-unplug and re-plug of CPUs 1-3 |
| Interrupts and timers | `timer` scenario (PR #6): kvm-clock, local timer interrupts advance, nanosleep/timerfd/interval timer accuracy, monotonic clock |
| Kernel panic and recovery | `panic-recovery` scenario (PR #6): deliberate `sysrq-c` panic, automatic reboot (`panic=-1`), recovery boot completes the base checks |
| Memory management | `mm` scenario (PR #6): see section 1.5 for its CI result |
| Software emulation | TCG: 0 of 248 TCG boots across 31 runs showed the XTILE message (docs/RUNTIME-VALIDATION.md) |
| Upstream kselftests | 60 programs from 14 targets run in the guest: 55 pass, 5 fail; all 5 are classified in `tests/kselftest/expected.txt` and the gate fails on any other change (run `46117009655`). Not built against the pinned headers: exec, sigaltstack, ptrace, mm (reported, not hidden) |
| Reproducible build | Two independent builds with a fixed development signing key give identical bzImage, System.map, config-final, modules tarball and vmlinux (workflow `xlin-repro.yml`, run `46005861224`; earlier `45928512177`) |
| Module-signature enforcement | `modules-enforce` scenario (`module.sig_enforce=1`): signed modules load, an unsigned module is refused |
| Packaging | `package` job: fresh unpack, SHA256SUMS verify, boot through the package's `xlin-run`, ext4 root-disk boot without an initramfs |
| Performance micro-benchmarks (informational) | Xlin vs Arch linux-lts on the same runner, interleaved (run `45930857708`); no claim of faster or slower is made, see section 5 |
| Regression baseline | Arch `linux-lts` and QEMU 8 control runs (non-gating comparison) |

### 1.2 Passed only in simulation

* `tests/runtime-selftest.sh` (46 checks) and `tests/boot-selftest.sh`: they run the host tools against canned logs. They prove the judge logic, not the kernel.
* The XTILE sampler verdict script: tested on five synthetic cases only.

### 1.3 Not supported by current infrastructure (could be added, not done)

| Item | Why / what is needed |
|---|---|
| Sanitiser and fuzz builds (KASAN, KCSAN, lockdep, syzkaller) | Would need a separate debug configuration; not built |
| Secure Boot in OVMF | Needs signing keys and a bootloader decision (Xlin Boot or other) |
| exFAT | No unprivileged tool can populate an image |
| FUSE mounting, framebuffer pixel contents | Availability only / not checked |
| Suspend, hibernate, kexec/kdump | Not tested; QEMU can partly emulate them |
| Networking beyond user-mode NAT (bridging, throughput, IPv6 routing) | Not tested |

### 1.4 Requires physical hardware

Real NICs (r8169, tg3, igc), GPUs (i915, amdgpu), Wi-Fi/Bluetooth (not configured yet), TPM, sound, touchpad/keyboard/backlight, battery and thermal behaviour, suspend/resume on real firmware, NVMe/SATA on real controllers, real-CPU feature behaviour (including AMX and the XTILE-CPUID message on the Xeon 8573C), performance, power, and firmware quirks. **No physical test has been run.**

### 1.5 PR #6 results

CI run `45813368893` (head `f6a347d`, merged as `02cd705`): all six jobs passed (build, boot-test, runtime-test, arch-baseline, arch-qemu8-control, runtime-compare). The 20-scenario runtime run passed with 0 failed runs and the open findings reported ("PASS WITH OPEN FINDINGS", not a clean pass); the 24-boot matrix and 8-boot control runs passed. Earlier runs of the same PR found and fixed two flaws in my new `mm` test (an unjustified MemFree threshold, then MemFree noise; now the exact AnonPages counter): `45803184008` and `45807861037`.

## 2. Completed kernel capabilities (demonstrated in QEMU only)

* Pinned, verifiable upstream source; approved x86_64 UEFI configuration (`xlin_defconfig`, a 137-setting fragment over upstream's defconfig).
* Boots under OVMF to user space; initramfs boot; `/proc/config.gz`.
* Modules with signing on; enforcement tested via `module.sig_enforce=1` (the `xlin-run` default); kmod load/unload.
* Reproducible build, release package, `xlin-run` launcher, kselftest and performance baseline (docs/XLINOS-DEVELOPMENT.md).
* SMP with CPU hotplug; kvm-clock timers; panic and automatic reboot recovery; warm reboots.
* Virtio, AHCI, NVMe and USB storage; common filesystems; virtual NICs; virtio-rng; virtual graphics (device nodes only).
* Hardening options enabled and probed (section 4).

## 3. Missing capabilities and known limitations

* **No Xlin-specific kernel patches**: Xlin is a configuration over upstream. There is no release identity beyond `-xlin` (the planned `-xlin0.1` form is not implemented).
* Not configured: Wi-Fi, Bluetooth, sound, laptop extras (touchpad, backlight, suspend), BTF/BPF tooling.
* Packages are unsigned: no production release key exists. The maintainer creates and stores it later; CI never holds one. No update channel.
* Pin is a single point-in-time release; no documented process for taking upstream stable security updates.
* Two open runtime findings, both still reported on every affected boot and neither allowlisted:
  * **W-X-CPA-ITS** (EXPLAINED-UPSTREAM): `CPA detected W^X violation` during early ITS-mitigation setup; seen in 578 of 578 boots on the Xeon 6975P-C hosts and no others. Upstream analysis kept the message. No report was sent upstream.
  * **XTILE-CPUID** (EXPLAINED-OPEN): kernel message about the AMX tile data size. The mechanism is reproduced when the guest's max CPUID leaf is 0x1c with AMX advertised; responsibility (hypervisor, QEMU, kernel) is not assigned and the natural 8573C case has not been reproduced (sampler run `45802200725`: 60 runners, 0 matching hosts). AMX itself worked in the forced reproduction.
* Runtime logs are scanned with an explicit allowlist; "PASS WITH OPEN FINDINGS" is not a clean pass.

## 4. Security status

| Item | State |
|---|---|
| Source authenticity | Source identity verified against the pin; authenticated provenance (signature) is reported separately and is limited as documented in SOURCE-MANAGEMENT.md |
| KASLR, stack protector, FORTIFY, hardened usercopy, VMAP_STACK, slab hardening, init_on_alloc, no vsyscall, Yama, Landlock, lockdown LSM present | On; behavioural probes pass where the kernel exposes behaviour |
| `MODULE_SIG_FORCE` | Off in the config by decision; enforcement is tested and set on the command line by `xlin-run` (`module.sig_enforce=1`) |
| Lockdown mode | LSM present, mode `none`: documented development configuration for QEMU/OVMF |
| `CONFIG_SECURITYFS` | Not set (nothing in the implementation requires it); two probes report UNSUPPORTED |
| `SHUFFLE_PAGE_ALLOCATOR` | Configured but not active at runtime |
| Secure Boot / measured boot | Not addressed (needs bootloader decision) |
| Vulnerability mitigations | Reported by the kernel (`/sys/devices/system/cpu/vulnerabilities` present); effectiveness on real CPUs not assessed |
| Sanitiser and fuzz coverage | None; kselftest subset runs (section 1.1) |
| CVE/security-update process | None |

## 5. Performance evidence

Size: `bzImage` 12,174,336 bytes; 39 modules, 9,729,035 bytes compressed. Static micro-benchmarks run in the guest, Xlin versus Arch `linux-lts`, interleaved three rounds on one KVM runner (Xeon 6975P-C), run `45930857708`. Informational only: shared noisy runners, no real hardware.

| Metric | Xlin | Arch linux-lts |
|---|---|---|
| syscall getppid | 106.98 ns | 105.05 ns |
| pipe round trip | 1881.98 ns | 1798.92 ns |
| fork+exit+wait | 26.34 us | 29.58 us |
| page fault | 1085 ns/page | 460 ns/page |
| munmap 64 MiB | 1619 us | 1248.73 us |
| memcpy | 13.15 GB/s | 13.09 GB/s |
| tmpfs write / read | 5291 / 7629 MiB/s | 4782 / 8960 MiB/s |
| timer lateness 1 ms, median / p99 | 85.67 / 102.85 us | 75.07 / 106.3 us |

Xlin's page-fault cost is about 2.4x Arch's here; the cause was not investigated (the two kernels differ in many options). No claim of smaller, lighter or faster is made.

## 6. Remaining items

Not blockers for the v1.0.0 QEMU/OVMF development release:

1. No physical-machine test of any kind (the remaining external limitation).
2. Production release-signing key: the maintainer creates and stores it later; do not publish packages as signed before then.
3. Hardware support scope for a first laptop is undefined.
4. No upstream-update (security patch) policy; the 6.18.64 pin is kept by decision.
5. XTILE-CPUID stays EXPLAINED-OPEN and W-X-CPA-ITS EXPLAINED-UPSTREAM; both are documented in the release notes and still reported on every affected boot.
6. kselftest: 5 classified non-passes (2 are guest-environment, 1 is a kernel feature not built, 2 are OPEN and unverified: `clone3_cap_checkpoint_restore`, `set-anon-vma-name-test`; `mincore_selftest` is OPEN and probably the ramfs guest) and 4 targets that do not build against the pinned headers.
7. Licensing review flagged in LICENSING.md is not recorded as done.
8. The `v1.0.0` tag and release publication need the maintainer's action.

## 7. Remaining physical-hardware tests (first laptop)

Boot via firmware (UEFI) with the kernel as an EFI stub; storage (NVMe), keyboard, display (framebuffer/DRM), wired NIC; `dmesg` capture and comparison with the QEMU findings; CPUID/AMX state on the real CPU (answers XTILE-CPUID for that machine); suspend/resume; thermal and battery readouts; module loading of real hardware drivers; a 24-hour soak. Procedure and acceptance criteria are in `docs/PHYSICAL-TEST-PLAN.md`.
