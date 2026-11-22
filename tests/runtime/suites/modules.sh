. /tests/lib.sh
SUITE=modules
# kmod (from the CI runner, copied into the test initramfs) loads and unloads every module of the
# build. Modules that fail with ENODEV need hardware that this VM does not have: they are
# classified, not counted as failures. Anything else (bad format, unknown symbol, rejected
# signature) FAILS.
have modprobe || { fail kmod "kmod is not in the test initramfs"; exit 0; }
rel=$(uname -r)
info kmod "$(modprobe --version 2>&1 | head -n1)"
setup_modules || { fail modules-image "cannot mount the modules disk (id xlin-modules) at /lib/modules/$rel"; exit 0; }
[ -f "/lib/modules/$rel/modules.dep" ] && pass modules-dep "modules.dep present" || { fail modules-dep "modules.dep missing"; exit 0; }
cut -d: -f1 "/lib/modules/$rel/modules.dep" | sed 's|.*/||; s|\.ko.*$||; s|-|_|g' | sort -u >/tmp/modlist
total=$(wc -l </tmp/modlist)
metric modules_total "$total" count
ok_n=0; nodev=0; unl_fail=0; bad=0; unsigned=0
: >/tmp/nodev.list
while read -r m; do
	[ -n "$m" ] || continue
	f=$(modinfo -n "$m" 2>/dev/null)
	if [ -n "$f" ] && [ -z "$(modinfo -F sig_id "$m" 2>/dev/null)" ]; then unsigned=$((unsigned + 1)); fail "$m-signed" "no module signature"; fi
	if modprobe -q "$m" 2>/tmp/err; then
		if modprobe -r "$m" 2>/tmp/err2; then ok_n=$((ok_n + 1)); else unl_fail=$((unl_fail + 1)); info "$m-unload" "loaded but not unloaded: $(cat /tmp/err2)"; fi
	else
		e=$(modprobe "$m" 2>&1 | tail -n 1)
		case $e in
		*"No such device"*|*"No such file or directory"*"$m"*|*ENODEV*) nodev=$((nodev + 1)); echo "$m" >>/tmp/nodev.list ;;
		*) bad=$((bad + 1)); fail "$m-load" "$e" ;;
		esac
	fi
done </tmp/modlist
metric modules_loaded_unloaded "$ok_n" count
metric modules_needing_hardware "$nodev" count
info needs-absent-hardware "$nodev modules returned ENODEV (no matching device in this VM): $(tr '\n' ' ' </tmp/nodev.list | head -c 1500)"
[ "$unl_fail" -eq 0 ] && pass unload "every loaded module could be unloaded" || info unload "$unl_fail modules loaded but did not unload"
[ "$bad" -eq 0 ] && pass load-all "$ok_n loaded and unloaded, $nodev need absent hardware, $unl_fail not unloadable, 0 unexpected failures (of $total)" || fail load-all "$bad of $total modules failed unexpectedly"
[ "$unsigned" -eq 0 ] && pass all-signed "all $total modules carry a signature" || fail all-signed "$unsigned unsigned modules"
t=$(cat /proc/sys/kernel/tainted)
[ "$t" = 0 ] && pass untainted-after-loads "signed module loads do not taint" || fail untainted-after-loads "tainted=$t"
sig=$(cat /sys/module/module/parameters/sig_enforce 2>/dev/null)
info sig_enforce "sig_enforce=$sig (MODULE_SIG_FORCE is an open decision)"
# a signed module with a corrupted body must be rejected even when enforcement is off
if [ -f "/lib/modules/$rel/xlin-tests/tampered.ko" ]; then
	if insmod "/lib/modules/$rel/xlin-tests/tampered.ko" 2>/tmp/err; then fail tampered-rejected "a module with an INVALID signature was loaded"; rmmod tampered 2>/dev/null
	else pass tampered-rejected "invalid signature refused: $(cat /tmp/err | tail -n 1)"; fi
else skip tampered-rejected "no tampered.ko in the modules image"; fi
