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

### Changed
- Documentation is licensed `CC-BY-4.0`; `docs/LICENSING.md` now describes the file-by-file policy.

No kernel has been built or tested yet.
