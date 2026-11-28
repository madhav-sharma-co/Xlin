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
mkdir -p /mnt/s && mount -t tmpfs -o size=96m tmpfs /mnt/s || { fail tmpfs-mount "cannot mount the 96 MiB stress filesystem"; exit 0; }
( j=0; while [ "$j" -lt 6 ]; do
	dd if=/dev/urandom of=/mnt/s/f$j bs=1k count=4096 2>/dev/null || exit 1
	sha256sum /mnt/s/f$j | cut -d' ' -f1 >"/mnt/s/f$j.sha256" || exit 1
	j=$((j + 1))
done; sync ) &
pids="$pids $!"
fork_ok=0
t_end=$(($(cut -d. -f1 /proc/uptime) + dur))
while [ "$(cut -d. -f1 /proc/uptime)" -lt "$t_end" ]; do
	n=0
	while [ "$n" -lt 40 ]; do ( : ) & n=$((n + 1)); done
	fork_ok=$((fork_ok + 1))
	sleep 1
done
for p in $pids; do kill "$p" 2>/dev/null; done
wait 2>/dev/null
io_ok=1
j=0
while [ "$j" -lt 6 ]; do
	expected=$(cat "/mnt/s/f$j.sha256" 2>/dev/null)
	actual=$(sha256sum "/mnt/s/f$j" 2>/dev/null | cut -d' ' -f1)
	[ -n "$expected" ] && [ "$expected" = "$actual" ] || io_ok=0
	j=$((j + 1))
done
[ "$io_ok" -eq 1 ] && pass io-readback "six 4 MiB tmpfs files match their recorded SHA-256 checksums after stress" || fail io-readback "one or more tmpfs files were missing, incomplete or changed"
umount /mnt/s && pass tmpfs-unmount "stress filesystem unmounted cleanly" || fail tmpfs-unmount "could not unmount stress filesystem"
pass stress-ran "${dur}s of CPU burn on $cpus CPUs, memory fill and fork storm ($fork_ok rounds)"
dmesg | sed -n "$((before + 1)),\$p" >/tmp/newlog
if grep -qE 'BUG:|Oops|WARNING:|Call Trace|soft lockup|hung task|rcu.*stall' /tmp/newlog; then fail log-after-stress "$(grep -E 'BUG:|Oops|WARNING:|Call Trace|soft lockup|hung task|rcu.*stall' /tmp/newlog | head -n 3 | tr '\n' ' ')"
else pass log-after-stress "no BUG/Oops/WARNING/lockup/stall in the kernel log during the stress"; fi
t=$(cat /proc/sys/kernel/tainted)
[ "$t" = 0 ] && pass tainted-after-stress "not tainted" || fail tainted-after-stress "tainted=$t"
