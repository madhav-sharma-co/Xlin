. /tests/lib.sh
SUITE=timer
# Clock source, timer interrupts and timer behaviour as seen from user space.
cs=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null)
av=$(cat /sys/devices/system/clocksource/clocksource0/available_clocksource 2>/dev/null)
[ -n "$cs" ] && pass clocksource "current='$cs' available='$av'" || fail clocksource "no clocksource0 in sysfs"
case "$cs" in jiffies) fail clocksource-not-jiffies "the kernel fell back to the jiffies clocksource" ;; *) pass clocksource-not-jiffies "$cs" ;; esac
# the timer interrupt is delivered on every online CPU: the local timer line grows
l() { grep -E '^ *LOC:' /proc/interrupts | head -n1 | tr -s ' ' | cut -d' ' -f3-; }
a=$(l); sleep 1; b=$(l)
if [ -n "$a" ] && [ "$a" != "$b" ]; then pass local-timer-ticks "LOC (local timer) interrupts advanced: '$a' -> '$b'"
else info local-timer-ticks "LOC counters did not advance in 1 s ('$a' -> '$b'); NO_HZ idle can do this on a quiet VM"; fi
# sleep must take at least the requested time by the kernel's own uptime clock
u1=$(cut -d' ' -f1 /proc/uptime); sleep 2; u2=$(cut -d' ' -f1 /proc/uptime)
d=$(echo "$u1 $u2" | awk '{printf "%d", ($2-$1)*1000}')
[ "$d" -ge 1950 ] && [ "$d" -lt 4000 ] && pass sleep-uptime "sleep 2 advanced /proc/uptime by ${d} ms" || fail sleep-uptime "sleep 2 advanced /proc/uptime by ${d} ms"
[ -x /tests/coretest ] || { fail coretest "the helper /tests/coretest is not in the initramfs"; exit 0; }
/tests/coretest timer
rc=$?
[ "$rc" -eq 0 ] || fail coretest-exit "coretest timer exited with status $rc"
metric timer_clocksource_is_tsc "$([ "$cs" = tsc ] && echo 1 || echo 0)" bool
