#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Axion Co.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Self-test of scripts/xlin-runtime-test with a SIMULATED guest: a fake "qemu" prints canned
# serial output. This is NOT a boot test; it proves the judge says FAIL when it must, and
# reports NOT TESTED / flake rate correctly. Needs only bash and python3.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok() { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }

# fixtures: an EFI-looking kernel, an initramfs, OVMF files, images.txt
python3 - "$T/bzImage" <<'PY'
import sys
b = bytearray(512)
b[0:2] = b"MZ"
b[60:64] = (128).to_bytes(4, "little")
b[128:132] = b"PE\0\0"
open(sys.argv[1], "wb").write(b)
PY
: >"$T/initramfs.cpio.zst"; echo x >"$T/initramfs.cpio.zst"
echo "kmod: fake" >"$T/initramfs.cpio.zst.manifest"
echo c >"$T/CODE.fd"; echo v >"$T/VARS.fd"
mkdir "$T/images"
printf 'built ext4 1\nbuilt modules 1\nbuilt scratch 1\nnot-built fs-xfs needs xfsprogs\n' >"$T/images/images.txt"
for i in ext4 modules scratch; do echo x >"$T/images/$i.img"; done
printf 'CONFIG_IKCONFIG_PROC=y\nCONFIG_VIRTIO_BLK=y\nCONFIG_EXT4_FS=y\n' >"$T/config-final"
SHA=$(sha256sum "$T/config-final" | cut -d' ' -f1)

REL=$(sed -n 's/^source.version=//p' "$ROOT/upstream/UPSTREAM.lock")-xlin
# fake qemu: prints $FAKE_LOG (a file), then exits with $FAKE_RC (default 0)
cat >"$T/qemu" <<'Q'
#!/bin/sh
cat "$FAKE_LOG"
exit "${FAKE_RC:-0}"
Q
chmod +x "$T/qemu"

good_log() { # SUITES...  -> a plausible serial log
	{
		echo "[    0.000000] Linux version $REL (gcc) #1 SMP"
		echo "[    0.100000] efi: EFI v2.7 by EDK II"
		echo "[    1.000000] Run /init as init process"
		echo "XLIN-RUNTIME: BEGIN pid=1 uptime=1.0 release=$REL suites=$*"
		for s in "$@"; do
			echo "XLIN-SUITE: $s BEGIN"
			echo "XLIN-TEST: $s something PASS fine"
			[ "$s" = config ] && echo "XLIN-CONFIG-SHA256: ${GUEST_SHA:-$SHA}"
			echo "XLIN-METRIC: mem_used_idle 12345 kB"
			echo "XLIN-SUITE: $s END"
		done
		echo "XLIN-RUNTIME: DONE"
	}
}

run() { # EXPECTED_EXIT NAME [runner args...]  (uses $FAKE_LOG)
	local want=$1 name=$2
	shift 2
	python3 -I "$ROOT/scripts/xlin-runtime-test" --kernel "$T/bzImage" --initramfs "$T/initramfs.cpio.zst" \
		--images "$T/images" --config "$T/config-final" --qemu "$T/qemu" --ovmf-code "$T/CODE.fd" --ovmf-vars "$T/VARS.fd" \
		--accel tcg --expect-release "$REL" --timeout 20 --out "$T/out" "$@" >"$T/last.txt" 2>&1
	local rc=$?
	if [ "$rc" = "$want" ]; then ok "$name (exit $rc)"; else bad "$name (exit $rc, wanted $want)"; sed 's/^/    | /' "$T/last.txt" | tail -n 15; fi
}

export FAKE_LOG="$T/log"
good_log config hardening systemd measure logscan >"$FAKE_LOG"
run 0 "a complete good guest log passes" --scenarios base

good_log config hardening systemd measure logscan | sed 's/^XLIN-TEST: hardening something PASS fine/XLIN-TEST: hardening kaslr FAIL text at link address/' >"$FAKE_LOG"
run 1 "a FAILED check fails the run" --scenarios base
if grep -q 'hardening.kaslr' "$T/last.txt"; then ok "the failing check is named in the output"; else bad "failing check not named"; fi

good_log config hardening systemd measure logscan | grep -v 'XLIN-RUNTIME: DONE' >"$FAKE_LOG"
run 1 "a missing DONE marker fails" --scenarios base

good_log config hardening systemd measure logscan | grep -v 'XLIN-SUITE: logscan END' >"$FAKE_LOG"
run 1 "a suite that never ended fails" --scenarios base

{ good_log config hardening systemd measure logscan; echo "Kernel panic - not syncing: boom"; } >"$FAKE_LOG"
run 1 "a kernel panic fails" --scenarios base

GUEST_SHA=$(printf 'a%.0s' $(seq 64)) good_log config hardening systemd measure logscan >"$FAKE_LOG"
run 1 "a guest config.gz that differs from the build .config fails" --scenarios base

good_log config hardening systemd measure logscan >"$FAKE_LOG"
FAKE_RC=1 run 1 "QEMU exiting with status 1 fails" --scenarios base

good_log config hardening systemd measure logscan | sed "s/Linux version $REL/Linux version 9.9.9-other/" >"$FAKE_LOG"
run 1 "the wrong kernel release fails" --scenarios base

good_log config hardening systemd measure logscan | sed 's/^XLIN-TEST: systemd something PASS fine$/XLIN-TEST: systemd something SKIP reason given/' >"$FAKE_LOG"
run 0 "an explained SKIP (not tested) is allowed and is not counted as a pass" --scenarios base

good_log config hardening systemd measure logscan | sed 's/^XLIN-TEST: logscan something PASS fine/XLIN-TEST: logscan finding INFO [    0.449975] CPA detected W^X violation/' >"$FAKE_LOG"
run 0 "an open finding does not fail the run" --scenarios base
if grep -A3 'Open findings' "$T/out/summary.md" | grep -q 'CPA detected'; then ok "the finding is listed in the summary"; else bad "finding missing from the summary"; fi

# NOT TESTED: option absent from the build config is reported and is not a failure
good_log config hardening systemd measure logscan >"$FAKE_LOG"
run 0 "a scenario whose kernel option is absent is NOT TESTED, not failed" --scenarios base,blk-nvme
if grep -q 'NOT TESTED blk-nvme' "$T/last.txt"; then ok "the NOT TESTED reason is printed"; else bad "no NOT TESTED line"; fi
run 3 "a run with nothing runnable is exit 3" --scenarios blk-nvme

# flake rate: the fake alternates good/bad by a counter file
echo 0 >"$T/n"
cat >"$T/qemu" <<Q
#!/bin/sh
n=\$(cat "$T/n"); echo \$((n + 1)) >"$T/n"
if [ \$((n % 2)) = 0 ]; then cat "$T/good"; else cat "$T/badlog"; fi
exit 0
Q
good_log config hardening systemd measure logscan >"$T/good"
good_log config hardening systemd measure logscan | grep -v DONE >"$T/badlog"
run 1 "alternating good/bad boots: the run fails" --scenarios base --repeat 4
if grep -q '| 2 | 50%' "$T/out/summary.md"; then ok "flake rate 50% is reported"; else bad "flake rate not reported"; grep base "$T/out/summary.md"; fi

# an image that could not be built is reported with its reason
run 3 "fs scenario without the modules image is NOT TESTED" --scenarios fs >/dev/null
echo
echo "Runtime-tool self-test: $pass passed, $fail failed (simulated guest only: NOT a boot test)"
[ "$fail" -eq 0 ]
