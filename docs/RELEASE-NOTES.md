<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin Kernel v1.0.0 release notes

**Scope: Xlin v1.0.0 is a kernel for development in QEMU + OVMF virtual machines (the foundation for XlinOS). It has not been run on physical hardware and is not declared production-ready.** Physical-hardware validation is the remaining external limitation (docs/PHYSICAL-TEST-PLAN.md).

## What it is
Linux 6.18.64 (pinned commit `fd7cfd39c88596fec816639ad83cbf3e9d316372`, unmodified) built with the approved Xlin x86_64 UEFI configuration (`config/x86_64/xlin_defconfig`). Kernel release string: `6.18.64-xlin`. There are no Xlin-specific kernel source patches.

## What was verified (QEMU + OVMF, CI)
Source pin; configuration against real Kconfig; build; UEFI boot; runtime matrix (vCPUs x memory); storage and filesystems; virtual networking; modules (signed; enforcement scenario); hardening probes; SMP and CPU hotplug; timers; memory management; stress; warm reboot; kernel panic and automatic recovery; upstream kselftests (results in the CI summary); performance micro-benchmarks (informational, versus Arch linux-lts); reproducible build (two independent builds compared byte for byte when built with a fixed signing key); package verification (fresh unpack, checksums, boot through the package launcher, ext4 root disk). See docs/RELEASE-READINESS.md for the classification of what passed, what passed only in simulation, what is unsupported and what needs hardware.

## Package
`xlin-<release>.tar.zst`: kernel (EFI stub), signed modules, config, System.map, minimal initramfs, `xlin-run`, SOURCE-PIN, SBOM, SHA256SUMS, reproducibility manifest. CI packages are **unsigned**: no production signing key exists yet; the maintainer creates it offline and signs SHA256SUMS.

## Security decisions for this release
* Module signing is on and `xlin-run` enforces it (`module.sig_enforce=1`, tested). The kernel configuration does not force it (`MODULE_SIG_FORCE=n`).
* Lockdown LSM present, mode `none` (documented development configuration for QEMU).
* `CONFIG_SECURITYFS` not set (nothing in the implementation requires it); two probes report UNSUPPORTED.
* No production signing key is generated, stored or published by this repository.

## Known findings (reported on every affected boot; not allowlisted)
* **W-X-CPA-ITS: EXPLAINED-UPSTREAM.** `CPA detected W^X violation` during early ITS-mitigation setup, seen on Xeon 6975P-C hosts. The behaviour is in upstream Linux's ITS code (analysis in docs/RUNTIME-VALIDATION.md); no Xlin change affects it. No report has been sent upstream.
* **XTILE-CPUID: EXPLAINED-OPEN.** `XFEATURE_XTILE_DATA: calculated size is 0 bytes, cpu state 8192 bytes` when a guest advertises AMX-TILE with a maximum CPUID leaf below 0x1d. The mechanism was reproduced under QEMU; AMX still works; responsibility (hypervisor, QEMU or the kernel's missing max-leaf validation) is not assigned, and the original Xeon 8573C case has not been reproduced naturally (sampler run 45802200725: 60 runners, none matching). Details: docs/XTILE-CPUID-INVESTIGATION.md.

## Known limitations
No physical-hardware test; Wi-Fi, Bluetooth, sound, laptop power management and BPF/BTF tooling not configured; no key management or update channel yet; performance numbers are informational only and make no claim against any other kernel; the CI runners are shared and noisy.
