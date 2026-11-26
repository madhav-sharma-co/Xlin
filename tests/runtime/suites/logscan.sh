# XLIN_TESTS / XLIN_TMP / dmesg can be redirected so tests/runtime-selftest.sh can drive this very
# script on the host against canned logs (inside the guest the defaults apply)
TD=${XLIN_TESTS:-/tests}
TMPD=${XLIN_TMP:-/tmp}
. "$TD/lib.sh"
SUITE=logscan
# Scan the whole kernel log. A line is "suspect" if its level is warning or worse, or if it
# mentions warning/error/fail/BUG/Oops/taint/lockdep/KASAN-like words. Every suspect line falls
# into exactly one of three tiers:
#   1. matches tests/dmesg-allowlist.txt (accepted, environment-specific notice)  -> INFO allowed
#   2. matches tests/known-findings.txt (known, UNRESOLVED issue)                -> FINDING
#   3. anything else (unexpected)                                                -> FAIL
dmesg -r >"$TMPD/dmesg.raw" 2>/dev/null || dmesg >"$TMPD/dmesg.raw"
total=$(wc -l <"$TMPD/dmesg.raw")
metric kernel_log_lines "$total" lines
# software emulation (TCG) is recognised by the CPU model name QEMU gives it
tcg=0
grep -q 'QEMU TCG CPU' "$TMPD/dmesg.raw" && tcg=1
# allowlist entries with scope "tcg" apply only to TCG guests
: >"$TMPD/allow.ere"
rm -f "$TMPD"/finding.*
awk -F'\t' -v tcg="$tcg" -v out="$TMPD/allow.ere" '!/^#/ && NF >= 2 { if ($3 == "tcg" && tcg != 1) next; print $1 >> out }' "$TD/dmesg-allowlist.txt"
bad=0
allowed=0
findings=0
# strip "<n>" priority prefix for matching, keep it for the level test
while IFS= read -r line; do
	lvl=$(echo "$line" | sed -n 's/^<\([0-9]\)>.*/\1/p')
	text=$(echo "$line" | sed 's/^<[0-9]*>//')
	sus=0
	[ -n "$lvl" ] && [ "$lvl" -le 4 ] && sus=1
	echo "$text" | grep -qiE 'warn(ing)?\b|\berror\b|\bfail(ed|ure)?\b|\bBUG\b|Oops|tainted|lockdep|call trace|unable to|corrupt|\bdeprecated\b' && sus=1
	[ "$sus" -eq 1 ] || continue
	fid=""
	while IFS="$(printf '\t')" read -r id ere status _rest; do
		case "$id" in '#'* | '') continue ;; esac
		if echo "$text" | grep -qE -e "$ere"; then fid="$id $status"; break; fi
	done <"$TD/known-findings.txt"
	if [ -n "$fid" ]; then
		# one FINDING per known finding and boot (with the number of lines and the first one),
		# so a multi-line kernel dump is one finding, not dozens
		findings=$((findings + 1))
		key=${fid%% *}
		if [ -f "$TMPD/finding.$key" ]; then
			n=$(sed -n 1p "$TMPD/finding.$key")
			{ echo $((n + 1)); sed -n '2,3p' "$TMPD/finding.$key"; } >"$TMPD/finding.$key.new" && mv "$TMPD/finding.$key.new" "$TMPD/finding.$key"
		else
			printf '1\n%s\n%s\n' "${fid#* }" "$text" >"$TMPD/finding.$key"
			echo "$key" >>"$TMPD/finding.seen"
		fi
	elif [ -s "$TMPD/allow.ere" ] && echo "$text" | grep -qE -f "$TMPD/allow.ere"; then
		allowed=$((allowed + 1))
		info allowed "$text"
	else
		bad=$((bad + 1))
		fail unexpected "$text"
	fi
done <"$TMPD/dmesg.raw"
# one result per known finding: FINDING if it appeared in this boot, else an explicit "not observed"
# (so how often it appears can be measured, never assumed)
while IFS="$(printf '\t')" read -r id _ere _status _rest; do
	case "$id" in '#'* | '') continue ;; esac
	if [ -f "$TMPD/finding.$id" ]; then
		n=$(sed -n 1p "$TMPD/finding.$id")
		st=$(sed -n 2p "$TMPD/finding.$id")
		first=$(sed -n 3p "$TMPD/finding.$id")
		finding "finding-$id" "[$st] $n line(s); first: $first"
	else
		info "finding-$id" "not observed in this boot"
	fi
done <"$TD/known-findings.txt"
metric kernel_log_allowlisted "$allowed" lines
metric kernel_log_findings "$findings" lines
if [ "$bad" -eq 0 ]; then pass kernel-log-no-unexpected "$total lines scanned, $allowed allowlisted, $findings known finding(s), 0 unexpected"; fi
tainted=$(cat "${XLIN_TAINT_FILE:-/proc/sys/kernel/tainted}" 2>/dev/null)
# bit 12 (4096) is "out-of-tree module"; 8192 "unsigned"; 1 proprietary; others are real problems
if [ "$tainted" = 0 ]; then pass not-tainted "kernel is not tainted"; else fail not-tainted "tainted=$tainted"; fi
