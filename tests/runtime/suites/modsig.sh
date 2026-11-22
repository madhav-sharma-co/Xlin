. /tests/lib.sh
SUITE=modsig
# Runs after logscan because it intentionally taints the kernel: a module WITHOUT a signature.
rel=$(uname -r)
setup_modules || { fail modules-image "no modules disk"; exit 0; }
f="/lib/modules/$rel/xlin-tests/unsigned.ko"
[ -f "$f" ] || { skip unsigned "no unsigned.ko in the modules image"; exit 0; }
sig=$(cat /sys/module/module/parameters/sig_enforce 2>/dev/null)
if insmod "$f" 2>/tmp/err; then
	t=$(cat /proc/sys/kernel/tainted)
	if [ "$sig" = N ]; then pass unsigned-loads-and-taints "sig_enforce=N: unsigned module loaded, tainted=$t (expected, bit 8192)"; else fail unsigned-loads-and-taints "sig_enforce=$sig but an unsigned module loaded"; fi
	rmmod "$(modinfo -F name "$f" 2>/dev/null)" 2>/dev/null
else
	if [ "$sig" = Y ]; then pass unsigned-rejected "sig_enforce=Y: unsigned module refused"; else fail unsigned-rejected "sig_enforce=$sig yet the unsigned module was refused: $(tail -n 1 /tmp/err)"; fi
fi
exit 0
