# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Shared helpers for Xlin Fetch and Xlin Verify: a strict parser for
# upstream/UPSTREAM.lock. This file is sourced, not executed. The lock file is
# parsed as data and is never executed as shell code.

declare -A LOCK=()

xlin_die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

# xlin_lock_require KEY REGEX: KEY must exist and match REGEX (extended, anchored by caller).
xlin_lock_require() {
	local key=$1 re=$2
	[ -n "${LOCK[$key]+x}" ] || xlin_die "lock file: missing required key '$key'"
	[[ ${LOCK[$key]} =~ $re ]] || xlin_die "lock file: invalid value for '$key': '${LOCK[$key]}'"
}

# xlin_lock_load FILE: parse and validate FILE into the LOCK array.
xlin_lock_load() {
	local file=$1 line key value n=0 k
	if [ ! -f "$file" ] || [ ! -r "$file" ]; then
		xlin_die "lock file not readable: $file"
	fi
	LOCK=()
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		case $line in '' | '#'*) continue ;; esac
		[[ $line =~ ^([a-z][a-z0-9_.]*)=(.*)$ ]] || xlin_die "$file:$n: not a 'key=value' line"
		key=${BASH_REMATCH[1]}
		value=${BASH_REMATCH[2]}
		[[ $value != *[[:cntrl:]]* ]] || xlin_die "$file:$n: control character in value of '$key'"
		[ -z "${LOCK[$key]+x}" ] || xlin_die "$file:$n: duplicate key '$key'"
		LOCK[$key]=$value
	done <"$file"

	local hex40='^[0-9a-f]{40}$' https='^https://[A-Za-z0-9._~/-]+$'
	xlin_lock_require format '^xlin-source-pin/1$'
	xlin_lock_require xlin.component '^.+$'
	xlin_lock_require pin.established '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
	xlin_lock_require source.project '^.+$'
	xlin_lock_require source.series '^.+$'
	xlin_lock_require source.version '^[0-9]+\.[0-9]+\.[0-9]+$'
	xlin_lock_require source.tag '^v[0-9]+\.[0-9]+\.[0-9]+$'
	xlin_lock_require source.tag_object "$hex40"
	xlin_lock_require source.commit "$hex40"
	xlin_lock_require source.makefile_extraversion '^[A-Za-z0-9._-]*$'
	xlin_lock_require source.repository.official "$https"
	xlin_lock_require source.repository.mirror "$https"
	xlin_lock_require verify.method '^signed-tag$'
	xlin_lock_require verify.signer.name '^.+$'
	xlin_lock_require verify.signer.fingerprint '^[0-9A-F]{40}$'
	xlin_lock_require verify.signer.key_locator '^wkd:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$'
	xlin_lock_require verify.signer.fingerprint_reference "$https"

	[ "${LOCK[source.tag]}" = "v${LOCK[source.version]}" ] ||
		xlin_die "lock file: source.tag '${LOCK[source.tag]}' does not match source.version '${LOCK[source.version]}'"

	for k in "${!LOCK[@]}"; do
		[[ $k =~ ^(format|xlin\.component|pin\.established|source\.[a-z_.]+|verify\.[a-z_.]+|observed\.[a-z0-9_.]+|note\.[a-z0-9_.]+)$ ]] ||
			xlin_die "lock file: unknown key '$k'"
	done
}
