<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin Kernel configuration

This is the first maintained Xlin Kernel configuration, for **x86_64 UEFI desktop and laptop systems**, with QEMU + OVMF as the first target. It is a configuration only: **no kernel has been built from it and nothing has been boot-tested yet.** What has been tested is described under [Verification](#verification).

## Strategy

1. **Start from upstream.** The base is `arch/x86/configs/x86_64_defconfig` of the pinned release (Linux 6.18.64, commit `fd7cfd39c88596fec816639ad83cbf3e9d316372`). It is the configuration the kernel developers maintain for x86_64.
2. **Add a small, documented delta.** `config/x86_64/xlin_defconfig` is a fragment of 137 settings, grouped under headings. Everything not listed keeps the upstream value.
3. **Use Arch Linux's kernel config as a reference, never as a source.** XlinOS is Arch-based, so Arch's choices are a useful cross-check for hardware and filesystem coverage. CI compares the fragment with the config shipped in Arch's `linux-lts-headers` package (the same 6.18.64 release) and reports the differences. No setting was copied from it, and it is not stored in this repository.
4. **Everything that other software needs is written down with its source** in `requirements.txt`, and checked.
5. **Security options stay on** unless there is a technical reason; each exception is listed under [Open decisions](#open-decisions).
6. **No experimental options** were added.

## What the configuration does

| Group | Settings (examples) | Why |
|---|---|---|
| Identity | `LOCALVERSION="-xlin"`, hostname `xlinos` | `uname -r` shows the Xlin origin; the kernel name stays `Linux` |
| Compression | kernel image, initramfs and modules use zstd (xz initramfs also accepted) | Fast to decompress; Arch's mkinitcpio and kmod handle it |
| Modules | `MODULES`, `MODULE_UNLOAD`, `MODULE_SIG` (SHA-512), zstd-compressed | Module support is required; signatures are generated but not yet enforced |
| UEFI boot | `EFI`, `EFI_STUB`, `EFIVAR_FS`, TPM 2 drivers (`TCG_TIS`, `TCG_CRB`), `RESET_ATTACK_MITIGATION` | The kernel boots directly as an EFI application (QEMU + OVMF, systemd-boot); TPM drivers prepare for measured boot |
| Storage | virtio-blk, virtio-scsi, AHCI/SATA, PIIX, NVMe, USB storage and UAS, loop, `BLK_DEV_BSG` | The disks of QEMU and of common PCs, built in so the root filesystem is reachable without extra modules |
| Filesystems | Built in: ext4, FAT/VFAT, squashfs (xz, zstd), overlayfs, ISO 9660, tmpfs (ACL, xattr), autofs. Modules: Btrfs, XFS, exFAT, NTFS3, UDF, FUSE, virtio-fs | Built in = what the live system and a normal install boot from. Modules = common data filesystems that are not needed to boot |
| Networking | IPv6, virtio-net, Intel e1000e (built in), Intel igb/igc (modules), Realtek r8169, Broadcom tg3 | virtio for QEMU, common wired NICs for real machines. **No Wi-Fi or Bluetooth yet** (see open decisions) |
| Console and graphics | VT console, framebuffer console, serial console, `SYSFB_SIMPLEFB`, simpledrm, virtio-gpu, Bochs (QEMU VGA); i915 and AMDGPU as modules | A terminal-only system needs a visible console on a UEFI screen. Upstream's defconfig has no `FB`, so a blank screen would result without the framebuffer console group |
| VM guest | `HYPERVISOR_GUEST`, `KVM_GUEST`, `PARAVIRT`, virtio PCI/balloon/console/rng | Efficient QEMU/KVM guest |
| initramfs and systemd | devtmpfs, cgroups, namespaces (user, net, pid, uts, ipc), inotify, fanotify, signalfd, timerfd, epoll, `FHANDLE`, `DMIID`, seccomp, BPF, PSI; legacy uevent helper and user-space firmware helper **off** | The list in the systemd README (see `requirements.txt`, source "systemd") |
| Security | Yama, Landlock, lockdown LSM, `CPU_MITIGATIONS`, KASLR (base and memory), stack protector (strong), vmapped stacks, `FORTIFY_SOURCE`, hardened usercopy, zero-on-alloc, slab freelist randomisation and hardening, page-allocator shuffle, kernel stack offset randomisation, strict `/dev/mem`, unprivileged BPF off by default, no legacy vsyscall, restricted `dmesg` | Hardening that costs little and is expected on a modern desktop kernel |
| Diagnostics | `IKCONFIG` (+ `/proc/config.gz`), `KALLSYMS`, `MAGIC_SYSRQ`, `PRINTK_TIME`, `DYNAMIC_DEBUG`, `CRASH_DUMP` + `PROC_VMCORE`, zram | A running kernel can report its own configuration and be diagnosed |

## Differences from the upstream x86_64 defconfig

The checker writes the exact list to `delta.txt` (CI prints it in the job log and summary). For the pinned release, with the toolchain recorded below, **296 symbols** differ from the upstream defconfig: the 137 explicit settings plus symbols that follow from their dependencies (for example the framebuffer helper symbols that `FB` pulls in, or the squashfs sub-options). The notable changes of existing defconfig values:

- Kernel image compression: gzip -> **zstd**.
- Intel i915 graphics and the DRM helpers it uses: built in -> **module**. Early console comes from simpledrm on the firmware framebuffer; the full driver loads from the initramfs/udev. This keeps the kernel image smaller, at the cost of a module load before native resolution.
- `EFIVAR_FS`: module -> built in.
- `LEGACY_VSYSCALL_XONLY` -> `LEGACY_VSYSCALL_NONE` (stricter; see risks).
- Added, previously off: NVMe, squashfs, overlayfs, user namespaces, fanotify, BPF syscall, PSI, FORTIFY_SOURCE, hardened usercopy, init-on-alloc, the TPM and security options above, framebuffer console, IKCONFIG, module signing and compression, and the module-built filesystems and NICs.

## Arch Linux reference

| | |
|---|---|
| Reference | `linux-lts-headers 6.18.64-1` from the Arch Linux repositories, file `/usr/lib/modules/*/build/.config`, fetched in CI on each run |
| Use | Comparison only. `scripts/xlin-config-check --arch-ref FILE` lists, for each setting of the fragment, where Arch's final value differs. It never changes the configuration and never fails the check |
| Not done | No setting, comment or ordering was copied from Arch. The reference is not committed |

On the run recorded in the pull request, 25 of the 137 fragment settings differ from Arch's. They fall in three groups, all deliberate:

1. **Built in where Arch builds modules** (NVMe, ATA PIIX, loop, USB storage/UAS, FAT/VFAT, squashfs, overlayfs, ISO 9660, virtio-net, e1000e, r8169, tg3, virtio-gpu, Bochs, virtio balloon/rng). Arch always boots through an initramfs that loads modules. Xlin's first target is the QEMU/OVMF live image, where a built-in root path removes a class of boot failures. This is a trade-off (a larger image), to be revisited when Xlin has measured sizes.
2. **Modules where Arch builds in** (Btrfs, FUSE, virtio-fs). Not needed to boot.
3. **Stricter or different**: `LEGACY_VSYSCALL_NONE`, `RESET_ATTACK_MITIGATION`, the Xlin version string and hostname.

Anything Arch enables that Xlin does not (Wi-Fi, Bluetooth, sound, many more drivers) is outside this first, terminal-only baseline and is not claimed.

## Verification

`scripts/xlin-config-check` and the "Kernel configuration" workflow check, against the real pinned source and the real kernel configuration tools:

- the fragment and requirements files are well-formed, no symbol is set twice, and **every named symbol exists** in this release's Kconfig;
- the two files do not contradict each other;
- `make x86_64_defconfig` + fragment + `make olddefconfig` completes, twice, with **byte-identical** results;
- **every fragment setting is really in effect** in the final config (a setting silently dropped for an unmet dependency fails the check; this found a real problem, see CHANGELOG);
- every requirement holds in the final config;
- `savedefconfig` produces a minimal form that expands back to the identical config;
- the pinned source tree was not modified;
- `tests/config-negative.sh`: ten broken inputs (unknown symbol, duplicate, malformed line, contradicting requirement, ...) are rejected.

Toolchain used in CI: GCC 13.3.0 (Ubuntu 24.04), GNU Make 4.3, flex and bison from Ubuntu. Some Kconfig symbols depend on the compiler, so a different toolchain can give a different final config; the recorded toolchain is part of the evidence.

**Not verified**: that the kernel compiles with this configuration, that it boots, and that any physical hardware works. Those are later steps. No claim of hardware support is made beyond "the driver is enabled".

## Open decisions

| Decision | Current state | Why open |
|---|---|---|
| Enforce module signatures (`MODULE_SIG_FORCE`) | Signing on, enforcement **off** | Needs a key-management and reproducible-build decision: today the signing key would be generated per build, so builds are not byte-reproducible |
| BTF / `DEBUG_INFO_BTF` | Off | Needs `pahole` in the build environment; wanted for BPF tooling |
| Wi-Fi, Bluetooth, sound, laptop extras (touchpad, backlight, suspend) | Not configured | Outside the terminal-only baseline; cannot be tested without hardware |
| Built-in vs module for storage and network drivers | Built in (see Arch section) | Revisit with measured image size and a QEMU/hardware boot matrix |
| `LEGACY_VSYSCALL_NONE` | Set | Breaks very old static binaries (glibc before 2.14). Re-check once Windows-application compatibility software is chosen |
| Lockdown mode | LSM present, mode `none` | Enforcing lockdown interacts with unsigned modules and hibernation; needs the signature decision first |
| Secure Boot and measured boot | TPM drivers only | Needs the bootloader decision (Xlin Boot or existing) |
| Reproducible builds | Not addressed | Depends on the signing key and build environment decisions |

## Licensing

See [LICENSING.md](LICENSING.md). In short: the configuration files are marked `GPL-2.0-only` because they are configuration of, and written against, GPL-2.0 kernel source; this is a conservative choice and is flagged for legal review.
