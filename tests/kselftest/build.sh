#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build upstream kselftest targets from the PINNED source tree without touching it (everything is
# written to OUT, the tree is checked afterwards by scripts/xlin-verify), and lay out a payload
# directory for tests/kselftest/mk-initramfs.sh. Dynamically linked programs get their shared
# libraries copied next to them. A target or program that does not build is recorded in
# OUT/not-built.txt and reported; it is never silently dropped.
# usage: build.sh SRC OUT TARGET...
set -uo pipefail
src=$1; out=$2; shift 2
[ $# -ge 1 ] || { echo "usage: build.sh SRC OUT TARGET..." >&2; exit 2; }
st=$src/tools/testing/selftests
mkdir -p "$out/obj" "$out/payload/kselftest" "$out/payload/lib" "$out/logs"
: >"$out/not-built.txt"
libs=$out/libs.list; : >"$libs"
for t in "$@"; do
	if ! make -k -C "$st" O="$out/obj" TARGETS="$t" -j"$(nproc)" >"$out/logs/build-$t.log" 2>&1; then
		echo "$t: some programs failed to build (see logs/build-$t.log)" >>"$out/not-built.txt"
	fi
	inst=$out/install-$t
	make -k -C "$st" O="$out/obj" TARGETS="$t" INSTALL_PATH="$inst" install >"$out/logs/install-$t.log" 2>&1 || true
	d=$out/payload/kselftest/$t
	mkdir -p "$d"
	[ -d "$inst/$t" ] && cp -a "$inst/$t/." "$d/"
	: >"$d/list"
	# programs to run: the install's list entries for this target that are ELF executables
	while IFS=: read -r tt prog; do
		[ "$tt" = "$t" ] || continue
		prog=${prog# }
		if [ -x "$d/$prog" ] && head -c4 "$d/$prog" | grep -q 'ELF'; then
			echo "$prog" >>"$d/list"
			ldd "$d/$prog" 2>/dev/null | awk '/=>/ {print $3} /^[ \t]*\// {print $1}' >>"$libs"
		else
			echo "$t:$prog: not an ELF program here (shell/python test or not built); not run" >>"$out/not-built.txt"
		fi
	done <"$inst/kselftest-list.txt"
	echo "$t: $(wc -l <"$d/list") programs to run"
done
sort -u "$libs" | while read -r l; do
	[ -f "$l" ] || continue
	mkdir -p "$out/payload/lib/$(dirname "$l" | sed 's#^/##')"
	cp -L "$l" "$out/payload/lib/${l#/}"
done
# the dynamic loader must be at its absolute path in the guest: /lib64 -> /payload/lib/lib64 (symlinked in init)
echo "not built / not run: $(wc -l <"$out/not-built.txt") entries (see not-built.txt)"
