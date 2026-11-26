. /tests/lib.sh
SUITE=smp
# SMP and CPU hotplug. The scenario passes xlin.smp=N (the number of vCPUs given to QEMU).
want=$(cmdline_get xlin.smp)
on=$(cat /sys/devices/system/cpu/online 2>/dev/null)
n=$(grep -c '^processor' /proc/cpuinfo)
info cpus "online='$on' processors=$n expected='${want:-unset}'"
[ -n "$want" ] && [ "$n" -eq "$want" ] && pass cpu-count "$n CPUs online, as configured" || fail cpu-count "$n CPUs online, expected '${want:-unset}'"
[ "$n" -ge 2 ] || { skip hotplug "only $n CPU; hotplug and cross-CPU checks need at least 2"; exit 0; }
# every CPU runs work pinned to it
[ -x /tests/coretest ] && /tests/coretest affinity || fail coretest "the helper /tests/coretest is missing"
# Require actual interrupt counts, not merely the presence of label lines. The affinity
# test above exercises cross-CPU scheduling; at least one function-call or reschedule IPI
# should therefore have been delivered on an SMP guest.
ipi=$(grep -E 'Function call interrupts|Rescheduling interrupts|TLB shootdowns' /proc/interrupts | tr -s ' ' | tr '\n' ';')
if printf '%s\n' "$ipi" | awk '
/Function call interrupts|Rescheduling interrupts|TLB shootdowns/ {
	for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/ && $i + 0 > 0) seen = 1
}
END { exit !seen }
'; then
	pass ipi-counters "$ipi"
else
	fail ipi-counters "IPI labels were present but all reported counters were zero or unavailable: $ipi"
fi
# offline and online every non-boot CPU, one at a time, with work in between
fails=0
for c in /sys/devices/system/cpu/cpu[1-9]*; do
	[ -w "$c/online" ] || { skip "hotplug-${c##*/}" "no writable online file (CPU cannot be hot-unplugged)"; continue; }
	echo 0 >"$c/online" 2>/dev/null; off=$(cat "$c/online")
	cnt=$(grep -c '^processor' /proc/cpuinfo)
	( i=0; while [ "$i" -lt 20000 ]; do i=$((i + 1)); done ) && w=ok
	echo 1 >"$c/online" 2>/dev/null; on1=$(cat "$c/online")
	cnt2=$(grep -c '^processor' /proc/cpuinfo)
	if [ "$off" = 0 ] && [ "$cnt" -eq $((n - 1)) ] && [ "$on1" = 1 ] && [ "$cnt2" -eq "$n" ] && [ "$w" = ok ]; then pass "hotplug-${c##*/}" "offline: $cnt CPUs and work still runs; online again: $cnt2"
	else fail "hotplug-${c##*/}" "offline=$off count=$cnt, online=$on1 count=$cnt2"; fails=1; fi
done
t=$(cat /proc/sys/kernel/tainted); [ "$t" = 0 ] && pass tainted "not tainted after hotplug" || fail tainted "tainted=$t"
