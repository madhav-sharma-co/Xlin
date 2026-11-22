. /tests/lib.sh
SUITE=fs
# xlin.fstest=ID:fstype:ro|rw,...   plus the pseudo entries tmpfs, overlay:ID and fuse
# Each disk carries XLIN-FS-TEST with the text xlin-fs-ok-<fstype>. rw filesystems also get a
# write / sync / remount round trip. A filesystem the kernel does not have is a FAIL, unless the
# build has no option for it at all, which is reported as not available.
setup_modules >/dev/null 2>&1
fs_available() { grep -qw "$1" /proc/filesystems || { have modprobe && modprobe -q "$1" 2>/dev/null && grep -qw "$1" /proc/filesystems; }; }
for spec in $(cmdline_get xlin.fstest | tr ',' ' '); do
	case $spec in
	tmpfs)
		mkdir -p /mnt/t && mount -t tmpfs -o size=64m tmpfs /mnt/t || { fail tmpfs-mount "cannot mount tmpfs"; continue; }
		a=$(dd if=/dev/urandom bs=1k count=8192 2>/dev/null | tee /mnt/t/big | sha256sum | cut -d' ' -f1)
		b=$(sha256sum </mnt/t/big | cut -d' ' -f1)
		[ "$a" = "$b" ] && pass tmpfs-rw "8 MiB written and read back" || fail tmpfs-rw "checksum differs"
		umount /mnt/t ;;
	fuse)
		if fs_available fuse && [ -c /dev/fuse ]; then pass fuse "fuse registered and /dev/fuse present (no userspace FUSE daemon is run: mounting is not tested)"
		else fail fuse "fuse: filesystem registered=$(grep -cw fuse /proc/filesystems) /dev/fuse=$([ -c /dev/fuse ] && echo yes || echo no)"; fi ;;
	overlay:*)
		id=${spec#overlay:}
		fs_available overlay || { fail overlayfs "overlay filesystem not available"; continue; }
		dev=$(wait_disk "$id" 20) || { fail overlayfs "lower disk $id not found"; continue; }
		mkdir -p /mnt/lo /mnt/up /mnt/ov
		mount -t squashfs -o ro "$dev" /mnt/lo || { fail overlayfs "cannot mount lower squashfs"; continue; }
		mount -t tmpfs tmpfs /mnt/up && mkdir -p /mnt/up/u /mnt/up/w
		if mount -t overlay overlay -o lowerdir=/mnt/lo,upperdir=/mnt/up/u,workdir=/mnt/up/w /mnt/ov 2>/tmp/err; then
			echo new >/mnt/ov/new-file
			rm -f /mnt/ov/XLIN-FS-TEST
			if [ -f /mnt/up/u/new-file ] && [ ! -e /mnt/ov/XLIN-FS-TEST ] && [ -f /mnt/lo/XLIN-FS-TEST ]; then pass overlayfs "squashfs lower + tmpfs upper: copy-up/whiteout behave, lower untouched"
			else fail overlayfs "overlay semantics wrong"; fi
			umount /mnt/ov
		else fail overlayfs "mount overlay: $(cat /tmp/err)"; fi
		umount /mnt/up; umount /mnt/lo ;;
	*:*:*)
		id=${spec%%:*}; rest=${spec#*:}; type=${rest%%:*}; mode=${rest#*:}
		if ! fs_available "$type"; then fail "$type" "filesystem '$type' is not available in this kernel (not in /proc/filesystems, no module loaded)"; continue; fi
		if ! dev=$(wait_disk "$id" 20); then fail "$type" "disk $id not found"; continue; fi
		mkdir -p /mnt/f
		opt=ro; [ "$mode" = rw ] && opt=rw
		if ! mount -t "$type" -o "$opt" "$dev" /mnt/f 2>/tmp/err; then fail "$type" "mount: $(cat /tmp/err)"; continue; fi
		if [ "$(cat /mnt/f/XLIN-FS-TEST 2>/dev/null)" = "xlin-fs-ok-$type" ]; then pass "$type-read" "mounted $opt, known content read"; else fail "$type-read" "wrong or missing XLIN-FS-TEST"; fi
		if [ "$mode" = rw ]; then
			a=$(dd if=/dev/urandom bs=1k count=512 2>/dev/null | tee /mnt/f/rw.bin | sha256sum | cut -d' ' -f1)
			sync; umount /mnt/f && mount -t "$type" "$dev" /mnt/f && b=$(sha256sum </mnt/f/rw.bin | cut -d' ' -f1)
			[ "$a" = "$b" ] && pass "$type-write" "512 KiB written, synced, remounted, checksum equal" || fail "$type-write" "checksum differs after remount"
		fi
		umount /mnt/f ;;
	*) fail bad-spec "unknown xlin.fstest entry '$spec'" ;;
	esac
done
