<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin v1.0.0 packaging (implemented)

Implemented by `scripts/xlin-package` and the CI `package` job. The package is `xlin-<release>.tar.zst` with the files below plus `initramfs-minimal.cpio.zst`, `xlin-run`, `XLINOS-DEVELOPMENT.md`, `REPRODUCIBILITY-MANIFEST.txt`; `vmlinux` is hashed in the manifest but not shipped. CI packages are unsigned (`SHA256SUMS.sig` appears only with `--sign KEYID`, after the maintainer creates the release key). Arch PKGBUILDs remain a later XlinOS-side phase.

Goal: a release that XlinOS (Arch-based) can consume as its kernel, built only by the existing pinned CI build.

## Release contents
| File | Purpose |
|---|---|
| `vmlinuz-xlin` (the `bzImage`, EFI stub bootable) | the kernel |
| `xlin-modules-<release>.tar.zst` | signed modules, `lib/modules/<release>` |
| `config-<release>` | the exact final `.config` |
| `System.map-<release>` | symbols |
| `vmlinux-<release>.zst` | debug image (separate asset) |
| `SOURCE-PIN.txt` | upstream version, commit, Xlin commit, toolchain versions |
| `SBOM.spdx.json` | bill of materials |
| `SHA256SUMS` and `SHA256SUMS.sig` | integrity and authenticity |
| `RELEASE-NOTES.md` | known limitations, open findings |

## Arch packages for XlinOS (later phase, after approval)
`xlin` (kernel and modules), `xlin-headers`, `xlin-docs`, built from the release assets by a PKGBUILD that verifies `SHA256SUMS` and the signature. The PKGBUILD belongs to the XlinOS project, not this repository.

## Rules
* Artifacts come from a tagged CI run; no local builds are released.
* Keep every prior release; never overwrite assets.
* Release signing key: created offline, public key committed, private key never in CI without a separate decision.
* Publishing needs explicit maintainer approval.
