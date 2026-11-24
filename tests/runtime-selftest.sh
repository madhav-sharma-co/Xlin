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

good_log config hardening systemd measure logscan | sed 's/^XLIN-TEST: logscan something PASS fine/&\nXLIN-TEST: logscan finding-W-X-CPA-ITS FINDING [EXPLAINED-OPEN] [    0.449975] CPA detected W^X violation/' >"$FAKE_LOG"
run 0 "an open finding does not fail the run by itself" --scenarios base
if grep -q 'RESULT: PASS WITH OPEN FINDINGS' "$T/last.txt" && ! grep -q '^RESULT: PASS (' "$T/last.txt"; then ok "the run is reported as PASS WITH OPEN FINDINGS, not as a clean PASS"; else bad "finding run reported as clean"; fi
if grep -q 'Verdict: PASS WITH OPEN FINDINGS' "$T/out/summary.md" && grep -q 'NOT a clean pass' "$T/out/summary.md"; then ok "the summary verdict says it is not a clean pass"; else bad "summary verdict does not flag the finding"; fi
if grep -A4 'Open findings' "$T/out/summary.md" | grep -q 'W-X-CPA-ITS.*EXPLAINED-OPEN.*1 of 1 boots whose kernel log was scanned'; then ok "the finding is listed in the summary with its status and boot count"; else bad "finding missing from the summary"; fi
run 4 "--strict-findings turns an open finding into a non-zero exit" --scenarios base --strict-findings

good_log config hardening systemd measure logscan | sed 's/^XLIN-TEST: hardening something PASS fine/XLIN-TEST: hardening kaslr SKIP COLLISION _text=ffffffff81000000 equals the link-time address/' >"$FAKE_LOG"
run 0 "one boot whose _text collides with the link address is not a failure (chance, 1 in ~512)" --scenarios base
run 1 "every boot of a 3-boot run colliding IS a failure (KASLR not moving the kernel)" --scenarios base --repeat 3
if grep -q 'KASLR did not move the kernel in any of 3 boots' "$T/last.txt"; then ok "the all-boots KASLR failure is named"; else bad "all-boots KASLR failure not named"; fi

good_log config hardening systemd measure logscan >"$FAKE_LOG"
run 0 "a good log without a finding is a clean PASS" --scenarios base
if grep -q '^RESULT: PASS (' "$T/last.txt" && grep -q 'Verdict: PASS - ' "$T/out/summary.md"; then ok "the clean verdict is used only when no finding was observed"; else bad "clean verdict wrong"; fi

