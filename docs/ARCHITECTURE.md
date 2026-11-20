<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Architecture

This describes what exists today and what is planned. Planned parts are marked and are **not** implemented yet.

## Project family

- **Axion Co.**: parent technology company.
- **Xlin**: this downstream Linux kernel project.
- **XlinOS**: the operating system built around Xlin.
- **Xlin Boot**: a possible future bootloader (not part of Xlin Kernel 0.1).

## Principles

1. Xlin is based on upstream Linux. It does not rewrite the kernel.
2. Upstream is never edited in place. Xlin's own work lives in separate, reviewable files (configuration, patches, packaging).
3. Upstream history, copyright and licences are preserved; the origin of the source is always stated.
4. Everything is reproducible: the exact source is pinned by full commit hash and verified.
5. Nothing is reported as working unless it was actually run.

## Layers

| Layer | Purpose | State |
|---|---|---|
| Xlin Source Pin (`upstream/UPSTREAM.lock`) | Names the exact upstream source: version, tag, full commit, signer | **Implemented** |
| Xlin Fetch (`scripts/xlin-fetch`) | Retrieves exactly that source into an ignored directory | **Implemented** |
| Xlin Verify (`scripts/xlin-verify`) | Proves identity (and, where possible, provenance) of the retrieved source | **Implemented** |
| Source verification CI | Runs fetch and verify on the real source | **Implemented** (see the workflow) |
| Xlin Kernel source configuration | Kernel configuration fragments | Planned |
| Xlin patches | Reviewed changes on top of upstream, kept as separate patch files | Planned |
| Build, packaging, QEMU tests | Build the kernel, package it for XlinOS, boot-test it | Planned |

## Data flow (current)

    upstream/UPSTREAM.lock --read by--> scripts/xlin-fetch --> upstream/src/linux   (ignored by Git, never committed)
                                                                      |
    upstream/UPSTREAM.lock --read by--> scripts/xlin-verify <---------+
                                              |
                                  per-check PASS / FAIL / SKIP and a clear verdict

The lock file is the single source of truth. No version, hash or URL is hard-coded in the scripts.

## Scope boundaries of this stage

This section describes the first stage, which only established and verified the source foundation (it did not build the kernel, change kernel source, add patches, create kernel configurations, or touch XlinOS). Later stages added the configuration ([CONFIGURATION.md](CONFIGURATION.md)) and a build validation ([BUILD.md](BUILD.md)); the kernel has still not been booted. See [SOURCE-MANAGEMENT.md](SOURCE-MANAGEMENT.md) for the details of the pin.
