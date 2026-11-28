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
		grep -E 'error|Error|fatal' "$out/logs/build-$t.log" | head -n 6 | sed "s/^/    [$t] /"
	fi
	inst=$out/install-$t
	make -k -C "$st" O="$out/obj" TARGETS="$t" INSTALL_PATH="$inst" install >"$out/logs/install-$t.log" 2>&1 || true
	d=$out/payload/kselftest/$t
	mkdir -p "$d"
	[ -d "$inst/$t" ] && cp -a "$inst/$t/." "$d/"
	: >"$d/list"
	# programs to run: the install's list entries for this target that are ELF executables
	[ -f "$inst/kselftest-list.txt" ] || { echo "$t: no install list (build failed before install)" >>"$out/not-built.txt"; continue; }
	while IFS=: read -r tt prog; do
		[ "$tt" = "$t" ] || continue
		prog=${prog# }
		first=$(head -n1 "$d/$prog" 2>/dev/null | tr -d '\r')
		if [ -x "$d/$prog" ] && { head -c4 "$d/$prog" | grep -q 'ELF' || [ "$first" = '#!/bin/sh' ]; }; then
			echo "$prog" >>"$d/list"
			ldd "$d/$prog" 2>/dev/null | awk '/=>/ {print $3} /^[ \t]*\// {print $1}' >>"$libs"
		else
			echo "$t:$prog: not an ELF program or a /bin/sh script here (bash/python test, or not built); not run" >>"$out/not-built.txt"
		fi
	done <"$inst/kselftest-list.txt"
	# helper programs started by the tests (not listed themselves) need their libraries too
	for f in "$d"/*; do
		[ -f "$f" ] || continue
		head -c4 "$f" | grep -q 'ELF' || continue
		ldd "$f" 2>/dev/null | awk '/=>/ {print $3} /^[ \t]*\// {print $1}' >>"$libs"
	done
	echo "$t: $(wc -l <"$d/list") programs to run"
done
# libgcc_s is loaded with dlopen by pthread_cancel and does not show up in ldd
gcc -print-file-name=libgcc_s.so.1 >>"$libs"
# libnuma is needed by futex_numa_mpol, which is not on the program list when ldd is run
for n in /usr/lib/x86_64-linux-gnu/libnuma.so.1 /lib/x86_64-linux-gnu/libnuma.so.1; do [ -f "$n" ] && echo "$n" >>"$libs"; done
mkdir -p "$out/payload/lib/flat" "$out/payload/lib/lib64"
sort -u "$libs" | while read -r l; do
	[ -f "$l" ] || continue
	case $(basename "$l") in
	ld-linux*) cp -L "$l" "$out/payload/lib/lib64/$(basename "$l")" ;;
	*) cp -L "$l" "$out/payload/lib/flat/$(basename "$l")" ;;
	esac
done
# in the guest: /lib64 -> /payload/lib/lib64 (the loader) and LD_LIBRARY_PATH=/payload/lib/flat (set in init)
echo "not built / not run: $(wc -l <"$out/not-built.txt") entries (see not-built.txt)"
