<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Contributing to Xlin

* Xlin never edits the upstream base in place. Changes are configuration, patches (kept apart from the source), scripts, tests or docs.
* Kernel configuration changes: edit `config/x86_64/xlin_defconfig` and `config/x86_64/requirements.txt` together, with a reason, and let CI prove them (see [docs/FEATURES.md](docs/FEATURES.md)).
* Do not weaken, skip or allowlist a test or gate to make CI pass. A new finding is classified in `tests/kselftest/expected.txt` or the runtime known-findings tiers with its evidence.
* Never claim physical-hardware compatibility or production readiness from QEMU results.
* Use a branch and a pull request; keep the upstream pin (`upstream/UPSTREAM.lock`) changes in their own PR with justification.
* Never commit signing keys (they are in `.gitignore`).
* Every file carries an SPDX header; see [docs/LICENSING.md](docs/LICENSING.md).
