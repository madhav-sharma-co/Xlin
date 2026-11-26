. /tests/lib.sh
SUITE=measure
# Informational measurements. Nothing here gates a run.
mt=$(sed -n 's/^MemTotal: *\([0-9]*\) kB.*/\1/p' /proc/meminfo)
ma=$(sed -n 's/^MemAvailable: *\([0-9]*\) kB.*/\1/p' /proc/meminfo)
mf=$(sed -n 's/^MemFree: *\([0-9]*\) kB.*/\1/p' /proc/meminfo)
sl=$(sed -n 's/^Slab: *\([0-9]*\) kB.*/\1/p' /proc/meminfo)
metric mem_total "$mt" kB
metric mem_free "$mf" kB
metric mem_available "$ma" kB
metric mem_used_idle "$((mt - ma))" kB
metric slab "$sl" kB
metric processes "$(ls -d /proc/[0-9]* | wc -l)" count
metric cpus "$(grep -c '^processor' /proc/cpuinfo)" count
metric uptime_at_measure "$(cut -d' ' -f1 /proc/uptime)" s
dmesg | sed -n 's/^\[ *\([0-9.]*\)\] Run \/init as init process.*/\1/p' | head -n1 | while read -r t; do metric kernel_to_run_init "$t" s; done
dmesg | sed -n 's/^\[ *\([0-9.]*\)\] Freeing unused kernel image (initmem).*/\1/p' | head -n1 | while read -r t; do metric kernel_init_done "$t" s; done
info metrics "recorded; informational, not gating"
