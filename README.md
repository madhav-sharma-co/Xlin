<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

<p align="center">
  <img src="docs/assets/xlin-logo.png" alt="Xlin" width="520">
</p>

# Xlin v1.0.0

**Xlin is a 64-bit kernel developed by Axion Co. for the Xlin operating system.**

Version **1.0.0** targets x86_64 UEFI virtual machines using QEMU and OVMF. It is built from the Linux 6.18.64 source base with Xlin's own configuration, build, packaging and validation workflow.

## Features

- **UEFI boot:** boots with QEMU and OVMF.
- **Multicore support:** SMP and CPU hotplug.
- **Memory management:** virtual memory, protection and tested memory operations.
- **Storage and filesystems:** NVMe, SATA, virtio, USB storage, ext4, FAT, Btrfs, XFS and other configured filesystems.
- **Networking:** IPv4/IPv6 and supported virtual network devices.
- **Security:** module signing, launcher-enforced signature checks, KASLR and kernel hardening options.
- **Modern kernel facilities:** namespaces, cgroups, seccomp, BPF and zram.
- **Development tools:** reproducible build workflow, kernel package, minimal initramfs and `xlin-run` QEMU launcher.

## Quick start

Build and run from source:

```sh
git clone https://github.com/madhav-sharma-co/Xlin.git
cd Xlin
```

Follow [Build and run](docs/XLINOS-DEVELOPMENT.md) for dependencies, source verification, building, packaging and launching the kernel.

## Status

Xlin v1.0.0 is validated for development in **QEMU + OVMF** and is suitable as the starting kernel foundation for XlinOS development.

- Physical hardware has not yet been validated.
- Wi-Fi, Bluetooth, audio and laptop power-management support are not configured.
- Production signing and security-update procedures remain future work.
- Two known kernel findings are documented in [Release notes](docs/RELEASE-NOTES.md).

See [feature coverage](docs/FEATURES.md) for supported areas and limitations, and the [physical test plan](docs/PHYSICAL-TEST-PLAN.md) for hardware validation.

## License

Xlin includes upstream Linux kernel source and retains its original licensing and notices. See [licensing information](docs/LICENSING.md).
