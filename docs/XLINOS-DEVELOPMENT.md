<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Developing XlinOS on the Xlin Kernel (QEMU + OVMF)

Xlin v1.0.0 is the kernel for XlinOS **in virtual machines**. It has not been run on physical hardware; that is the remaining external limitation. Everything below runs in QEMU with OVMF (UEFI).

## 1. Get the kernel

Either download the CI artifact `xlin-release-candidate` (a `xlin-<release>.tar.zst` and its `.sha256`) from the kernel-build run you want, or build it:

```sh
git clone https://github.com/madhav-sharma-co/Xlin && cd Xlin
sudo apt-get install build-essential flex bison bc libelf-dev libssl-dev zstd kmod file time \
                     qemu-system-x86 ovmf busybox-static          # or the Arch equivalents
./scripts/xlin-fetch && ./scripts/xlin-verify --strict            # pinned Linux 6.18.64, verified
./scripts/xlin-dev-key dev-key.pem                                # DEVELOPMENT signing key, never a release key
./scripts/xlin-build --out "$PWD/build/xlin-x86_64" --signing-key "$PWD/dev-key.pem"
./scripts/xlin-initramfs --out build/minimal.cpio.zst
./scripts/xlin-package --report build/xlin-x86_64/report --out build/dist --initramfs build/minimal.cpio.zst
```

Unpack and verify: `zstd -dc xlin-6.18.64-xlin.tar.zst | tar xf - && cd xlin-6.18.64-xlin && sha256sum -c SHA256SUMS`.

The package contains `vmlinuz-xlin-<release>` (EFI-stub kernel), `modules-<release>.tar.zst`, `config-<release>`, `System.map-<release>`, `initramfs-minimal.cpio.zst`, `xlin-run`, `SOURCE-PIN.txt`, `SBOM.spdx.json`, `SHA256SUMS`, `REPRODUCIBILITY-MANIFEST.txt` and the release notes.

## 2. Boot it

```sh
./xlin-run                                    # minimal BusyBox shell on this terminal (Ctrl-A then X quits)
```

Run `./xlin-run --help` for all options. Defaults: KVM if usable, otherwise software emulation; 2 vCPUs, 2 GiB; OVMF firmware; the original OVMF variable store is never modified.

## 3. Boot your XlinOS root filesystem

Build a root filesystem image for XlinOS (for example `pacstrap` into a directory, then `mke2fs -t ext4 -d rootdir root.img 4G`), install the kernel's modules into it, and boot it as a virtio disk:

```sh
tar --zstd -xf modules-6.18.64-xlin.tar.zst -C rootdir          # puts lib/modules/6.18.64-xlin in the image
./xlin-run --no-initramfs --disk root.img --root /dev/vda --rootfstype ext4 --net --memory 4096 --smp 4
```

`virtio-blk`, `virtio-net`, `virtio-pci` and `ext4` are built into the kernel, so no initramfs is required for this layout. Use the default initramfs only for the minimal shell. If your init system needs an initramfs, supply it with `--initramfs`.

## 4. Things XlinOS must know

* **Kernel release:** `6.18.64-xlin`. Modules live under `/lib/modules/6.18.64-xlin`; run `depmod -a` after installing them (the tarball already contains the `modules.*` files).
* **Module signatures:** modules are signed at build time. `xlin-run` boots with `module.sig_enforce=1` by default, so only modules signed with the build's key can load (tested: scenario `modules-enforce`). The kernel configuration itself does not force this (`MODULE_SIG_FORCE` is off), so a different launcher can choose otherwise. Out-of-tree modules need signing with the key of the build you use; a development build can use your own key via `scripts/xlin-build --signing-key`. Pass `--no-enforce-modules` to disable enforcement while experimenting.
* **No production key exists yet.** Release packages from CI are unsigned (`SHA256SUMS.sig` is created by the maintainer with the production key, which is generated and stored offline by the maintainer and never by CI).
* **Lockdown and securityfs:** the lockdown LSM is built in with mode `none`; for development in QEMU that is the documented configuration. `CONFIG_SECURITYFS` is not set, so `/sys/kernel/security` does not exist (the two probes that need it report UNSUPPORTED). Do not rely on either in XlinOS early development; a decision to enable them belongs in a separate, reviewed change.
* **Console:** serial `ttyS0`; add `--graphic` for a window (simple framebuffer/VGA console).
* **Not configured yet:** Wi-Fi, Bluetooth, sound, laptop power management, BPF/BTF tooling. Add them through the normal configuration-change process with evidence.
* **Open findings:** two kernel messages appear in logs by design and are documented rather than hidden (see `RELEASE-NOTES.md`).
* The kernel pin is Linux 6.18.64. Do not update it as part of XlinOS work.

## 5. Where to look

`docs/RUNTIME-VALIDATION.md` (what is tested and how), `docs/BUILD.md`, `docs/CONFIGURATION.md`, `docs/RELEASE-READINESS.md`, `docs/PHYSICAL-TEST-PLAN.md`.
