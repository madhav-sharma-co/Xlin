# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Shared helpers of the Xlin runtime-validation guest. POSIX sh / BusyBox ash only.
# Every result is one line on the serial console, read by scripts/xlin-runtime-test:
#   XLIN-TEST: <suite> <name> PASS|FAIL|SKIP|INFO <detail>
#   XLIN-METRIC: <name> <value> <unit>            (informational measurements, never gating)
# SKIP always carries the reason; a SKIP is "not tested", never a pass.

say() { echo "XLIN-TEST: $SUITE $1 $2 ${3:-}"; }
pass() { say "$1" PASS "${2:-}"; }
fail() { say "$1" FAIL "${2:-}"; }
skip() { say "$1" SKIP "${2:-}"; }
info() { say "$1" INFO "${2:-}"; }
metric() { echo "XLIN-METRIC: $1 $2 ${3:-}"; }

# ok NAME DETAIL COMMAND...  -> PASS if the command succeeds, else FAIL
ok() {
	_n=$1 _d=$2
	shift 2
	if "$@" >/dev/null 2>&1; then pass "$_n" "$_d"; else fail "$_n" "$_d (command failed: $*)"; fi
}

# BusyBox's shell prefers its own applets for bare command names. The module tests must run the
# kmod tools that the initramfs carries (/bin/modprobe etc. are links to /bin/kmod), so call them
# by full path.
if [ -x /bin/kmod ]; then
	modprobe() { /bin/modprobe "$@"; }
	insmod() { /bin/insmod "$@"; }
	rmmod() { /bin/rmmod "$@"; }
	lsmod() { /bin/lsmod "$@"; }
	depmod() { /bin/depmod "$@"; }
	modinfo() { /bin/modinfo "$@"; }
fi

have() { command -v "$1" >/dev/null 2>&1; }
cmdline_get() { sed -n "s/.*[ ]$1=\([^ ]*\).*/\1/p" /proc/cmdline | head -n1; }

# kernel config of the running kernel (extracted once)
CONFIG=/tmp/config.running
load_config() {
	[ -s "$CONFIG" ] && return 0
	[ -r /proc/config.gz ] || return 1
	zcat /proc/config.gz >"$CONFIG" 2>/dev/null || gunzip -c /proc/config.gz >"$CONFIG" 2>/dev/null
	[ -s "$CONFIG" ]
}
config_is() { grep -qx "CONFIG_$1=$2" "$CONFIG" 2>/dev/null; }

# find_disk ID -> prints the device node whose filesystem holds the file XLIN-DISK-ID == ID.
# Test disks carry their filesystem on the whole device, so no partition table or udev is needed.
find_disk() {
	for _b in /sys/block/*; do
		_n=${_b##*/}
		case $_n in loop* | ram* | zram* | sr*) continue ;; esac
		[ -b "/dev/$_n" ] || continue
		# an empty CD-ROM drive (size 0) cannot be mounted and only makes the kernel log a complaint
		[ "$(cat "/sys/class/block/$_n/size" 2>/dev/null)" != 0 ] || continue
		mkdir -p /mnt/probe
		for _t in "" ext4 vfat iso9660 squashfs udf btrfs xfs exfat; do
			if [ -z "$_t" ]; then mount -o ro "/dev/$_n" /mnt/probe 2>/dev/null || continue
			else mount -t "$_t" -o ro "/dev/$_n" /mnt/probe 2>/dev/null || continue; fi
			_id=$(cat /mnt/probe/XLIN-DISK-ID 2>/dev/null)
			umount /mnt/probe 2>/dev/null
			if [ "$_id" = "$1" ]; then echo "/dev/$_n"; return 0; fi
			break
		done
	done
	return 1
}

# wait_disk ID [SECONDS]: devices such as USB or NVMe appear some time after boot
wait_disk() {
	_i=0
	while [ "$_i" -lt "${2:-20}" ]; do
		find_disk "$1" && return 0
		_i=$((_i + 1))
		sleep 1
	done
	return 1
}

# block_driver DEVNAME: every kernel driver on the path from the block device up to the bus
# (e.g. "sd ahci" or "virtio_blk"), space separated, nearest first
block_driver() {
	_p=$(readlink -f "/sys/class/block/$1")
	_l=""
	while [ -n "$_p" ] && [ "$_p" != / ] && [ "$_p" != /sys ]; do
		if [ -L "$_p/driver" ]; then _l="$_l $(basename "$(readlink -f "$_p/driver")")"; fi
		_p=$(dirname "$_p")
	done
	echo "${_l# }"
}

# the kernel modules image is attached as a disk with the id xlin-modules
setup_modules() {
	[ -d "/lib/modules/$(uname -r)/kernel" ] && return 0
	_d=$(wait_disk xlin-modules 20) || return 1
	mkdir -p "/lib/modules/$(uname -r)"
	mount -t ext4 -o ro "$_d" "/lib/modules/$(uname -r)" 2>/dev/null
}
