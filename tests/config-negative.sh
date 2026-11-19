#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Negative tests for scripts/xlin-config-check (static mode): each broken input must be REJECTED.
# Needs the source retrieved by scripts/xlin-fetch.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAG="$ROOT/config/x86_64/xlin_defconfig"
REQ="$ROOT/config/x86_64/requirements.txt"
CHK="$ROOT/scripts/xlin-config-check"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

passed=0 failed=0
# expect_reject NAME PATTERN FRAGMENT REQUIREMENTS
expect_reject() {
	local out rc
	out=$("$CHK" --static --fragment "$3" --requirements "$4" 2>&1)
	rc=$?
	if [ "$rc" -ne 0 ] && grep -qF -- "$2" <<<"$out"; then
		printf 'PASS  %s (exit %s)\n' "$1" "$rc"
		passed=$((passed + 1))
	else
		printf 'FAIL  %s: exit %s, expected non-zero and output containing: %s\n' "$1" "$rc" "$2"
		tail -n 8 <<<"$out" | while IFS= read -r l; do printf '        | %s\n' "$l"; done
		failed=$((failed + 1))
	fi
}
mk() { printf '%s\n' "$2" >"$tmp/$1"; }

echo "== the real files are accepted"
if "$CHK" --static >/dev/null 2>&1; then
	echo "PASS  real fragment and requirements pass the static check"
	passed=$((passed + 1))
else
	echo "FAIL  real fragment and requirements do not pass the static check"
	failed=$((failed + 1))
fi

echo "== broken fragments"
{ cat "$FRAG"; echo "CONFIG_XLIN_NO_SUCH_SYMBOL=y"; } >"$tmp/f1"
expect_reject "fragment: symbol that does not exist" "symbols that do not exist" "$tmp/f1" "$REQ"
{ cat "$FRAG"; echo "CONFIG_EXT4_FS=m"; } >"$tmp/f2"
expect_reject "fragment: symbol set twice" "set more than once" "$tmp/f2" "$REQ"
{ cat "$FRAG"; echo "CONFIG_BROKEN"; } >"$tmp/f3"
expect_reject "fragment: malformed setting" "not a comment, blank line or well-formed" "$tmp/f3" "$REQ"
{ cat "$FRAG"; echo "# CONFIG_BROKEN is off"; } >"$tmp/f4"
expect_reject "fragment: malformed 'not set' comment" "not a comment, blank line or well-formed" "$tmp/f4" "$REQ"
sed 's/^CONFIG_USER_NS=y$/# CONFIG_USER_NS is not set/' "$FRAG" >"$tmp/f5"
expect_reject "fragment: turns off a required option" "fragment contradicts requirements" "$tmp/f5" "$REQ"
sed 's/^# CONFIG_FW_LOADER_USER_HELPER is not set$/CONFIG_FW_LOADER_USER_HELPER=y/' "$FRAG" >"$tmp/f6"
expect_reject "fragment: enables a forbidden option" "fragment contradicts requirements" "$tmp/f6" "$REQ"

echo "== broken requirements"
{ cat "$REQ"; echo "XLIN_NO_SUCH_SYMBOL y # test"; } >"$tmp/r1"
expect_reject "requirements: symbol that does not exist" "symbols that do not exist" "$FRAG" "$tmp/r1"
{ cat "$REQ"; echo "EXT4_FS maybe"; } >"$tmp/r2"
expect_reject "requirements: bad expectation" "requirements syntax" "$FRAG" "$tmp/r2"
{ cat "$REQ"; echo "EXT4_FS y"; } >"$tmp/r3"
expect_reject "requirements: duplicate symbol" "requirements syntax" "$FRAG" "$tmp/r3"

echo
echo "Config negative tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
