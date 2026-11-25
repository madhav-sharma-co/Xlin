#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the throw-away XTILE research initramfs (never committed): static busybox + /xtile-probe + init.
# usage: build-initramfs.sh OUT.cpio.zst   (run from the repository root; needs gcc, busybox-static, zstd)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; root="$(cd "$here/../../.." && pwd)"
out=$(realpath -m "$1"); w=$(mktemp -d)
gcc -O1 -Wall -Wextra -static -o "$w/xtile-probe" "$here/xtile-probe.c"
gcc -O1 -o "$w/gen_init_cpio" "$root/upstream/src/linux/usr/gen_init_cpio.c"
bb=$(command -v busybox); file "$bb" | grep -q 'statically linked' || { echo "busybox is not static: $bb" >&2; exit 3; }
{
	echo "dir /bin 0755 0 0"; echo "dir /sbin 0755 0 0"; echo "dir /proc 0755 0 0"; echo "dir /sys 0755 0 0"; echo "dir /dev 0755 0 0"
	echo "nod /dev/console 0600 0 0 c 5 1"
	echo "file /init $here/init 0755 0 0"
	echo "file /xtile-probe $w/xtile-probe 0755 0 0"
	echo "file /bin/busybox $bb 0755 0 0"
	for a in sh mount grep tr sed dmesg uname poweroff sleep cat; do echo "slink /bin/$a busybox 0777 0 0"; done
} >"$w/list"
"$w/gen_init_cpio" "$w/list" | zstd -q -19 -o "$out" -f
sha256sum "$out" "$w/xtile-probe" "$here/xtile-probe.c" "$here/init"
rm -rf "$w"
