<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin v1.0.0 release checklist

Status key: [x] done and evidenced, [ ] open, [H] needs physical hardware, [D] needs a maintainer decision. **Nothing is tagged or published until every box a maintainer marks required is checked and the maintainer approves.**

## A. Source and configuration
- [x] Upstream pin verified (Linux 6.18.64, `fd7cfd39c88596fec816639ad83cbf3e9d316372`); wrong pins rejected
- [x] Configuration checked against real Kconfig; negative tests; running kernel's `/proc/config.gz` matches build `.config`
- [D] Decide whether to move the pin to a later 6.18.x point release before v1.0.0 (separate, justified proposal)
- [D] Decide the open settings: module-signature enforcement, lockdown mode, `CONFIG_SECURITYFS`
- [D] Release identity string (currently `6.18.64-xlin`)

## B. Automated validation (QEMU + OVMF)
- [x] Build, boot, runtime matrix, storage, filesystems, virtual networking, modules, hardening probes, stress, reboot (PR #5)
- [x] SMP/hotplug, timers, memory management, panic-recovery (PR #6, run 45813368893)
- [ ] Resolve PR #7 against the new scenarios
- [ ] Upstream kselftest subset run in the VM (new work; must not weaken any gate)
- [ ] Performance baseline against a named reference kernel under identical conditions
- [ ] Debug-configuration build (lockdep/KASAN) run as a separate, non-shipping job
- [ ] Reproducible-build check (blocked by signing-key decision)
- [x] Open findings documented: XTILE-CPUID (EXPLAINED-OPEN), W-X-CPA-ITS (EXPLAINED-UPSTREAM)
- [D] Accept or resolve each open finding for v1.0.0

## C. Physical hardware (see PHYSICAL-TEST-PLAN.md)
- [H] First-laptop test passes all P-level checks
- [H] `dmesg` compared against the QEMU findings; XTILE-CPUID observed (or not) on the real CPU
- [H] Soak test

## D. Packaging and release
- [ ] Packaging implemented per PACKAGING-PLAN.md
- [ ] SHA256SUMS and detached signature produced with the release key
- [D] Release signing key created and custody decided
- [ ] SBOM (source pin, config hash, toolchain versions)
- [ ] Release notes listing known limitations and open findings
- [ ] Rollback: previous known-good build retained
- [D] Maintainer approval, then tag `v1.0.0`

## E. Do not claim
Production readiness, physical-hardware compatibility, performance or size advantages, or that either open finding is resolved, unless the evidence above exists.
