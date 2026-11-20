<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Changelog

All notable changes to Xlin are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Xlin Source Pin: `upstream/UPSTREAM.lock` pins Linux 6.18.64 (commit `fd7cfd39c88596fec816639ad83cbf3e9d316372`, signed tag `v6.18.64`).
- Xlin Fetch (`scripts/xlin-fetch`): retrieves exactly the pinned source into an ignored directory.
- Xlin Verify (`scripts/xlin-verify`): reports source identity and, separately, authenticated provenance.
- Negative tests (`tests/negative.sh`) and the "Source verification" GitHub Actions workflow.
- `docs/ARCHITECTURE.md` and `docs/SOURCE-MANAGEMENT.md`; `LICENSES/CC-BY-4.0.txt`.

- Xlin Kernel configuration for x86_64 UEFI (`config/x86_64/xlin_defconfig`, a 137-setting fragment over the upstream x86_64 defconfig), `requirements.txt` with the source of each requirement, and `docs/CONFIGURATION.md`.
- `scripts/xlin-config-check` (static and full real-kconfig modes), `tests/config-negative.sh` and the "Kernel configuration" workflow, which also compares against Arch's `linux-lts` config as an informational reference.
- `LICENSES/GPL-2.0-only.txt` and the provenance record for configuration files in `docs/LICENSING.md`.

### Fixed
- Found by the first real kconfig run: upstream's defconfig has no framebuffer, so the console group needed `FB` and `DRM_FBDEV_EMULATION`; the legacy uevent helper is now turned off through `UEVENT_HELPER` (its path symbol does not exist otherwise).

### Changed
- Documentation is licensed `CC-BY-4.0`; `docs/LICENSING.md` now describes the file-by-file policy.

No kernel has been built or booted yet; the configuration has been checked with the real kconfig tools only.
