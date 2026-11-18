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
| `scripts/xlin-fetch`, `scripts/xlin-verify`, `scripts/lib/xlin-lock.sh`, `tests/negative.sh` | `GPL-3.0-or-later` | Independently written tooling |
| `.github/workflows/source-verification.yml`, `.gitignore` | `GPL-3.0-or-later` | Repository tooling and configuration |
| `upstream/UPSTREAM.lock` | `GPL-3.0-or-later` | Configuration read by the GPL-3.0-or-later scripts |
| `README.md`, `CHANGELOG.md`, `docs/*.md` | `CC-BY-4.0` | Original documentation |
| `LICENSES/GPL-3.0-or-later.txt` | GNU GPL version 3 | Verbatim licence text (copy shipped with Debian/Ubuntu `base-files`) |
| `LICENSES/CC-BY-4.0.txt` | Creative Commons Attribution 4.0 International | Verbatim licence text from the SPDX License List data (<https://github.com/spdx/license-list-data>) |

Each file states its licence in an SPDX identifier in its first lines. `LICENSES/` contains only licences that files in this repository actually use. When the first kernel-derived file is added, `LICENSES/GPL-2.0-only.txt` (and the `Linux-syscall-note` text, if needed) will be added with it. There is deliberately no single top-level `LICENSE` file, because it would wrongly suggest one licence for everything.

## Third-party material

Any third-party file added later is listed here with its origin, version, licence and the changes made, and keeps its original notices.

## Open points

- Legal review of the licence choices before the first release.
- Whether to check SPDX headers automatically in CI (for example with the REUSE tool).
