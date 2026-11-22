. /tests/lib.sh
SUITE=disks
# xlin.devtest=ID:driver[,ID:driver...]  every named disk must appear, be bound to the driver,
# mount as ext4, return the known content, and survive a write / sync / remount round trip.
specs=$(cmdline_get xlin.devtest | tr ',' ' ')
[ -n "$specs" ] || { skip none "no xlin.devtest on the command line"; exit 0; }
for spec in $specs; do
	id=${spec%%:*}
	drv=${spec#*:}
	if ! dev=$(wait_disk "$id" 25); then fail "$id-appears" "no disk with id $id appeared within 25 s (expected driver $drv)"; continue; fi
	n=${dev#/dev/}
	pass "$id-appears" "$dev"
	got=$(block_driver "$n")
	if [ "$got" = "$drv" ]; then pass "$id-driver" "$dev bound to $got"; else fail "$id-driver" "$dev bound to '${got:-none}', expected $drv"; fi
	info "$id-size" "$(($(cat /sys/class/block/$n/size) / 2)) KiB"
	mkdir -p /mnt/d
	if ! mount -t ext4 "$dev" /mnt/d 2>/tmp/err; then fail "$id-mount" "mount ext4 $dev: $(cat /tmp/err)"; continue; fi
	if [ "$(cat /mnt/d/XLIN-TESTFILE 2>/dev/null)" = "xlin-disk-ok" ]; then pass "$id-read" "known file content read"; else fail "$id-read" "XLIN-TESTFILE content wrong"; fi
	r=$(dd if=/dev/urandom bs=1k count=256 2>/dev/null | tee /mnt/d/rw.bin | sha256sum | cut -d' ' -f1)
	sync
	umount /mnt/d && mount -t ext4 "$dev" /mnt/d && w=$(sha256sum </mnt/d/rw.bin | cut -d' ' -f1)
	if [ "$r" = "$w" ] && [ -n "$r" ]; then pass "$id-write" "256 KiB written, synced, remounted, checksum equal"; else fail "$id-write" "checksum after remount differs: $r vs $w"; fi
	umount /mnt/d
done
