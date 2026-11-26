. /tests/lib.sh
SUITE=graphics
# Framebuffer / DRM devices exist and the framebuffer console is active. Pixel contents are NOT
# checked (not tested: would need a host-side screendump).
fbs=$(ls /dev/fb[0-9]* 2>/dev/null | tr '\n' ' ')
cards=$(ls /dev/dri/card[0-9]* 2>/dev/null | tr '\n' ' ')
info devices "fb: ${fbs:-none} drm: ${cards:-none}"
if [ -c /dev/fb0 ]; then
	pass fb0 "name=$(cat /sys/class/graphics/fb0/name 2>/dev/null) size=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null) bpp=$(cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null)"
else fail fb0 "/dev/fb0 missing (config has FB and DRM_FBDEV_EMULATION)"; fi
if [ -c /dev/dri/card0 ]; then
	drv=$(basename "$(readlink -f /sys/class/drm/card0/device/driver)" 2>/dev/null)
	pass drm-card0 "driver=${drv:-unknown}"
else fail drm-card0 "/dev/dri/card0 missing"; fi
if dmesg | grep -qE 'fbcon: .*(frame buffer device|is primary device)|Console: switching to colour frame buffer device'; then
	pass fbcon "$(dmesg | grep -E 'fbcon:|colour frame buffer' | head -n1 | sed 's/^\[[^]]*\] //')"
else fail fbcon "no framebuffer console message in the kernel log"; fi
[ -d /sys/class/graphics/fbcon ] && pass fbcon-sysfs "/sys/class/graphics/fbcon exists" || fail fbcon-sysfs "missing"
skip pixels "not tested: framebuffer contents are not captured"
