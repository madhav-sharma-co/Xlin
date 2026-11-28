<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin

**Xlin** is the Linux kernel of [XlinOS](https://github.com/madhav-sharma-co/XlinOS), by Axion Co. It is a downstream of a pinned, unmodified upstream Linux release (6.18.64) with Xlin's own kernel configuration, reproducible build, packaging, launcher and a validation suite. Xlin is not a rewrite of Linux and does not hide its origin: upstream history, copyright and licences are preserved.

> **Xlin v1.0.0 is a development kernel for QEMU + OVMF (UEFI) virtual machines.** It builds reproducibly, boots, passes the automated validation in this repository and ships as a verified package. **It has not been run on physical hardware and is not production-ready.** Release packages are unsigned until the maintainer creates the production key. See [docs/RELEASE-READINESS.md](docs/RELEASE-READINESS.md).

| | |
|---|---|
| Upstream | Linux **6.18.64** (longterm), commit `fd7cfd39c88596fec816639ad83cbf3e9d316372`, unmodified |
| Release string | `6.18.64-xlin` |
| Target | x86_64, UEFI, QEMU + OVMF |
| Xlin changes | one reviewed configuration fragment; no kernel source patches |
| Pin file | [`upstream/UPSTREAM.lock`](upstream/UPSTREAM.lock) |

## Quick start

Download the release package (`xlin-6.18.64-xlin.tar.zst`) from the [Releases page](https://github.com/madhav-sharma-co/Xlin/releases), then:

    zstd -dc xlin-6.18.64-xlin.tar.zst | tar xf - && cd xlin-6.18.64-xlin
    sha256sum -c SHA256SUMS
    ./xlin-run                      # BusyBox shell in QEMU + OVMF (Ctrl-A then X quits)

Boot your own root filesystem (the XlinOS workflow):

    ./xlin-run --no-initramfs --disk root.img --root /dev/vda --rootfstype ext4 --net --memory 4096 --smp 4

Full instructions, including building the package yourself: [docs/XLINOS-DEVELOPMENT.md](docs/XLINOS-DEVELOPMENT.md).

## What is validated (QEMU + OVMF, in CI)

| Area | What is checked |
|---|---|
| Source | exact upstream commit pinned and verified; wrong pins are rejected |
| Configuration | every setting checked against the real Kconfig and confirmed in effect |
| Build | 0 warnings; **bit-for-bit reproducible** with a fixed signing key |
| Boot | UEFI boot to user space; 24-boot matrix of 1-8 vCPUs x 256 MiB-4 GiB |
| Hardware models | virtio, AHCI, NVMe, USB storage; ext4, FAT, squashfs, overlayfs, btrfs, XFS, ISO 9660, UDF, tmpfs; virtio-net, e1000e, igb |
| Kernel | SMP and CPU hotplug, timers, memory management, panic and automatic recovery, warm reboot, stress |
| Security | 44 hardening probes tied to Kconfig symbols; signed modules, enforcement tested (`module.sig_enforce=1`) |
| Regression | 60 upstream kselftest programs (55 pass, 5 classified), gated against [`tests/kselftest/expected.txt`](tests/kselftest/expected.txt) |
| Package | fresh unpack, checksums, boot through the package launcher, ext4 root disk |
| Performance | micro-benchmarks against Arch `linux-lts` (informational, no speed claim) |

Test classification, results and the limits of QEMU evidence: [docs/RELEASE-READINESS.md](docs/RELEASE-READINESS.md). Honest feature coverage and gaps: [docs/FEATURES.md](docs/FEATURES.md).

## Known findings

Two kernel messages appear on affected boots and are reported, never hidden: **W-X-CPA-ITS** (upstream behaviour in early ITS mitigation setup) and **XTILE-CPUID** (an AMX message under some virtual CPU models; unassigned, not reproduced on the original host). Details: [docs/RELEASE-NOTES.md](docs/RELEASE-NOTES.md).

## Repository layout

    upstream/        the source pin (UPSTREAM.lock); the Linux source is fetched, never committed
    config/x86_64/   xlin_defconfig fragment and its requirements
    scripts/         xlin-fetch, -verify, -config-check, -build, -package, -run, -dev-key, test runners
    tests/           boot, runtime (guest scenarios), kselftest, perf, negative and self tests
    docs/            architecture, build, configuration, validation, release and licensing
    .github/         CI: source, configuration, build, boot, runtime, kselftest, perf, package, reproducibility

## Build and test it yourself

    scripts/xlin-fetch && scripts/xlin-verify --strict      # pinned, verified source
    scripts/xlin-config-check --full                        # real Kconfig checks
    scripts/xlin-dev-key dev-key.pem                        # DEVELOPMENT signing key (never a release key)
    scripts/xlin-build --out "$PWD/build/xlin" --signing-key "$PWD/dev-key.pem"
    scripts/xlin-runtime-test --help                        # runtime scenarios (needs QEMU + OVMF)

Details: [docs/BUILD.md](docs/BUILD.md), [docs/BOOT-TEST.md](docs/BOOT-TEST.md), [docs/RUNTIME-VALIDATION.md](docs/RUNTIME-VALIDATION.md).

## Project family

- **Axion Co.**: parent technology company.
- **Xlin**: this kernel.
- **XlinOS**: the operating system built on Xlin.
- **Xlin Boot**: a possible future bootloader, not part of v1.0.0.

## Documentation

[ARCHITECTURE](docs/ARCHITECTURE.md) | [FEATURES](docs/FEATURES.md) | [XLINOS-DEVELOPMENT](docs/XLINOS-DEVELOPMENT.md) | [BUILD](docs/BUILD.md) | [CONFIGURATION](docs/CONFIGURATION.md) | [SOURCE-MANAGEMENT](docs/SOURCE-MANAGEMENT.md) | [BOOT-TEST](docs/BOOT-TEST.md) | [RUNTIME-VALIDATION](docs/RUNTIME-VALIDATION.md) | [RELEASE-READINESS](docs/RELEASE-READINESS.md) | [RELEASE-NOTES](docs/RELEASE-NOTES.md) | [PACKAGING](docs/PACKAGING-PLAN.md) | [PHYSICAL-TEST-PLAN](docs/PHYSICAL-TEST-PLAN.md) | [XTILE-CPUID](docs/XTILE-CPUID-INVESTIGATION.md) | [LICENSING](docs/LICENSING.md)

Contributing: [CONTRIBUTING.md](CONTRIBUTING.md). Security: [SECURITY.md](SECURITY.md). History: [CHANGELOG.md](CHANGELOG.md).

## Licensing

Licences are chosen file by file; see [docs/LICENSING.md](docs/LICENSING.md) and the SPDX identifier in each file. The Linux kernel keeps its own licence (`GPL-2.0 WITH Linux-syscall-note`) and notices.

## Trademarks

Linux(R) is the registered trademark of Linus Torvalds in the United States and other countries. Xlin is an independent downstream project and is not affiliated with or endorsed by Linus Torvalds, the Linux Foundation or the Linux kernel maintainers. The name "Linux" is used only to say what Xlin is based on.
