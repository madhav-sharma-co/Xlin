. /tests/lib.sh
SUITE=rng
want=$(cmdline_get xlin.rng)
avail=$(cat /sys/class/misc/hw_random/rng_available 2>/dev/null)
cur=$(cat /sys/class/misc/hw_random/rng_current 2>/dev/null)
info hwrng "available='$avail' current='$cur'"
case " $avail $cur " in *" ${want:-virtio_rng}"*|*"${want:-virtio_rng}"*) pass "${want:-virtio_rng}-registered" "hwrng: $cur" ;; *) fail "${want:-virtio_rng}-registered" "available='$avail' current='$cur'"; exit 0 ;; esac
[ -c /dev/hwrng ] || { fail hwrng-node "/dev/hwrng missing"; exit 0; }
a=$(dd if=/dev/hwrng bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
b=$(dd if=/dev/hwrng bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
zero=0000000000000000000000000000000000000000000000000000000000000000
if [ ${#a} -eq 64 ] && [ "$a" != "$zero" ] && [ "$a" != "$b" ]; then pass hwrng-data "two 32-byte reads are non-zero and differ"; else fail hwrng-data "unusable data: '$a' '$b'"; fi
