<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin v1.0.0 release checklist

Status key: [x] done and evidenced, [ ] open, [H] needs physical hardware, [D] needs a maintainer decision. **Nothing is tagged or published until every box a maintainer marks required is checked and the maintainer approves.**

## A. Source and configuration
- [x] Upstream pin verified (Linux 6.18.64, `fd7cfd39c88596fec816639ad83cbf3e9d316372`); wrong pins rejected
- [x] Configuration checked against real Kconfig; negative tests; running kernel's `/proc/config.gz` matches build `.config`
- [x] Pin kept at 6.18.64 (maintainer decision 2026-11-26); no separate upgrade project
- [x] Settings decided: module loading kept as is, enforcement tested and set by `xlin-run`; lockdown mode `none` for development; `CONFIG_SECURITYFS` left unset
- [x] Release identity `6.18.64-xlin`

## B. Automated validation (QEMU + OVMF)
- [x] Build, boot, runtime matrix, storage, filesystems, virtual networking, modules, hardening probes, stress, reboot (PR #5)
- [x] SMP/hotplug, timers, memory management, panic-recovery (PR #6, run 45813368893)
- [x] PR #7 reconciled and merged
- [x] Upstream kselftest subset run in the VM, gated against `tests/kselftest/expected.txt` (55 pass, 5 classified fails; run 46117009655)
- [x] Performance baseline against Arch linux-lts (informational; run 45930857708)
- [ ] Debug-configuration build (lockdep/KASAN) as a separate, non-shipping job: not done, post-v1.0.0
- [x] Reproducible-build check (fixed development key; identical hashes, run 46005861224)
- [x] Open findings documented: XTILE-CPUID (EXPLAINED-OPEN), W-X-CPA-ITS (EXPLAINED-UPSTREAM)
- [x] Open findings accepted and documented in the release notes

## C. Physical hardware (see PHYSICAL-TEST-PLAN.md)
- [H] First-laptop test passes all P-level checks
- [H] `dmesg` compared against the QEMU findings; XTILE-CPUID observed (or not) on the real CPU
- [H] Soak test

## D. Packaging and release
- [x] Packaging implemented (`scripts/xlin-package`, CI `package` job)
- [x] SHA256SUMS produced and verified in CI; [D] detached signature waits for the release key (unsigned CI packages)
- [D] Release signing key: the maintainer creates it offline later; none exists or is published
- [x] SBOM (`SBOM.spdx.json`), SOURCE-PIN, reproducibility manifest
- [x] Release notes (docs/RELEASE-NOTES.md)
- [ ] Rollback: previous known-good build retained
- [D] Tag `v1.0.0` (maintainer action; not created)

## E. Do not claim
Production readiness, physical-hardware compatibility, performance or size advantages, or that either open finding is resolved, unless the evidence above exists.
