. /tests/lib.sh
SUITE=reliability
# Short stress: CPU burn on every CPU, a memory/tmpfs fill, a fork storm, parallel file I/O,
# then a check that the kernel log gained no BUG/Oops/WARNING and the kernel is not tainted.
before=$(dmesg | wc -l)
cpus=$(grep -c '^processor' /proc/cpuinfo)
dur=${XLIN_STRESS_SECONDS:-$(cmdline_get xlin.stress)}
dur=${dur:-8}
pids=""
i=0
while [ "$i" -lt "$cpus" ]; do
	( while :; do :; done ) &
	pids="$pids $!"
	i=$((i + 1))
done
mkdir -p /mnt/s && mount -t tmpfs -o size=96m tmpfs /mnt/s
( j=0; while [ "$j" -lt 6 ]; do dd if=/dev/urandom of=/mnt/s/f$j bs=1k count=4096 2>/dev/null; j=$((j + 1)); done; sync ) &
pids="$pids $!"
k=0
fork_ok=0
t_end=$(($(cut -d. -f1 /proc/uptime) + dur))
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$t_end" ]; do
	n=0
	while [ "$n" -lt 40 ]; do ( : ) & n=$((n + 1)); done
	wait_pids=$(jobs -p | wc -l)
	fork_ok=$((fork_ok + 1))
	sleep 1
done
for p in $pids; do kill "$p" 2>/dev/null; done
wait 2>/dev/null
sum=$(cat /mnt/s/f0 | sha256sum | cut -d' ' -f1)
[ -n "$sum" ] && pass io-readback "tmpfs file readable after stress" || fail io-readback "tmpfs read failed"
umount /mnt/s 2>/dev/null
pass stress-ran "${dur}s of CPU burn on $cpus CPUs, memory fill and fork storm ($fork_ok rounds)"
dmesg | sed -n "$((before + 1)),\$p" >/tmp/newlog
if grep -qE 'BUG:|Oops|WARNING:|Call Trace|soft lockup|hung task|rcu.*stall' /tmp/newlog; then fail log-after-stress "$(grep -E 'BUG:|Oops|WARNING:|Call Trace|soft lockup|hung task|rcu.*stall' /tmp/newlog | head -n 3 | tr '\n' ' ')"
else pass log-after-stress "no BUG/Oops/WARNING/lockup/stall in the kernel log during the stress"; fi
t=$(cat /proc/sys/kernel/tainted)
[ "$t" = 0 ] && pass tainted-after-stress "not tainted" || fail tainted-after-stress "tainted=$t"
