. /tests/lib.sh
SUITE=net
# xlin.nic=DRIVER: the single non-loopback interface must use that driver, get a DHCP lease from
# QEMU's user-mode network and reach the gateway (10.0.2.2) with ICMP echo.
want=$(cmdline_get xlin.nic)
_i=0
iface=""
while [ "$_i" -lt 15 ]; do
	for d in /sys/class/net/*; do
		n=${d##*/}
		[ "$n" = lo ] && continue
		iface=$n
	done
	[ -n "$iface" ] && break
	_i=$((_i + 1)); sleep 1
done
[ -n "$iface" ] || { fail iface-appears "no network interface besides lo within 15 s (expected $want)"; exit 0; }
pass iface-appears "$iface"
drv=$(basename "$(readlink -f /sys/class/net/$iface/device/driver)" 2>/dev/null)
if [ "$drv" = "$want" ]; then pass driver "$iface bound to $drv"; else fail driver "$iface bound to '${drv:-none}', expected '$want'"; fi
info mac "$(cat /sys/class/net/$iface/address)"
ifconfig lo 127.0.0.1 up 2>/dev/null
ifconfig "$iface" up 2>/dev/null || ip link set "$iface" up
# wait for link
_i=0; while [ "$_i" -lt 10 ] && [ "$(cat /sys/class/net/$iface/carrier 2>/dev/null)" != 1 ]; do _i=$((_i + 1)); sleep 1; done
[ "$(cat /sys/class/net/$iface/carrier 2>/dev/null)" = 1 ] && pass link "carrier up" || fail link "no carrier after 10 s"
if ! have udhcpc; then skip dhcp "no udhcpc applet"; exit 0; fi
if udhcpc -i "$iface" -n -q -t 5 -T 2 -s /tests/udhcpc.script >/tmp/dhcp.log 2>&1; then
	pass dhcp "$(grep XLIN-DHCP /tmp/dhcp.log | head -n1)"
else fail dhcp "no lease: $(tail -n 3 /tmp/dhcp.log | tr '\n' ' ')"; exit 0; fi
if ping -c 3 -W 3 10.0.2.2 >/tmp/ping.log 2>&1; then pass ping-gateway "$(tail -n 1 /tmp/ping.log)"; else fail ping-gateway "$(tail -n 3 /tmp/ping.log | tr '\n' ' ')"; fi
rx=$(cat /sys/class/net/$iface/statistics/rx_packets); tx=$(cat /sys/class/net/$iface/statistics/tx_packets)
[ "$rx" -gt 0 ] && [ "$tx" -gt 0 ] && pass counters "rx=$rx tx=$tx packets" || fail counters "rx=$rx tx=$tx"
