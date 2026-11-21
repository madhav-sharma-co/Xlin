#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Self-test of the boot-test tooling WITHOUT QEMU and WITHOUT booting anything.
#
#   * scripts/xlin-boot-test is run against a SIMULATED guest (a fake "qemu" that prints
#     scripted serial output) to prove that the harness passes only when every criterion
#     is met, and rejects and classifies each kind of failure.
#   * scripts/xlin-initramfs is run with a tiny stand-in for BusyBox to check the archive
#     structure and its input validation.
#
# This tests the TEST TOOLS. It is not a boot test and says nothing about the kernel.
# The real boot is scripts/xlin-boot-test with the real kernel (see docs/BOOT-TEST.md).
# Needs gcc and python3 and the fetched source (for gen_init_cpio.c).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BT="$ROOT/scripts/xlin-boot-test"
IR="$ROOT/scripts/xlin-initramfs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

passed=0 failed=0
# expect NAME EXIT PATTERN CMD...: CMD must exit with status EXIT and print PATTERN (fixed string).
expect() {
	local name=$1 want=$2 pattern=$3 out rc
	shift 3
	out=$("$@" 2>&1)
	rc=$?
	if [ "$rc" -eq "$want" ] && grep -qF -- "$pattern" <<<"$out"; then
		printf 'PASS  %s (exit %s)\n' "$name" "$rc"
		passed=$((passed + 1))
	else
		printf 'FAIL  %s: exit %s (wanted %s), expected output containing: %s\n' "$name" "$rc" "$want" "$pattern"
		tail -n 12 <<<"$out" | while IFS= read -r l; do printf '        | %s\n' "$l"; done
		failed=$((failed + 1))
	fi
}

# ---- fake inputs: an EFI-looking "kernel", a non-empty initramfs, firmware files ----------
python3 - "$tmp" <<'PY'
import sys
t = sys.argv[1]
k = bytearray(4096)
k[0:2] = b"MZ"
k[60:64] = (128).to_bytes(4, "little")
k[128:132] = b"PE\0\0"
open(t + "/bzImage", "wb").write(k)
open(t + "/initramfs", "wb").write(b"fake initramfs")
open(t + "/CODE.fd", "wb").write(b"fake firmware")
open(t + "/VARS.fd", "wb").write(b"fake vars")
open(t + "/notefi", "wb").write(b"not a kernel" * 100)
PY

# ---- the simulated guest ---------------------------------------------------------------------
cat >"$tmp/fakeqemu" <<'FAKE'
#!/usr/bin/env bash
# Simulated guest for the harness self-test. FAKE_SCENARIO selects the behaviour.
scn=${FAKE_SCENARIO:-pass}
rel=${FAKE_RELEASE:-6.18.64-xlin}
case $scn in
qemu-fails) echo "qemu: fake failure" >&2; exit 1 ;;
silent) sleep 60; exit 0 ;;
esac
echo "[    0.000000] Linux version $rel (fake) #1 SMP"
echo "[    0.010000] efi: EFI v2.7 by EDK II"
echo "[    0.050000] Memory: 900000K/1000000K available (fake)"
echo "[    0.200000] smp: Brought up 1 node, 2 CPUs"
echo "[    0.300000] Unpacking initramfs..."
if [ "$scn" = kernel-panic ]; then
	echo "[    0.310000] Kernel panic - not syncing: VFS: fake"; sleep 30; exit 1
fi
echo "[    0.400000] Run /init as init process"
if [ "$scn" = init-dies ]; then
	echo "[    0.410000] Kernel panic - not syncing: Attempted to kill init! exitcode=0x00000100"; sleep 30; exit 1
fi
echo "XLIN-BOOT-TEST: BEGIN fake"
echo "XLIN-BOOT-TEST: uptime=0.42s"
echo "XLIN-BOOT-TEST: cpu-model=Fake CPU"
echo "XLIN-BOOT-TEST: cpu-count=2"
echo "XLIN-BOOT-TEST: mem-total-kb=1000000"
if [ "$scn" = no-uefi ]; then :; else echo "XLIN-BOOT-TEST: check-ok booted-via-uefi"; fi
[ "$scn" = noshell ] && { sleep 60; exit 0; }
failed=0; [ "$scn" = init-check-fails ] && failed=1
echo "XLIN-BOOT-TEST: SHELL-READY failed=$failed"
[ "$scn" = deaf-shell ] && { sleep 60; exit 0; }
while IFS= read -r line; do
	case $line in
	xlin-pass)
		if [ "$failed" = 0 ]; then echo "XLIN-BOOT-TEST-RESULT: PASS (fake)"; else echo "XLIN-BOOT-TEST-RESULT: FAIL ($failed)"; fi
		[ "$scn" = hang-after-pass ] && { sleep 60; exit 0; }
		exit 0 ;;
	*) eval "$line" ;;
	esac
