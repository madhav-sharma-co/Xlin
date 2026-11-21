#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Negative tests that need a REAL boot (QEMU, OVMF, the built Xlin bzImage): the boot test
# must FAIL, and say why, when the guest is wrong. Run by CI after the successful boot.
#
# Usage: tests/boot-negative.sh --kernel BZIMAGE [--busybox PATH]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kernel=""
busybox=""
while [ $# -gt 0 ]; do
	case $1 in
	--kernel) kernel=$2; shift 2 ;;
	--busybox) busybox=$2; shift 2 ;;
	*) echo "unknown option: $1" >&2; exit 3 ;;
	esac
done
[ -f "$kernel" ] || { echo "error: --kernel BZIMAGE is required" >&2; exit 3; }
bb=()
[ -n "$busybox" ] && bb=(--busybox "$busybox")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passed=0 failed=0
expect() { # NAME EXIT PATTERN CMD...
	local name=$1 want=$2 pattern=$3 out rc
	shift 3
	out=$("$@" 2>&1)
	rc=$?
	if [ "$rc" -eq "$want" ] && grep -qF -- "$pattern" <<<"$out"; then
		printf 'PASS  %s (exit %s)\n' "$name" "$rc"
		passed=$((passed + 1))
	else
		printf 'FAIL  %s: exit %s (wanted %s), expected output containing: %s\n' "$name" "$rc" "$want" "$pattern"
		tail -n 15 <<<"$out" | while IFS= read -r l; do printf '        | %s\n' "$l"; done
		failed=$((failed + 1))
	fi
}

"$ROOT/scripts/xlin-initramfs" "${bb[@]}" --out "$tmp/good.cpio.zst" >/dev/null || { echo "error: cannot build the initramfs" >&2; exit 3; }
"$ROOT/scripts/xlin-initramfs" "${bb[@]}" --init "$ROOT/tests/boot/init-broken" --out "$tmp/broken.cpio.zst" >/dev/null || exit 3

echo "== real boots that must be reported as failures"
expect "boot: a /init that exits is a failure (initramfs)" 1 "classification: initramfs" \
	"$ROOT/scripts/xlin-boot-test" --kernel "$kernel" --initramfs "$tmp/broken.cpio.zst" --timeout 180 --out "$tmp/o1"
expect "boot: a wrong expected release is a failure" 1 "FAIL  kernel started with the expected release" \
	"$ROOT/scripts/xlin-boot-test" --kernel "$kernel" --initramfs "$tmp/good.cpio.zst" --expect-release 0.0.0-wrong --timeout 180 --out "$tmp/o2"
expect "boot: a 1 second limit is a failure (timeout)" 1 "FAIL  finished within the time limit" \
	"$ROOT/scripts/xlin-boot-test" --kernel "$kernel" --initramfs "$tmp/good.cpio.zst" --timeout 1 --out "$tmp/o3"

echo
echo "Boot negative tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
