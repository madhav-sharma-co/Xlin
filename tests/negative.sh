#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Negative tests for Xlin Fetch and Xlin Verify: every case below must be REJECTED.
# Needs the source retrieved by scripts/xlin-fetch (the real pinned source).
# Set XLIN_TEST_NETWORK=1 to also run the test that fetches from a real server.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/upstream/UPSTREAM.lock"
SRC="$ROOT/upstream/src/linux"
[ -d "$SRC/.git" ] || { echo "error: run scripts/xlin-fetch first (no source at $SRC)" >&2; exit 1; }

tmp=$(mktemp -d)
cleanup() {
	git -C "$SRC" checkout -q -- Makefile 2>/dev/null || true
	rm -rf "$tmp"
}
trap cleanup EXIT

passed=0 failed=0 skipped=0
# expect_reject NAME PATTERN CMD...: CMD must exit non-zero and print PATTERN (fixed string).
expect_reject() {
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
# variant NAME SED_EXPR: write a modified copy of the lock file to $tmp/NAME.lock
variant() { sed -e "$2" "$LOCK" >"$tmp/$1.lock"; }

V="$ROOT/scripts/xlin-verify"
F="$ROOT/scripts/xlin-fetch"

echo "== lock file validation"
expect_reject "lock: file missing" "lock file not readable" "$V" --lock "$tmp/nope.lock"
variant nocommit '/^source\.commit=/d'
expect_reject "lock: required key missing" "missing required key 'source.commit'" "$V" --lock "$tmp/nocommit.lock"
variant shortcommit 's/^source\.commit=.*/source.commit=fd7cfd39/'
expect_reject "lock: partial commit hash" "invalid value for 'source.commit'" "$V" --lock "$tmp/shortcommit.lock"
{ cat "$LOCK"; echo "source.version=6.18.65"; } >"$tmp/dup.lock"
expect_reject "lock: duplicate key" "duplicate key 'source.version'" "$V" --lock "$tmp/dup.lock"
{ cat "$LOCK"; echo "surprise.key=1"; } >"$tmp/unknown.lock"
expect_reject "lock: unknown key" "unknown key 'surprise.key'" "$V" --lock "$tmp/unknown.lock"
variant badtag 's/^source\.tag=.*/source.tag=v6.18.65/'
expect_reject "lock: tag does not match version" "does not match source.version" "$V" --lock "$tmp/badtag.lock"
{ cat "$LOCK"; echo "this is not a pair"; } >"$tmp/junk.lock"
expect_reject "lock: line that is not key=value" "not a 'key=value' line" "$V" --lock "$tmp/junk.lock"
sed 's/$/\r/' "$LOCK" >"$tmp/crlf.lock"
expect_reject "lock: CRLF line endings" "control character" "$V" --lock "$tmp/crlf.lock"
variant badfpr 's/^verify\.signer\.fingerprint=.*/verify.signer.fingerprint=647F2865/'
expect_reject "lock: short signer fingerprint" "invalid value for 'verify.signer.fingerprint'" "$V" --lock "$tmp/badfpr.lock"

echo "== verification against the real source with a wrong pin"
variant wrongcommit 's/^source\.commit=.*/source.commit=0123456789abcdef0123456789abcdef01234567/'
expect_reject "verify: wrong pinned commit" "[FAIL] COMMIT" "$V" --lock "$tmp/wrongcommit.lock"
variant wrongobj 's/^source\.tag_object=.*/source.tag_object=0123456789abcdef0123456789abcdef01234567/'
expect_reject "verify: wrong pinned tag object" "[FAIL] TAG" "$V" --lock "$tmp/wrongobj.lock"
variant wrongver 's/^source\.version=.*/source.version=6.18.63/; s/^source\.tag=.*/source.tag=v6.18.63/'
expect_reject "verify: wrong pinned version" "[FAIL] VERSION" "$V" --lock "$tmp/wrongver.lock"
expect_reject "verify: source directory missing" "[FAIL] SOURCE" "$V" --dest "$tmp/empty"
echo "// tampered" >>"$SRC/Makefile"
expect_reject "verify: modified tracked file" "[FAIL] TREE" "$V"
git -C "$SRC" checkout -q -- Makefile

echo "== signature check rejects a key that is not the pinned one"
gh="$tmp/gnupg"
mkdir -m 700 "$gh"
if GNUPGHOME=$gh gpg --batch --quiet --passphrase '' --quick-generate-key "Throwaway <throwaway@example.invalid>" ed25519 sign never 2>/dev/null; then
	GNUPGHOME=$gh gpg --batch --export --armor >"$tmp/throwaway.asc"
	expect_reject "verify: signer key has the wrong fingerprint" "does not have the pinned fingerprint" \
		"$V" --keyfile "$tmp/throwaway.asc"
else
	echo "SKIP  verify: signer key has the wrong fingerprint (could not create a throwaway key)"
	skipped=$((skipped + 1))
fi

echo "== fetch safety"
mkdir -p "$tmp/foreign/linux"
echo "user data" >"$tmp/foreign/linux/keep.txt"
expect_reject "fetch: refuses a directory it did not create" "was not created by Xlin Fetch" "$F" --dest "$tmp/foreign"
if [ "$(cat "$tmp/foreign/linux/keep.txt")" = "user data" ]; then
	echo "PASS  fetch: foreign directory left untouched"
	passed=$((passed + 1))
else
	echo "FAIL  fetch: foreign directory was modified"
	failed=$((failed + 1))
fi
variant unreachable 's#^source\.repository\.official=.*#source.repository.official=https://localhost/xlin-test/none.git#; s#^source\.repository\.mirror=.*#source.repository.mirror=https://localhost/xlin-test/none.git#'
expect_reject "fetch: unreachable server fails and accepts nothing" "Nothing was accepted" \
	"$F" --lock "$tmp/unreachable.lock" --dest "$tmp/offline" --no-checkout

if [ "${XLIN_TEST_NETWORK:-0}" = "1" ]; then
	variant mismatch 's/^source\.commit=.*/source.commit=0123456789abcdef0123456789abcdef01234567/'
	expect_reject "fetch: real tag with a wrong pinned commit is rejected" "SOURCE MISMATCH" \
		"$F" --lock "$tmp/mismatch.lock" --dest "$tmp/mismatch" --source mirror --no-checkout
else
	echo "SKIP  fetch: wrong-pin rejection against a real server (set XLIN_TEST_NETWORK=1)"
	skipped=$((skipped + 1))
fi

echo
echo "Negative tests: $passed passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
