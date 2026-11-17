<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Licensing

**Status: draft policy. The per-category choices below are proposals awaiting approval by Axion Co. This file is not legal advice.**

## Principles

1. **Upstream notices are never removed.** Every copyright notice, licence text and SPDX identifier in Linux source, in patches that modify it and in files copied from other projects stays as it is.
2. **One licence per file, chosen by ownership and derivation.** No single licence is applied to everything. A file's licence is the SPDX identifier in its first lines.
3. **Axion Co. is named as copyright holder only for files it owns.** For changes to upstream files, the existing copyright holders keep their notices.
4. **Only licences that are actually used are included** in `LICENSES/`, as verbatim texts.
5. **Compatibility.** GPL-2.0-only and GPL-3.0-or-later code cannot be combined into one work. Files under the two licences must therefore stay separate programs or separate files that do not copy each other's code.

## The Linux kernel

The kernel is `GPL-2.0-only WITH Linux-syscall-note` (user-space API headers) and `GPL-2.0-only` otherwise, with some files under other compatible licences. Xlin does not copy kernel source into this repository; it records which upstream release is used and how it is fetched and verified.

## Proposed licences by category

| Category | Proposed licence | Reason |
|---|---|---|
| Patches to the Linux kernel (none exist yet) | `GPL-2.0-only` (headers and UAPI files keep their upstream identifiers) | A patch to a GPL-2.0-only file is a derivative work and must use the same licence |
| Kernel config fragments | `GPL-2.0-only` | They consist of Kconfig option names defined by the kernel; the origin of any baseline config will be recorded |
| Build, fetch, verify and test scripts | `GPL-3.0-or-later` | Independently authored programs that only run kernel build tools as separate processes |
| Packaging files (`PKGBUILD`, hooks) | `GPL-3.0-or-later` | Authored by Axion Co. |
| Documentation | `GPL-3.0-or-later` (provisional; `CC-BY-4.0` is an alternative) | Decision pending |

## Open points

- Confirm the documentation licence.
- Review the config-fragment and patch licences with legal counsel before the first release.
- When the first kernel-derived file is added, add `LICENSES/GPL-2.0-only.txt` and, if needed, `LICENSES/Linux-syscall-note.txt`.
- Decide whether to adopt the REUSE specification to check SPDX headers in CI.

## Third-party material

Any third-party file added later is listed here with its origin, version, licence and the changes made.

## Currently in the repository

| File | Licence |
|---|---|
| `README.md`, `CHANGELOG.md`, `docs/LICENSING.md`, `.gitignore` | GPL-3.0-or-later (SPDX header in each file) |
| `LICENSES/GPL-3.0-or-later.txt` | Verbatim GNU GPL version 3 text from the Debian `base-files` copy |