done
FAKE
chmod +x "$tmp/fakeqemu"

run_bt() { # SCENARIO [extra args...]: run the harness against the simulated guest
	local scn=$1
	shift
	FAKE_SCENARIO=$scn "$BT" --kernel "$tmp/bzImage" --initramfs "$tmp/initramfs" --qemu "$tmp/fakeqemu" \
		--ovmf-code "$tmp/CODE.fd" --ovmf-vars "$tmp/VARS.fd" --accel tcg --out "$tmp/out-$scn" "$@"
}

echo "== simulated guest: the harness must pass only when everything is shown"
expect "sim: complete boot passes" 0 "RESULT: PASS" run_bt pass --timeout 20
expect "sim: pass proves the shell computed the product" 0 "the shell computed" run_bt pass --timeout 20
expect "sim: kernel panic fails (kernel)" 1 "classification: kernel: failed before running /init" run_bt kernel-panic --timeout 20
expect "sim: init dying fails (initramfs)" 1 "classification: initramfs" run_bt init-dies --timeout 20
expect "sim: wrong kernel release fails" 1 "not the expected release" run_bt pass --timeout 20 --expect-release 9.9.9-xlin
expect "sim: no kernel output fails (firmware)" 1 "classification: firmware" run_bt silent --timeout 3
expect "sim: /init that never reaches the shell fails (timeout)" 1 "RESULT: FAIL" run_bt noshell --timeout 4
expect "sim: shell that does not answer fails" 1 "no interactive shell answered" run_bt deaf-shell --timeout 4
expect "sim: failed /init check fails" 1 "FAIL  /init checks passed" run_bt init-check-fails --timeout 20
expect "sim: not booted through UEFI fails" 1 "FAIL  booted through UEFI" run_bt no-uefi --timeout 20
expect "sim: QEMU that stays running after the success marker fails" 1 "FAIL  QEMU exited cleanly with status 0" run_bt hang-after-pass --timeout 8
expect "sim: QEMU that fails to start fails (harness)" 1 "harness: QEMU failed to start" run_bt qemu-fails --timeout 5
expect "sim: timeout is enforced and reported" 1 "FAIL  finished within the time limit" run_bt silent --timeout 2
if [ -s "$tmp/out-pass/serial.log" ] && [ -s "$tmp/out-pass/report.md" ]; then
	echo "PASS  sim: serial log and report are written"
	passed=$((passed + 1))
else
	echo "FAIL  sim: serial log and report are written"
	failed=$((failed + 1))
fi

echo "== invalid inputs and missing dependencies are refused (exit 3)"
expect "kernel missing" 3 "kernel image not found" "$BT" --kernel "$tmp/none" --initramfs "$tmp/initramfs" --qemu "$tmp/fakeqemu" --out "$tmp/o1"
expect "kernel without an EFI header" 3 "not an EFI-bootable kernel" "$BT" --kernel "$tmp/notefi" --initramfs "$tmp/initramfs" --qemu "$tmp/fakeqemu" --out "$tmp/o2"
expect "initramfs missing" 3 "initramfs not found or empty" "$BT" --kernel "$tmp/bzImage" --initramfs "$tmp/none" --qemu "$tmp/fakeqemu" --out "$tmp/o3"
: >"$tmp/empty"
expect "initramfs empty" 3 "initramfs not found or empty" "$BT" --kernel "$tmp/bzImage" --initramfs "$tmp/empty" --qemu "$tmp/fakeqemu" --out "$tmp/o4"
expect "QEMU missing" 3 "QEMU not found" "$BT" --kernel "$tmp/bzImage" --initramfs "$tmp/initramfs" --qemu "$tmp/no-such-qemu" --out "$tmp/o5"
expect "OVMF missing" 3 "OVMF firmware not found" "$BT" --kernel "$tmp/bzImage" --initramfs "$tmp/initramfs" --qemu "$tmp/fakeqemu" --ovmf-code "$tmp/none.fd" --ovmf-vars "$tmp/VARS.fd" --out "$tmp/o6"
expect "invalid timeout" 3 "must be positive" "$BT" --kernel "$tmp/bzImage" --initramfs "$tmp/initramfs" --qemu "$tmp/fakeqemu" --ovmf-code "$tmp/CODE.fd" --ovmf-vars "$tmp/VARS.fd" --timeout 0 --out "$tmp/o7"

