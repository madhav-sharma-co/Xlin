<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Changelog

All notable changes to Xlin are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- TCG evidence corrected: the unsupported "1 of 56" / "1 of 136" TCG counts replaced by 0 of 248 TCG boots across 31 runs (per-boot logs); "43" clarified as 43 boot events. XTILE-CPUID stays EXPLAINED-OPEN.
- XTILE-CPUID finding text and docs updated with the reproduced forced mechanism (guest max CPUID leaf 0x1c with AMX advertised), AMX functional results and limits; status stays EXPLAINED-OPEN, original 8573C failure not reproduced; see docs/XTILE-CPUID-INVESTIGATION.md.
- Known finding W-X-CPA-ITS reclassified EXPLAINED-UPSTREAM (upstream commit ea6fd393cb9e); still reported as a finding, evidence and limitations kept, no upstream report sent; XTILE-CPUID stays EXPLAINED-OPEN.
- Expanded runtime validation (Phase B Step 6): probe table mapped to kernel options, guest suites, host runner with boot matrix, repeats and flake rate, device/filesystem/module (kmod) scenarios, kernel-log allowlist and known-findings tiers (an open W^X finding stays visible, never a clean pass), informational measurements, optional non-gating Arch `linux-lts` baseline. QEMU only; see `docs/RUNTIME-VALIDATION.md`.- Xlin Source Pin: `upstream/UPSTREAM.lock` pins Linux 6.18.64 (commit `fd7cfd39c88596fec816639ad83cbf3e9d316372`, signed tag `v6.18.64`).
- Xlin Fetch (`scripts/xlin-fetch`): retrieves exactly the pinned source into an ignored directory.
- Xlin Verify (`scripts/xlin-verify`): reports source identity and, separately, authenticated provenance.
- Negative tests (`tests/negative.sh`) and the "Source verification" GitHub Actions workflow.
- `docs/ARCHITECTURE.md` and `docs/SOURCE-MANAGEMENT.md`; `LICENSES/CC-BY-4.0.txt`.

- Xlin Kernel configuration for x86_64 UEFI (`config/x86_64/xlin_defconfig`, a 137-setting fragment over the upstream x86_64 defconfig), `requirements.txt` with the source of each requirement, and `docs/CONFIGURATION.md`.
- `scripts/xlin-config-check` (static and full real-kconfig modes), `tests/config-negative.sh` and the "Kernel configuration" workflow, which also compares against Arch's `linux-lts` config as an informational reference.
- `LICENSES/GPL-2.0-only.txt` and the provenance record for configuration files in `docs/LICENSING.md`.

- Xlin Build (`scripts/xlin-build`), `tests/build-negative.sh`, the "Kernel build" workflow and `docs/BUILD.md`: the pinned Linux 6.18.64 compiles with the approved configuration (`6.18.64-xlin`; bzImage 11.9 MiB; 39 modules, 9.5 MiB; 0 warnings; 12-15 min on 4 vCPUs). Build validation only: not booted, not a release.

- Xlin boot test: `scripts/xlin-initramfs`, `scripts/xlin-boot-test`, `tests/boot/` (`/init`, `xlin-pass`), `tests/boot-selftest.sh`, `tests/boot-negative.sh`, a "boot-test" job in the "Kernel build" workflow and `docs/BOOT-TEST.md`. The built kernel `6.18.64-xlin` boots under UEFI (OVMF) in QEMU, runs `/init` and reaches an interactive serial shell, exit status 0, in 3.5 s (three independent CI runs). QEMU only: not Xlin Boot, not physical hardware.
- `xlin-build` records the `bzImage` SHA-256 in `build-report.env`; the boot job checks it.

### Fixed
- Found by the first real kconfig run: upstream's defconfig has no framebuffer, so the console group needed `FB` and `DRM_FBDEV_EMULATION`; the legacy uevent helper is now turned off through `UEVENT_HELPER` (its path symbol does not exist otherwise).

### Changed
- Documentation is licensed `CC-BY-4.0`; `docs/LICENSING.md` now describes the file-by-file policy.

The kernel has been built in CI and boots in QEMU + OVMF; it has not been tested on physical hardware.
