#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Negative tests for scripts/xlin-build: it must refuse unsafe or wrong input BEFORE it
# builds anything. Needs the fetched source and the build tools (the CI installs them).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/upstream/src/linux"
B="$ROOT/scripts/xlin-build"
[ -d "$SRC/.git" ] || { echo "error: run scripts/xlin-fetch first" >&2; exit 1; }

tmp=$(mktemp -d)
cleanup() {
	git -C "$SRC" checkout -q -- Makefile 2>/dev/null || true
	rm -f "$SRC/xlin-untracked-test" 2>/dev/null || true
	rm -rf "$tmp"
}
trap cleanup EXIT

passed=0 failed=0
expect_reject() { # NAME PATTERN CMD...
	local name=$1 pattern=$2 out rc
	shift 2
	out=$("$@" 2>&1)
	rc=$?
	if [ "$rc" -ne 0 ] && grep -qF -- "$pattern" <<<"$out"; then
		printf 'PASS  %s (exit %s)\n' "$name" "$rc"
		passed=$((passed + 1))
	else
		printf 'FAIL  %s: exit %s, expected non-zero and output containing: %s\n' "$name" "$rc" "$pattern"
		tail -n 8 <<<"$out" | while IFS= read -r l; do printf '        | %s\n' "$l"; done
		failed=$((failed + 1))
	fi
}

expect_reject "build: --jobs must be a positive integer" "--jobs must be a positive integer" "$B" --jobs 0 --out "$tmp/o1"
mkdir -p "$tmp/foreign"
echo "user data" >"$tmp/foreign/keep.txt"
expect_reject "build: refuses an output directory it did not create" "was not created by Xlin Build" "$B" --out "$tmp/foreign"
if [ "$(cat "$tmp/foreign/keep.txt" 2>/dev/null)" = "user data" ]; then
	echo "PASS  build: foreign directory left untouched"
	passed=$((passed + 1))
else
	echo "FAIL  build: foreign directory was modified"
	failed=$((failed + 1))
fi
echo "// tampered" >>"$SRC/Makefile"
expect_reject "build: refuses a source with a modified file" "modified or untracked files" "$B" --out "$tmp/o2"
git -C "$SRC" checkout -q -- Makefile
: >"$SRC/xlin-untracked-test"
expect_reject "build: refuses a source with an untracked file" "modified or untracked files" "$B" --out "$tmp/o3"
rm -f "$SRC/xlin-untracked-test"

echo
echo "Build negative tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