echo "== initramfs builder (with a tiny static stand-in for BusyBox)"
SRC="$ROOT/upstream/src/linux"
if [ -f "$SRC/usr/gen_init_cpio.c" ] && command -v gcc >/dev/null && gcc -static -x c -o "$tmp/busybox" - 2>/dev/null <<'C'
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
	if (argc > 1 && !strcmp(argv[1], "--list")) {
		puts("busybox\nsh\nmount\ncat\ngrep\nsed\ncut\nuname\npoweroff\nsetsid\ncttyhack\nsync\necho\nmkdir\nsleep");
		return 0;
	}
	puts("BusyBox v0.0 (test stand-in)");
	return 0;
}
C
then
	expect "initramfs: builds an archive" 0 "Wrote" "$IR" --busybox "$tmp/busybox" --compress gzip --out "$tmp/ir/initramfs.cpio.gz"
	python3 - "$tmp/ir/initramfs.cpio.gz" >"$tmp/ir/listing" 2>&1 <<'PY'
import gzip, sys
d = gzip.open(sys.argv[1]).read()
pos, names = 0, {}
while True:
    assert d[pos:pos + 6] == b"070701", "bad newc magic"
    h = d[pos:pos + 110]
    f = lambda i: int(h[6 + 8 * i:14 + 8 * i], 16)
    mode, size, namesize = f(1), f(6), f(11)
    name = d[pos + 110:pos + 110 + namesize - 1].decode()
    pos = (pos + 110 + namesize + 3) & ~3
    data = d[pos:pos + size]
    pos = (pos + size + 3) & ~3
    if name == "TRAILER!!!":
        break
    names[name] = (oct(mode), data)
for n in ("init", "bin/busybox", "bin/xlin-pass", "dev/console", "bin/sh", "proc", "sys"):
    print(n, "present" if n in names else "MISSING")
print("init-first-line", names["init"][1].split(b"\n")[0].decode())
print("sh-target", names["bin/sh"][1].decode())
print("console-mode", names["dev/console"][0])
print("init-mode", names["init"][0])
PY
	for want in "init present" "bin/busybox present" "bin/xlin-pass present" "dev/console present" "bin/sh present" "init-first-line #!/bin/sh" "sh-target busybox" "console-mode 0o20600" "init-mode 0o100755"; do
		if grep -qxF -- "$want" "$tmp/ir/listing"; then
			echo "PASS  initramfs archive: $want"
			passed=$((passed + 1))
		else
			echo "FAIL  initramfs archive: $want"
			cat "$tmp/ir/listing"
			failed=$((failed + 1))
		fi
	done
	"$IR" --busybox "$tmp/busybox" --compress gzip --out "$tmp/ir/a.gz" >/dev/null 2>&1
	"$IR" --busybox "$tmp/busybox" --compress gzip --out "$tmp/ir/b.gz" >/dev/null 2>&1
	if cmp -s "$tmp/ir/a.gz" "$tmp/ir/b.gz"; then echo "PASS  initramfs archive: two builds are byte-identical"; passed=$((passed + 1)); else echo "FAIL  initramfs archive: two builds differ"; failed=$((failed + 1)); fi
	expect "initramfs: bad --compress" 1 "must be zstd, gzip or xz" "$IR" --busybox "$tmp/busybox" --compress lz4 --out "$tmp/ir/x"
	expect "initramfs: busybox missing" 3 "no BusyBox found" "$IR" --busybox "$tmp/none" --compress gzip --out "$tmp/ir/x"
	expect "initramfs: dynamic binary refused" 3 "not statically linked" "$IR" --busybox /bin/ls --compress gzip --out "$tmp/ir/x"
	expect "initramfs: init script missing" 3 "init script not found" "$IR" --busybox "$tmp/busybox" --init "$tmp/none" --compress gzip --out "$tmp/ir/x"
else
	echo "SKIP  initramfs builder tests (need gcc with static linking and the fetched source)"
fi

echo
echo "Boot-tool self-test: $passed passed, $failed failed (simulated guest only: NOT a boot test)"
[ "$failed" -eq 0 ]