# ---- the guest-side log scanner itself (tests/runtime/suites/logscan.sh), run on the host ------
S=$T/scan
mkdir -p "$S/tests" "$S/tmp" "$S/bin"
cp "$ROOT"/tests/runtime/lib.sh "$ROOT"/tests/runtime/dmesg-allowlist.txt "$ROOT"/tests/runtime/known-findings.txt "$S/tests/"
echo 0 >"$S/taint"
cat >"$S/bin/dmesg" <<'D'
#!/bin/sh
cat "$SCAN_LOG"
D
chmod +x "$S/bin/dmesg"
scan() { # prints the scanner's XLIN-TEST lines for the log in $SCAN_LOG
	SCAN_LOG="$S/log" PATH="$S/bin:$PATH" XLIN_TESTS="$S/tests" XLIN_TMP="$S/tmp" XLIN_TAINT_FILE="$S/taint" \
		sh "$ROOT/tests/runtime/suites/logscan.sh" 2>&1
}
scan_expect() { # NAME PATTERN (must match)   /  scan_refuse NAME PATTERN (must not match)
	local out
	out=$(scan)
	if grep -qE -e "$2" <<<"$out"; then ok "scanner: $1"; else bad "scanner: $1"; printf '%s\n' "$out" | sed 's/^/    | /'; fi
}
scan_refuse() {
	local out
	out=$(scan)
	if grep -qE -e "$2" <<<"$out"; then bad "scanner: $1"; printf '%s\n' "$out" | sed 's/^/    | /'; else ok "scanner: $1"; fi
}
printf '<6>[    0.1] Linux version x\n<6>[    0.2] all quiet\n' >"$S/log"
scan_expect "a quiet log passes" 'logscan kernel-log-no-unexpected PASS'
scan_expect "an absent known finding is stated as not observed" 'logscan finding-W-X-CPA-ITS INFO not observed'
scan_refuse "an absent known finding is not reported as a FINDING" ' FINDING '
printf '<6>[    0.1] x\n<4>[    0.2] totally new warning: something broke\n' >"$S/log"
scan_expect "an unknown warning FAILS" 'logscan unexpected FAIL'
scan_refuse "an unknown warning never gets the clean pass" 'kernel-log-no-unexpected PASS'
printf '<6>[    0.1] x\n<6>[    0.2] a harmless line with the word error in it\n' >"$S/log"
scan_expect "an unknown line that merely mentions 'error' FAILS (words are scanned)" 'logscan unexpected FAIL'
printf '<4>[    0.2] x86/split lock detection: #DB: warning on user-space bus_locks\n' >"$S/log"
scan_expect "an allowlisted notice is INFO allowed" 'logscan allowed INFO'
scan_expect "an allowlisted notice does not fail the scan" 'kernel-log-no-unexpected PASS'
scan_refuse "an allowlisted notice is not a finding" ' FINDING '
printf '<4>[    0.2] CPA detected W^X violation: 8000000000000123 -> 0000000000000123 range: 0xffffffffc0400000 - 0xffffffffc0400fff PFN 2000\n' >"$S/log"
scan_expect "the W^X line is a FINDING with its ID and status" 'logscan finding-W-X-CPA-ITS FINDING \[EXPLAINED-OPEN\]'
scan_refuse "the W^X line is not allowlisted" 'logscan allowed'
scan_refuse "the W^X line is not an unexpected failure" 'logscan unexpected FAIL'
printf '<3>[    0.2] XFEATURE_XTILE_DATA: calculated size is 0 bytes, cpu state 8192 bytes\n<3>[    0.3] CPUID[0d, 00]: eax=000600e7 ebx=00002b00 ecx=00002b00 edx=00000000\n<3>[    0.4] CPUID[0d, 01]: eax=0000001f ebx=000029c0 ecx=00000000 edx=00000000\n' >"$S/log"
scan_expect "a multi-line kernel dump of a known finding is ONE FINDING with its line count" 'logscan finding-XTILE-CPUID FINDING \[EXPLAINED-OPEN\] 3 line\(s\)'
scan_refuse "that dump is not reported as unexpected" 'logscan unexpected'
printf '<3>[    0.2] XFEATURE_XTILE_DATA: struct is 8192 bytes, cpu xtile 1024 bytes\n' >"$S/log"
scan_expect "a different XTILE error is NOT covered by the finding and FAILS" 'logscan unexpected FAIL'
printf '<4>[    0.2] CPA detected W^X violation: 1 -> 2 range: 0x1 - 0x2 PFN 1\n<4>[    0.3] brand new warning: boom\n' >"$S/log"
scan_expect "a known finding does not hide an unexpected warning next to it" 'logscan unexpected FAIL'
scan_expect "... and the finding is still reported" 'logscan finding-W-X-CPA-ITS FINDING'
printf '<4>[    0.2] tsc: Fast TSC calibration failed\n' >"$S/log"
scan_expect "a TCG-scoped notice is UNEXPECTED on a KVM guest" 'logscan unexpected FAIL'
printf '<6>[    0.0] smpboot: CPU0: AMD QEMU TCG CPU version 2.5+\n<4>[    0.2] tsc: Fast TSC calibration failed\n' >"$S/log"
scan_expect "the same notice is INFO allowed on a TCG guest" 'logscan allowed INFO'
echo 4096 >"$S/taint"
printf '<6>[    0.1] x\n' >"$S/log"
scan_expect "a tainted kernel fails" 'not-tainted FAIL'
echo 0 >"$S/taint"

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
if grep -q '| 2 | 0 | 50%' "$T/out/summary.md"; then ok "flake rate 50% is reported"; else bad "flake rate not reported"; grep base "$T/out/summary.md"; fi

# an image that could not be built is reported with its reason
run 3 "fs scenario without the modules image is NOT TESTED" --scenarios fs >/dev/null
echo
echo "Runtime-tool self-test: $pass passed, $fail failed (simulated guest only: NOT a boot test)"
[ "$fail" -eq 0 ]
