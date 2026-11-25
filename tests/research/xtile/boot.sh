#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
# Boot one kernel N times under one QEMU CPU model and keep every serial log.
# usage: boot.sh OUTDIR LABEL KERNEL INITRAMFS ACCEL CPU REPEAT
set -uo pipefail
outdir=$1; label=$2; kernel=$3; initrd=$4; accel=$5; cpu=$6; n=$7
code=/usr/share/OVMF/OVMF_CODE_4M.fd; vars=/usr/share/OVMF/OVMF_VARS_4M.fd
for i in $(seq 1 "$n"); do
	d="$outdir/$label-$i"; mkdir -p "$d"; cp "$vars" "$d/vars.fd"
	cmd=(qemu-system-x86_64 -machine "q35,accel=$accel" -cpu "$cpu" -m 1024 -smp 2 -display none -monitor none
	     -serial "file:$d/serial.log" -no-reboot -nic none
	     -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" -drive "if=pflash,format=raw,unit=1,file=$d/vars.fd"
	     -kernel "$kernel" -initrd "$initrd" -append "console=ttyS0,115200 loglevel=7 panic=-1 rdinit=/init")
	printf '%q ' "${cmd[@]}" >"$d/qemu-command.txt"; echo >>"$d/qemu-command.txt"
	printf 'label=%s accel=%s cpu=%s kernel=%s\n' "$label" "$accel" "$cpu" "$kernel" >"$d/meta.txt"
	t=120; [ "$accel" = tcg ] && t=400
	timeout "$t" "${cmd[@]}" >"$d/qemu-stdout.txt" 2>&1; echo "qemu_exit=$?" >>"$d/meta.txt"
	grep -q 'XTILE-GUEST: DONE' "$d/serial.log" && echo "completed=yes" >>"$d/meta.txt" || echo "completed=NO" >>"$d/meta.txt"
done
