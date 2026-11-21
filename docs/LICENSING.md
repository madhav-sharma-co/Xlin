<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Licensing

This file describes how Xlin is licensed. It is not legal advice. **Licences are chosen file by file** according to what each file is, who owns it and what it depends on. No single licence is applied to everything.

## Policy

| Kind of file | Licence |
|---|---|
| Original software (scripts, tests, workflow files, configuration written by Axion Co.) | Chosen individually by purpose and dependencies. Currently `GPL-3.0-or-later` for the scripts, tests, workflow and the lock file that configures them |
| Kernel-derived files and patches (none exist yet) | The applicable Linux kernel licence is preserved: `GPL-2.0-only`, with the `Linux-syscall-note` exception for user-space API headers, exactly as the files being modified state |
| Original documentation | `CC-BY-4.0` |
| Third-party material | Keeps its original licence and notices |

Axion Co. is named as copyright holder only for files it owns. Nothing in this repository relicenses upstream code or documentation.

## Upstream Linux source

Xlin does not store the Linux source. `scripts/xlin-fetch` retrieves it, unmodified, into an ignored directory. It stays under its own terms: the fetched tree states "`GPL-2.0 WITH Linux-syscall-note`" in its `COPYING` file, ships its licence texts under `LICENSES/`, and keeps every copyright notice, `CREDITS` and `MAINTAINERS` entry. Those notices must be preserved in anything Xlin builds or distributes from it.

Linux(R) is the registered trademark of Linus Torvalds. Xlin is an independent downstream project and is not affiliated with or endorsed by him, the Linux Foundation or the kernel maintainers. "Linux" is used only to name the source project.

## GPL-2.0-only and GPL-3.0-or-later

These two licences cannot be combined in a single work. Xlin keeps them apart: the scripts under `GPL-3.0-or-later` only run Git, GnuPG and (later) the kernel build tools as separate programs and contain no kernel code. Anything derived from kernel source will be `GPL-2.0-only` and will be kept in separate files.

## Files in this repository

