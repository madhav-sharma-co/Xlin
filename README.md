<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Xlin

**Xlin** is a downstream Linux kernel project by Axion Co. It is built on a pinned, maintained upstream Linux release and adds only what Xlin needs: its own kernel configuration, a small set of reviewed patches, build and test infrastructure, packaging and a release identity. It is the kernel of [XlinOS](https://github.com/madhav-sharma-co/XlinOS).

Xlin is not a rewrite of Linux and does not replace or hide its origin. Upstream history, copyright and licensing notices are preserved.

> **Status: repository foundation only.** There is no kernel build, configuration or package yet. Nothing here has been built or boot-tested. See [CHANGELOG.md](CHANGELOG.md) for what exists.

## Plan for Xlin Kernel 0.1

| Item | Decision |
|---|---|
| Upstream | Linux 6.18 LTS (longterm series, supported until Dec 2028 per kernel.org); exact version and commit pinned in `upstream/UPSTREAM.lock` once added |
| Targets | x86_64 UEFI systems and QEMU virtual machines |
| Source in this repo | References and pins only; no copy of the Linux source tree |
| Xlin changes | Config fragments (`config/`) and patch files (`patches/`), kept apart from upstream |
| Release identity | `uname -r` will read `<upstream version>-xlin0.1`; `uname -s` stays `Linux` |
| Packaging | Arch package `linux-xlin` for XlinOS |
| Boot chain for XlinOS | UEFI -> existing bootloader -> Xlin Kernel -> initramfs -> systemd -> XlinOS terminal |

## Project family

- **Axion Co.**: parent technology company.
- **Xlin**: this downstream Linux kernel.
- **XlinOS**: the operating system built around Xlin.
- **Xlin Boot**: a possible future bootloader. It is not part of 0.1.

## Documentation

Documents are added together with the work they describe. Planned: `docs/ARCHITECTURE.md`, `docs/BUILD.md`, `docs/CONFIGURATION.md`, `docs/UPSTREAM.md`, `docs/LICENSING.md`, `docs/TESTING.md`. Currently present: [docs/LICENSING.md](docs/LICENSING.md) (draft).

## Licensing

Licences are chosen file by file according to who owns each file and what it derives from. See [docs/LICENSING.md](docs/LICENSING.md) and the SPDX identifier in each file. The Linux kernel itself is GPL-2.0-only with the Linux-syscall-note and keeps its own notices.

## Trademarks

Linux(R) is the registered trademark of Linus Torvalds in the United States and other countries. Xlin is an independent downstream project and is not affiliated with or endorsed by Linus Torvalds, the Linux Foundation or the Linux kernel maintainers. The name "Linux" is used only to say what Xlin is based on.
