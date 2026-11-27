#!/bin/sh
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
# Build a small initramfs for the CI jobs that run a payload in the guest (kselftest, performance).
# usage: mk-initramfs.sh OUT.cpio.zst INIT-SCRIPT PAYLOAD-DIR   (PAYLOAD-DIR is copied to /payload)
# Needs busybox-static, cpio, zstd. No root.
set -eu
out=$1; init=$2; payload=$3
bb=$(command -v busybox) || { echo "busybox-static not installed" >&2; exit 3; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/sbin" "$t/proc" "$t/sys" "$t/dev" "$t/tmp" "$t/payload" "$t/root"
cp "$bb" "$t/bin/busybox"
for a in $("$bb" --list); do ln -sf busybox "$t/bin/$a"; done
cp "$init" "$t/init"; chmod +x "$t/init"
cp -a "$payload/." "$t/payload/"
( cd "$t" && find . | sort | cpio -o -H newc -R 0:0 --quiet ) | zstd -q -19 -o "$out"
echo "initramfs: $out ($(stat -c %s "$out") bytes)"
