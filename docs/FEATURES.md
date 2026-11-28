<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin feature coverage and gaps

An audit of what a modern general-purpose kernel provides, against what Xlin v1.0.0 has. "Configured" means the option is in `config/x86_64/xlin_defconfig` and was confirmed in effect by `xlin-config-check`. "Probed" means a guest test exercised the behaviour in QEMU. Anything else is stated as not done. Nothing here claims physical-hardware behaviour. Kernel options were deliberately **not** changed for v1.0.0: each change needs its own evidence run, and several gaps cannot be tested without hardware.

## Present

| Area | State |
|---|---|
| Boot | UEFI EFI stub, zstd-compressed kernel and initramfs, built-in virtio/ext4 root path, KASLR |
| Modules | signed (SHA-512), zstd-compressed; enforcement via `module.sig_enforce=1`, probed |
| Storage | NVMe, AHCI/SATA, virtio-blk/scsi, USB mass storage, loop; probed in QEMU |
| Filesystems | ext4, FAT/VFAT, tmpfs, squashfs, overlayfs, ISO 9660 built in; btrfs, XFS, exFAT, NTFS3, UDF, FUSE, virtio-fs as modules; probed (NTFS3 read-only) |
| Networking | IPv4/IPv6, virtio-net, e1000e, r8169, tg3, igb, igc; DHCP and ICMP probed on virtual NICs only |
| Containers | all namespaces, cgroups with BPF, user namespaces, seccomp filter, PSI |
| BPF | `BPF_SYSCALL`, cgroup BPF, unprivileged BPF off by default |
| Security | Yama, Landlock, lockdown LSM (mode `none`), stack protector strong, FORTIFY, hardened usercopy, VMAP_STACK, slab hardening, init-on-alloc, kernel stack offset randomisation, strict /dev/mem, no vsyscall; probed |
| Memory | zram (module), SMP with hotplug, NUMA-capable x86_64 defconfig; SMP and memory scenarios probed |
| Diagnostics | `/proc/config.gz`, kallsyms, magic SysRq, dynamic debug, crash dump and vmcore; panic recovery probed |
| Virtualisation guest | KVM guest, paravirt, kvm-clock, balloon, virtio console and rng |
| Graphics | simpledrm, virtio-gpu, Bochs, framebuffer console; i915 and amdgpu as modules (not tested) |
| TPM | TIS and CRB drivers (not tested without hardware) |

## Gaps (candidates after v1.0.0, each needs its own change and evidence)

| Gap | Why it is not in v1.0.0 |
|---|---|
| Wi-Fi, Bluetooth | needs hardware and firmware to test |
| Sound | needs hardware (a QEMU sound card could be added) |
| Laptop support: touchpad, backlight, suspend/hibernate, battery | physical hardware only |
| BTF (`DEBUG_INFO_BTF`) | needs `pahole` in the build environment; wanted for BPF tooling |
| Security LSMs beyond Yama/Landlock (AppArmor, SELinux) | XlinOS has not chosen one |
| `CONFIG_SECURITYFS`, enforced lockdown | decided off for development; revisit with Secure Boot |
| Secure Boot, measured boot | needs a bootloader decision |
| `MODULE_SIG_FORCE` in the config | enforcement is applied by the launcher instead; a release decision |
| Sanitiser and fuzz builds (KASAN, KCSAN, lockdep, syzkaller) | would be a separate non-shipping debug configuration |
| kselftest targets exec, sigaltstack, ptrace, mm | do not compile against the pinned headers; reported as not built |
| Performance tuning | page-fault cost is about 2.4x Arch `linux-lts` in the baseline; cause not investigated |
| Security-update process for the pin | none yet |
| aarch64, other architectures | out of scope |

## Rule for adding features

Change `xlin_defconfig` and `requirements.txt` together, run the full CI (config, build, boot, runtime, kselftest, package, reproducibility) and record the evidence in the PR. Do not weaken a gate to get a green run.
