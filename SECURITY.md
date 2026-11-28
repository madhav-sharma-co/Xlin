<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Security policy

Xlin is a development kernel (v1.0.0, QEMU/OVMF) and has no security-update process for its upstream pin yet. Vulnerabilities in Linux itself should be reported to the Linux kernel security team (security@kernel.org). For problems in Xlin's own configuration, scripts, build or packaging, use GitHub's private vulnerability reporting on this repository (Security tab) or contact the maintainer at Axion Co. Please do not open a public issue for an exploitable flaw.

Signing: modules are signed with a per-build key; release packages are unsigned until the maintainer creates the production key. No production key is stored in this repository or in CI.
