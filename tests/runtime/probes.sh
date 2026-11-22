# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Table-driven probe runner. Reads /tests/probes.tsv (see tests/runtime/probes.tsv for the
# column meaning) and runs every probe whose id starts with "<group>.".
# A probe whose kernel option is absent from the running kernel's own configuration is
# reported as SKIP with the reason, never silently passed.

special_kaslr() {
	_t=$(grep -m1 ' _text$' /proc/kallsyms | cut -d' ' -f1)
	[ -n "$_t" ] && [ "$_t" != 0000000000000000 ] || { skip "$1" "_text address hidden (kptr_restrict)"; return; }
	if [ "$_t" != ffffffff81000000 ]; then pass "$1" "_text=$_t (not the link-time address)"
	else fail "$1" "_text=$_t is the link-time address: KASLR did not move the kernel"; fi
}
special_vsyscall() {
	if grep -q vsyscall /proc/self/maps; then fail "$1" "a [vsyscall] mapping exists"
	else pass "$1" "no [vsyscall] mapping in /proc/self/maps"; fi
}
special_devmem() {
	[ -c /dev/mem ] || { skip "$1" "/dev/mem does not exist (CONFIG_DEVMEM off): nothing to restrict"; return; }
	_a=$(awk '/System RAM/ { split($1,r,"-"); if (length(r[1]) >= 6 && r[1] != "00100000") { print r[1]; exit } }' /proc/iomem 2>/dev/null)
	[ -n "$_a" ] || _a=$(sed -n 's/^\([0-9a-f]*\)-.* : System RAM$/\1/p' /proc/iomem | sed -n '2p')
	[ -n "$_a" ] || { skip "$1" "no System RAM range found in /proc/iomem"; return; }
	_off=$((0x$_a))
	if dd if=/dev/mem of=/dev/null bs=1 skip=$_off count=16 2>/dev/null; then
		fail "$1" "read 16 bytes of system RAM at 0x$_a through /dev/mem"
	else pass "$1" "reading system RAM at 0x$_a through /dev/mem is refused"; fi
}
special_shuffle() {
	_v=$(cat /sys/module/page_alloc/parameters/shuffle 2>/dev/null)
	if [ -z "$_v" ]; then fail "$1" "page_alloc.shuffle parameter missing: the option is not compiled in"
	elif [ "$_v" = Y ]; then pass "$1" "configured and ACTIVE (shuffle=Y)"
	else pass "$1" "configured (compiled in) but NOT active at runtime: shuffle=$_v; needs page_alloc.shuffle=1 or HMAT memory-side cache"; fi
}
special_cgroup2() {
	mkdir -p /sys/fs/cgroup
	mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || { fail "$1" "cannot mount cgroup2"; return; }
	_c=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null)
	if [ -n "$_c" ]; then pass "$1" "cgroup2 mounted, controllers: $_c"
	else fail "$1" "cgroup2 mounted but no controllers listed"; fi
}
special_efivarfs() {
	[ -d /sys/firmware/efi/efivars ] || { fail "$1" "no /sys/firmware/efi/efivars"; return; }
	mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || mountpoint -q /sys/firmware/efi/efivars || { fail "$1" "cannot mount efivarfs"; return; }
	_n=$(ls /sys/firmware/efi/efivars | wc -l)
	if [ "$_n" -gt 0 ]; then pass "$1" "efivarfs mounted, $_n variables"; else fail "$1" "efivarfs mounted but empty"; fi
}

run_probes() { # GROUP
	load_config || info config-gz "no /proc/config.gz: config-only probes will be skipped"
	TAB=$(printf '\t')
	while IFS="$TAB" read -r id kind arg expected opts desc; do
		case $id in '' | '#'*) continue ;; "$1".*) ;; *) continue ;; esac
		n=${id#*.}
		# the probe is meaningful only if its options are really set in the running kernel
		missing=""
		if [ "$opts" != "-" ] && [ -s "$CONFIG" ]; then
			for o in $(echo "$opts" | tr ',' ' '); do
				config_is "${o%%=*}" "${o#*=}" || missing="$missing $o"
			done
		fi
		if [ -n "$missing" ]; then skip "$n" "UNSUPPORTED by this kernel's configuration (needs${missing}): $desc"; continue; fi
		case $kind in
		sysctl)
			v=$(cat "$arg" 2>/dev/null)
			if [ "$v" = "$expected" ]; then pass "$n" "$desc: $arg=$v"
			else fail "$n" "$desc: $arg is '${v:-unreadable}', expected '$expected'"; fi ;;
		exists)
			if [ -e "$arg" ]; then pass "$n" "$desc: $arg exists"; else fail "$n" "$desc: $arg is missing"; fi ;;
		contains)
			if grep -qF -- "$expected" "$arg" 2>/dev/null; then pass "$n" "$desc ('$expected' in $arg)"
			else fail "$n" "$desc: '$expected' not found in $arg: $(head -c 200 "$arg" 2>/dev/null)"; fi ;;
		lsm)
			if tr ',' '\n' </sys/kernel/security/lsm 2>/dev/null | grep -qx "$arg"; then pass "$n" "$desc (lsm list: $(cat /sys/kernel/security/lsm))"
			else fail "$n" "$desc: not in /sys/kernel/security/lsm ($(cat /sys/kernel/security/lsm 2>/dev/null))"; fi ;;
		dmesg)
			if dmesg | grep -qE -- "$arg"; then pass "$n" "$desc ($(dmesg | grep -E -- 'mem auto-init' | head -n1 | sed 's/^\[[^]]*\] //'))"
			else fail "$n" "$desc: '$arg' not in the kernel log"; fi ;;
		config)
			if [ ! -s "$CONFIG" ]; then skip "$n" "no /proc/config.gz"
			elif config_is "$arg" "$expected"; then pass "$n" "$desc (CONFIG_$arg=$expected; config only, not a behavioural test)"
			else fail "$n" "$desc: CONFIG_$arg is not $expected in the running kernel's config"; fi ;;
		cmd)
			set -- $arg
			if ! have "$1"; then skip "$n" "applet '$1' not in this BusyBox: $desc"
			elif sh -c "$arg" >/dev/null 2>&1; then pass "$n" "$desc ($arg)"
			else fail "$n" "$desc: '$arg' failed"; fi ;;
		special) "special_$arg" "$n" ;;
		*) fail "$n" "bad probe kind '$kind' in probes.tsv" ;;
		esac
	done </tests/probes.tsv
}