| Files | Licence | Why |
|---|---|---|
| `scripts/xlin-fetch`, `scripts/xlin-verify`, `scripts/xlin-config-check`, `scripts/xlin-build`, `scripts/xlin-initramfs`, `scripts/xlin-boot-test`, `scripts/lib/xlin-lock.sh`, `tests/negative.sh`, `tests/config-negative.sh`, `tests/build-negative.sh`, `tests/boot-selftest.sh`, `tests/boot-negative.sh`, `tests/boot/init`, `tests/boot/xlin-pass`, `tests/boot/init-broken` | `GPL-3.0-or-later` | Independently written tooling |
| `.github/workflows/source-verification.yml`, `.github/workflows/kernel-config.yml`, `.github/workflows/kernel-build.yml`, `.gitignore` | `GPL-3.0-or-later` | Repository tooling and configuration |
| `upstream/UPSTREAM.lock` | `GPL-3.0-or-later` | Configuration read by the GPL-3.0-or-later scripts |
| `config/x86_64/xlin_defconfig`, `config/x86_64/requirements.txt` | `GPL-2.0-only` | Kernel configuration written against the GPL-2.0 kernel's Kconfig; see "Kernel configuration files" below |
| `README.md`, `CHANGELOG.md`, `docs/*.md`, `config/x86_64/README.md` | `CC-BY-4.0` | Original documentation |
| `LICENSES/GPL-3.0-or-later.txt` | GNU GPL version 3 | Verbatim licence text (copy shipped with Debian/Ubuntu `base-files`) |
| `LICENSES/GPL-2.0-only.txt` | GNU GPL version 2 | Verbatim text from the pinned kernel's own `LICENSES/preferred/GPL-2.0` (kept with its header) |
| `LICENSES/CC-BY-4.0.txt` | Creative Commons Attribution 4.0 International | Verbatim licence text from the SPDX License List data (<https://github.com/spdx/license-list-data>) |

Each file states its licence in an SPDX identifier in its first lines. `LICENSES/` contains only licences that files in this repository actually use. `LICENSES/GPL-2.0-only.txt` was added with the first kernel configuration file; the `Linux-syscall-note` text will be added if a file that needs it is. There is deliberately no single top-level `LICENSE` file, because it would wrongly suggest one licence for everything.

## Kernel configuration files

Provenance of `config/x86_64/xlin_defconfig` and `requirements.txt`:

| Input | Role | Licence of the input |
|---|---|---|
| Upstream `arch/x86/configs/x86_64_defconfig` and the Kconfig files of the pinned release | Starting point and the definition of every symbol. Read in place; the defconfig is **not copied**: the fragment only lists settings that differ | `GPL-2.0-only` (kernel) |
| systemd README, "Kernel Config Options" | Source of the symbol names listed as "systemd" in `requirements.txt`. Only option names are used; no text is copied | systemd is `LGPL-2.1-or-later` |
| Arch Linux `linux-lts-headers` config | Comparison only, done in CI. **Nothing was taken from it**, it is not stored in the repository, and no setting is attributed to it | Distributed by Arch as part of the GPL-2.0 kernel package |
| Axion Co. | The selection, grouping and comments | see below |

The files are marked `GPL-2.0-only`, the licence of the code whose options they configure, so that no incompatibility can arise when they are combined with kernel build files. The choice is conservative, not a legal conclusion.

**Licensing uncertainty, flagged:** whether a list of option names and values is a copyrightable work, and whether a configuration of GPL code is a derivative of it, is not settled by this project and was not reviewed by a lawyer. Option names are facts defined by the kernel; many settings are identical in every distribution's config, so overlap with Arch's config is expected and says nothing about copying. If the reference comparison ever leads to adopting a setting on Arch's evidence, the adoption will be recorded here with the setting. The upstream licence is not changed or overridden, and the scripts under `GPL-3.0-or-later` contain no kernel text: they read symbol names from the fetched tree at run time and run the kernel's own tools as separate programs.

## Built kernel artifacts

The "Kernel build" workflow uploads a compiled `bzImage`, `System.map`, a modules archive and the final `.config` as CI artifacts. They are builds of the unmodified Linux source under `GPL-2.0-only` (with the `Linux-syscall-note` for user-space headers) and carry that licence; the kernel's own copyright notices and licence texts stay in the pinned source. The corresponding source is the pinned upstream commit named in `upstream/UPSTREAM.lock` plus this repository (the configuration and scripts, no kernel patches). The artifacts are build outputs for validation, not a release or a distribution; before any release, the source-offer and notice obligations for distributing the binaries must be satisfied and reviewed. The build adds no third-party code: it uses only the pinned source and the standard GNU toolchain.

## Boot test components

The boot test uses third-party programs that are **installed on the CI runner and are not part of this repository**:

| Component | Use | Licence (as published by its project) |
|---|---|---|
| BusyBox (Ubuntu `busybox-static`) | The only userspace of the test initramfs, copied into it at build time | `GPL-2.0-only` |
| QEMU | Runs the virtual machine | `GPL-2.0` (mostly) |
| OVMF / EDK II (Ubuntu `ovmf`) | UEFI firmware of the virtual machine | `BSD-2-Clause-Patent` (some components under other licences) |
| `usr/gen_init_cpio.c` from the pinned kernel source | Compiled at test time to write the initramfs; the tool is not distributed | `GPL-2.0-only` |

The initramfs itself (which contains BusyBox) is a build output: it is **not committed and not uploaded**; only its manifest (sizes and hashes, BusyBox version) and the logs are. The committed test scripts are `GPL-3.0-or-later` and contain no code from these projects. If an initramfs containing BusyBox is ever distributed, BusyBox's source-offer obligations apply and must be reviewed first. The boot test uses no XlinOS or Arch material.

## Third-party material

Any third-party file added later is listed here with its origin, version, licence and the changes made, and keeps its original notices.

## Open points

- Legal review of the licence choices before the first release.
- Whether to check SPDX headers automatically in CI (for example with the REUSE tool).
