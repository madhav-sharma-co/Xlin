<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin Kernel configuration: x86_64

| File | What it is |
|---|---|
| [`xlin_defconfig`](xlin_defconfig) | The Xlin configuration, as a **fragment**: only the settings Xlin sets or pins, on top of the upstream `x86_64_defconfig` of the pinned release. |
| [`requirements.txt`](requirements.txt) | Settings the final configuration must (or must not) have, each with its source. Checked automatically. |

The full explanation (strategy, every group of settings, differences from upstream, the Arch reference, open decisions) is in [docs/CONFIGURATION.md](../../docs/CONFIGURATION.md).

## Why a fragment and not a full `.config`

A full `.config` has about 7,000 lines, most of them defaults that change with every kernel release and compiler. A fragment keeps the diff reviewable (each line is an Xlin decision), and the pinned release's own Kconfig computes the rest. The final configuration is reproduced exactly by:

    make x86_64_defconfig
    scripts/kconfig/merge_config.sh -m .config <this fragment>
    make olddefconfig

`scripts/xlin-config-check --full` does exactly this (twice, to prove it is reproducible) in a separate output directory, so the pinned source is never modified.

## Use

    scripts/xlin-fetch                      # the pinned source (once)
    scripts/xlin-config-check --static      # fast: syntax, symbols exist in this release
    scripts/xlin-config-check --full        # real kconfig: needs make, gcc, flex, bison
    scripts/xlin-config-check --full --report out/report    # also keep the final config and the delta

`--static` needs only the fetched source. `--full` configures only; it never compiles the kernel.

## Changing the configuration

1. Edit `xlin_defconfig` (one setting per line; keep it under the right heading) and, if other software needs it, add a line to `requirements.txt` with its source.
2. Run `scripts/xlin-config-check --full`. A setting that "did not take effect" has an unmet dependency: fix the dependency, do not ignore it.
3. Explain the decision in `docs/CONFIGURATION.md` and add a line to `CHANGELOG.md`.

When Xlin moves to a new upstream release (a new `upstream/UPSTREAM.lock`), run the full check first: symbols that were renamed or removed are reported, and the delta shows what the new release changed under Xlin's feet.
