<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin

**Xlin** is the kernel of [XlinOS](https://github.com/madhav-sharma-co/XlinOS), by Axion Co. It grows from the Linux kernel the way Linux grew from Unix: a new kernel with its own identity, configuration, build, packaging and validation, standing on proven foundations.

**Xlin v1.0.0** (`6.18.64-xlin`) is a development kernel for QEMU + OVMF (UEFI) virtual machines. It has not been run on physical hardware and is not production-ready.

## Features

- **Boots and builds reliably:** UEFI boot, bit-for-bit reproducible builds, verified source, checksummed release package.
- **`xlin-run` launcher:** boots a minimal shell or your own root disk in one command.
- **Secure by default:** signed modules (enforced by the launcher), KASLR, stack protector, FORTIFY, Yama, Landlock, memory hardening.
- **Modern platform:** namespaces, cgroups, BPF, seccomp, SMP with CPU hotplug, zram.
- **Hardware models:** NVMe, SATA, virtio and USB storage; ext4, FAT, btrfs, XFS, squashfs, overlayfs and more; virtio, e1000e, igb networking.
- **Validated in CI:** boot matrix, SMP, timers, memory, panic recovery, 60 kernel regression programs, performance baseline.

## Quick start

Download the package from the [Releases page](https://github.com/madhav-sharma-co/Xlin/releases):

    zstd -dc xlin-6.18.64-xlin.tar.zst | tar xf - && cd xlin-6.18.64-xlin
    sha256sum -c SHA256SUMS
    ./xlin-run                      # shell in QEMU + OVMF (Ctrl-A then X quits)

Boot your own root filesystem:

    ./xlin-run --no-initramfs --disk root.img --root /dev/vda --rootfstype ext4 --net --memory 4096 --smp 4

More, including building it yourself: [docs/XLINOS-DEVELOPMENT.md](docs/XLINOS-DEVELOPMENT.md).

## Limits

No physical-hardware testing yet; no Wi-Fi, Bluetooth or sound; packages are unsigned until the maintainer creates the release key. Two known kernel log messages are documented, not hidden ([docs/RELEASE-NOTES.md](docs/RELEASE-NOTES.md)). Full coverage and gaps: [docs/FEATURES.md](docs/FEATURES.md).

## Documentation

[XLINOS-DEVELOPMENT](docs/XLINOS-DEVELOPMENT.md) | [FEATURES](docs/FEATURES.md) | [BUILD](docs/BUILD.md) | [CONFIGURATION](docs/CONFIGURATION.md) | [RUNTIME-VALIDATION](docs/RUNTIME-VALIDATION.md) | [RELEASE-READINESS](docs/RELEASE-READINESS.md) | [RELEASE-NOTES](docs/RELEASE-NOTES.md) | [CONTRIBUTING](CONTRIBUTING.md) | [SECURITY](SECURITY.md) | [CHANGELOG](CHANGELOG.md)

## Licence and attribution

Xlin includes the Linux kernel source, which keeps its own licence (`GPL-2.0 WITH Linux-syscall-note`) and notices. File-by-file licensing: [docs/LICENSING.md](docs/LICENSING.md). Linux(R) is the registered trademark of Linus Torvalds; Xlin is independent and not affiliated with or endorsed by him, the Linux Foundation or the kernel maintainers.
