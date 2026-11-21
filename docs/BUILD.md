<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin Kernel build

This documents the **first build** of the Xlin Kernel: the pinned Linux 6.18.64 source compiled with the approved x86_64 configuration ([CONFIGURATION.md](CONFIGURATION.md)). It is a **build validation, not a release**. This page covers the build only; its booting in QEMU is documented in [BOOT-TEST.md](BOOT-TEST.md). Nothing here claims that it works on any hardware.

## Result

| | |
|---|---|
| Compiled | **Yes**: no errors, 0 build warnings |
| Kernel release | `6.18.64-xlin` |
| Source | Linux 6.18.64, commit `fd7cfd39c88596fec816639ad83cbf3e9d316372` (signed tag `v6.18.64`), unmodified |
| Configuration | exactly the approved one: `x86_64_defconfig` + `xlin_defconfig` + `olddefconfig`; the build fails if `olddefconfig` changes it. No option was changed to make the build pass |
| Evidence | GitHub Actions run [44729121034](https://github.com/madhav-sharma-co/Xlin/actions/runs/44729121034) ("Kernel build"); the full report is in its job summary and in the `xlin-kernel-build` artifact |

An earlier run (44727025586) compiled and passed every artifact check, then failed while writing the report (a bug in the report script: `grep` finding no warnings counted as an error under `pipefail`). That was fixed in the build script and the whole build was repeated; the numbers below are from the repeat.

## Toolchain and machine

GCC 13.3.0 (Ubuntu 24.04), GNU ld 2.42, GNU Make 4.3, flex 2.6.4, bison 3.8.2, zstd 1.5.7. GitHub-hosted runner: 4 vCPUs (Intel Xeon 6975P-C), 15.3 GB RAM. Some Kconfig symbols depend on the compiler, so another toolchain may produce a different configuration; this one is the recorded reference.

## Measurements

These are reference points for later comparison. **No comparison with any other kernel has been made, so nothing here shows that Xlin is smaller, lighter or faster than anything.**

| Measurement | Value |
|---|---|
| Compile time (4 jobs) | 12 min 09 s in the run above; 12 min 09 s and 14 min 32 s in the two other full runs. Expect 12-15 min on a shared runner (total with configuration and module install: about 1 min more) |
| Peak memory of the largest single build process | 918 MB |
| Build tree on disk | 1,242 MB |
| `bzImage` (zstd-compressed, EFI stub) | 12,174,336 bytes (11.9 MiB) |
| `vmlinux` (uncompressed ELF) text / data / bss | 29,513,833 / 8,363,034 / 1,132,240 bytes |
| Loadable modules | 39 files, 9,729,035 bytes (9.5 MiB), zstd-compressed |
| Built-in modules | 358 |
| Settings `=y` / `=m` in the final config | 1,746 / 41 |

Across the three full runs the `bzImage` size, `.config`, warning count (0) and peak memory were identical. The `bzImage` hash and the module sizes differ slightly between runs (build timestamp and a per-build module signing key); the `.config` and `System.map` were identical in both. The build is therefore **not** claimed to be byte-reproducible.

### Potentially expensive configuration choices

Observations from the measurements, **for review; nothing was changed**:

- **Two GPU modules are 63 % of all module bytes**: `amdgpu` 4.3 MB and `i915` 1.8 MB (compressed). They are modules, so they cost disk space but no image size or boot memory unless loaded. Btrfs and XFS together are 2.2 MB.
- **Built-in code by subsystem** (text+data of the objects before the final link): drivers 7.35 MB, net 5.20 MB, kernel 4.11 MB, fs 3.25 MB, mm 1.15 MB. Largest built-in driver directories: net 0.95 MB, acpi 0.88 MB, usb 0.69 MB, gpu 0.61 MB, tty 0.37 MB, ata 0.36 MB. The Arch comparison in CONFIGURATION.md already notes that building storage and network drivers in, instead of as modules, is a deliberate size trade-off that this data can now be used to revisit.
- `bzImage` is dominated by the built-in drivers and the networking stack, not by Xlin's own settings; the 137-setting delta from upstream's defconfig has not been measured option by option.

## Artifact checks

The build script (`scripts/xlin-build`) fails unless all of these hold:

- kernel release is `<version>-xlin`; `bzImage` exists and is an x86 boot image **with an EFI/PE header** (checked from the file bytes; this does not prove it boots);
- `vmlinux` (ELF), `System.map` and `.config` exist;
- modules were installed, `modules.dep` and `modules.builtin` exist, and every module is zstd-compressed as configured;
- the pinned source tree is unmodified and at the pinned commit.

`tests/build-negative.sh` checks that the script refuses, before building anything: a bad `--jobs`, an output directory it did not create, a source with a modified file and a source with an untracked file.

## Running it

    scripts/xlin-fetch && scripts/xlin-verify --strict      # the pinned source
    scripts/xlin-build                                      # output in build/xlin-x86_64/

Needs `make gcc flex bison bc zstd kmod file` and the libelf and OpenSSL development headers (Debian/Ubuntu: `build-essential flex bison bc libelf-dev libssl-dev zstd kmod file time`). Output (ignored by Git): `build/` (kernel tree), `staging/` (installed modules), `logs/` and `report/` (`build-report.md`, `build-report.env`, `bzImage`, `System.map`, `config-final`, a modules archive).

The "Kernel build" workflow does this on every pull request and push to `main` (timeout 120 minutes) and uploads `report/` and `logs/` as an artifact kept for 14 days.

## What has not been done

Hardware compatibility, packaging, release, and integration into XlinOS. (Booting in a virtual machine: see [BOOT-TEST.md](BOOT-TEST.md).) The artifacts uploaded by CI are build outputs, not a release.
