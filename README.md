<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin

**Xlin** is a downstream Linux kernel project by Axion Co. It is built on a pinned, maintained upstream Linux release and adds only what Xlin needs: its own kernel configuration, a small set of reviewed patches, build and test infrastructure, packaging and a release identity. It is the kernel of [XlinOS](https://github.com/madhav-sharma-co/XlinOS).

Xlin is not a rewrite of Linux and does not hide its origin. The source is the Linux kernel; upstream history, copyright and licensing notices are preserved.

> **Status: source and configuration only.** The upstream source is pinned and verifiable and a first x86_64 configuration exists and passes the real kconfig checks. The kernel has not been built, packaged or boot-tested. See [CHANGELOG.md](CHANGELOG.md).

## Xlin Source Pin

| | |
|---|---|
| Source project | Linux kernel (stable tree, longterm series 6.18) |
| Version | `6.18.64` |
| Commit | `fd7cfd39c88596fec816639ad83cbf3e9d316372` |
| Pin file | [`upstream/UPSTREAM.lock`](upstream/UPSTREAM.lock) |

    scripts/xlin-fetch               # retrieve exactly the pinned source (ignored by Git)
    scripts/xlin-verify              # verify it; reports every check
    scripts/xlin-verify --strict     # CI mode: skipped checks also fail
    tests/negative.sh                # wrong pins and bad input must be rejected

Needs `git`, and `gpg` for the signature check. See [docs/SOURCE-MANAGEMENT.md](docs/SOURCE-MANAGEMENT.md) for what each check proves and the difference between source identity and authenticated provenance.

## Xlin Kernel configuration

[`config/x86_64/xlin_defconfig`](config/x86_64/xlin_defconfig) is a documented fragment over the pinned release's upstream x86_64 defconfig, for UEFI desktop/laptop systems with QEMU + OVMF first.

    scripts/xlin-config-check --static    # fast checks
    scripts/xlin-config-check --full      # real kconfig (needs make, gcc, flex, bison)
    tests/config-negative.sh              # broken configs must be rejected

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) and [config/x86_64/README.md](config/x86_64/README.md).

## Plan for Xlin Kernel 0.1

| Item | Decision |
|---|---|
| Upstream | Linux 6.18 LTS, pinned as above |
| Targets | x86_64 UEFI systems and QEMU virtual machines |
| Source in this repository | References and pins only; no copy of the Linux source tree |
| Xlin changes | Config fragment (done); patch files, kept apart from upstream (planned) |
| Release identity | `uname -r` will read `<upstream version>-xlin0.1`; `uname -s` stays `Linux` (planned) |
| Packaging | Arch package `linux-xlin` for XlinOS (planned) |
| Boot chain for XlinOS | UEFI -> existing bootloader -> Xlin Kernel -> initramfs -> systemd -> XlinOS terminal |

## Project family

- **Axion Co.**: parent technology company.
- **Xlin**: this downstream Linux kernel.
- **XlinOS**: the operating system built around Xlin.
- **Xlin Boot**: a possible future bootloader, not part of 0.1.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): what exists and what is planned.
- [docs/SOURCE-MANAGEMENT.md](docs/SOURCE-MANAGEMENT.md): the source pin, Xlin Fetch and Xlin Verify.
- [docs/CONFIGURATION.md](docs/CONFIGURATION.md): the kernel configuration, its decisions and open questions.
- [docs/LICENSING.md](docs/LICENSING.md): licences, file by file.

## Licensing

Licences are chosen file by file; see [docs/LICENSING.md](docs/LICENSING.md) and the SPDX identifier in each file. The Linux kernel keeps its own licence (`GPL-2.0 WITH Linux-syscall-note`) and notices.

## Trademarks

Linux(R) is the registered trademark of Linus Torvalds in the United States and other countries. Xlin is an independent downstream project and is not affiliated with or endorsed by Linus Torvalds, the Linux Foundation or the Linux kernel maintainers. The name "Linux" is used only to say what Xlin is based on.
