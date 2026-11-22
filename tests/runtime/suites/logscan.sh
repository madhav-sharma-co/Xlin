. /tests/lib.sh
SUITE=logscan
# Scan the whole kernel log. A line is "suspect" if its level is warning or worse, or if it
# mentions warning/error/fail/BUG/Oops/taint/lockdep/KASAN-like words. Suspect lines that
# match the reviewed allowlist are INFO; any other suspect line FAILS the suite.
dmesg -r >/tmp/dmesg.raw 2>/dev/null || dmesg >/tmp/dmesg.raw
total=$(wc -l </tmp/dmesg.raw)
metric kernel_log_lines "$total" lines
TAB=$(printf '\t')
sed -n 's/^\([^#\t][^\t]*\)\t.*/\1/p' /tests/dmesg-allowlist.txt >/tmp/allow.ere
bad=0
allowed=0
# strip "<n>" priority prefix for matching, keep it for the level test
while IFS= read -r line; do
	lvl=$(echo "$line" | sed -n 's/^<\([0-9]\)>.*/\1/p')
	text=$(echo "$line" | sed 's/^<[0-9]*>//')
	sus=0
	[ -n "$lvl" ] && [ "$lvl" -le 4 ] && sus=1
	echo "$text" | grep -qiE 'warn(ing)?\b|\berror\b|\bfail(ed|ure)?\b|\bBUG\b|Oops|tainted|lockdep|call trace|unable to|corrupt|\bdeprecated\b' && sus=1
	[ "$sus" -eq 1 ] || continue
	if [ -s /tmp/allow.ere ] && echo "$text" | grep -qE -f /tmp/allow.ere; then
		allowed=$((allowed + 1))
		info allowed "$text"
	else
		bad=$((bad + 1))
		fail unexpected "$text"
	fi
done </tmp/dmesg.raw
metric kernel_log_allowlisted "$allowed" lines
if [ "$bad" -eq 0 ]; then pass kernel-log-clean "$total lines scanned, $allowed allowlisted, 0 unexpected"; fi
tainted=$(cat /proc/sys/kernel/tainted 2>/dev/null)
# bit 12 (4096) is "out-of-tree module"; 8192 "unsigned"; 1 proprietary; others are real problems
if [ "$tainted" = 0 ]; then pass not-tainted "kernel is not tainted"; else fail not-tainted "tainted=$tainted"; fi
