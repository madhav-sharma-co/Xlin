. /tests/lib.sh
SUITE=mm
# Memory management: /proc/meminfo sanity, the kernel's own view of free memory, then user-space
# mappings and memory accounting (tests/runtime/coretest.c mm), then a tmpfs size limit.
mt=$(grep '^MemTotal:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2)
mf=$(grep '^MemFree:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2)
[ -n "$mt" ] && [ -n "$mf" ] && [ "$mf" -le "$mt" ] && [ "$mt" -gt 100000 ] && pass meminfo "MemTotal ${mt} kB, MemFree ${mf} kB" || fail meminfo "implausible /proc/meminfo: total='$mt' free='$mf'"
[ -x /tests/coretest ] || { fail coretest "the helper /tests/coretest is not in the initramfs"; exit 0; }
/tests/coretest mm
rc=$?
[ "$rc" -eq 0 ] || fail coretest-exit "coretest mm exited with status $rc"
# tmpfs enforces its size limit with ENOSPC instead of consuming all memory
mkdir -p /mnt/lim && mount -t tmpfs -o size=8m tmpfs /mnt/lim
dd if=/dev/zero of=/mnt/lim/f bs=1k count=16384 2>/dev/null
sz=$(wc -c </mnt/lim/f)
[ "$sz" -le 8388608 ] && [ "$sz" -gt 0 ] && pass tmpfs-limit "write stopped at $sz bytes on an 8 MiB tmpfs" || fail tmpfs-limit "file is $sz bytes on an 8 MiB tmpfs"
umount /mnt/lim 2>/dev/null
t=$(cat /proc/sys/kernel/tainted); [ "$t" = 0 ] && pass tainted "not tainted" || fail tainted "tainted=$t"
