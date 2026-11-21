<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin Kernel boot test (QEMU + OVMF)

The first runtime test of the Xlin Kernel: the kernel built by CI ([BUILD.md](BUILD.md)) is booted in a virtual x86_64 machine with UEFI firmware, runs a minimal initramfs, and reaches an interactive shell on the serial console.

## What this test is, and is not

- It **is** a test that the Xlin Kernel `6.18.64-xlin`, built from the pinned source with the approved configuration, boots under UEFI in QEMU, unpacks an initramfs, runs `/init` and reaches a shell.
- It is **not** a test of Xlin Boot (there is no bootloader: QEMU's `-kernel` option hands the kernel to OVMF, which starts it through the kernel's EFI stub).
- It is **not** a test of physical hardware, of an installed system, of XlinOS (not used at all), of graphics, networking, storage, suspend, or of performance. **QEMU success is not a claim of hardware compatibility or production readiness.**

## Result

| | |
|---|---|
| Boot result | **PASS**, in two independent CI runs |
| Evidence | GitHub Actions runs [44898422683](https://github.com/madhav-sharma-co/Xlin/actions/runs/44898422683) and [44900135792](https://github.com/madhav-sharma-co/Xlin/actions/runs/44900135792) ("Kernel build", job "boot-test"); each run builds the kernel afresh, so the two `bzImage` files differ in hash (`3a3ceed7…` and `784867c5…`) |
| Kernel | Linux 6.18.64, release `6.18.64-xlin`, commit `fd7cfd39c88596fec816639ad83cbf3e9d316372`; `bzImage` 12,174,336 bytes |
| Firmware | OVMF from Ubuntu package `ovmf 2024.02-2ubuntu0.10` (`OVMF_CODE_4M.fd`); the guest log says `efi: EFI v2.7 by Ubuntu distribution of EDK II`, `Secure boot disabled` |
| QEMU | 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18) |
| VM | q35 machine, KVM acceleration, 2 vCPUs (host CPU Intel Xeon 6975P-C), 1024 MiB RAM (guest MemTotal 964 MiB) |
| `/init` executed | Yes (`Run /init as init process`, then its banner, PID 1) |
| Serial shell reached | Yes: BusyBox `ash` answered a command the harness made up at random (`$((380*501))` -> `190380`) |
| Success signal and exit | `XLIN-BOOT-TEST-RESULT: PASS`, guest powered off, **QEMU exit status 0** |
| Duration | 3.5 s from QEMU start to exit, in both runs (first kernel message at 1.7 s, `/init` at 3.3-3.4 s; the kernel's own clock says `/init` started at about 1.55 s). This includes firmware start-up and is the time for a minimal initramfs under KVM, **not a boot-speed benchmark** |
| Negative tests | 3 of 3 real boots that must fail did fail correctly; 36 of 36 harness self-tests passed |

### The shell session, as logged

    XLIN-BOOT-TEST: BEGIN Xlin Kernel boot test: /init is running as PID 1
    XLIN-BOOT-TEST: kernel-release=6.18.64-xlin expected=6.18.64-xlin
    XLIN-BOOT-TEST: cpu-model=Intel(R) Xeon(R) 6975P-C
    XLIN-BOOT-TEST: cpu-count=2
    XLIN-BOOT-TEST: mem-total-kb=987952
    XLIN-BOOT-TEST: check-ok booted-via-uefi
    XLIN-BOOT-TEST: SHELL-READY failed=0
    xlin-test# echo XLIN-SHELL-PROOF $((380*501))
    XLIN-SHELL-PROOF 190380
    xlin-test# xlin-pass
    XLIN-BOOT-TEST-RESULT: PASS (all /init checks passed)
    [    1.669478] reboot: Power down

The complete serial log is printed in the CI job log (group "serial.log") and uploaded as the `xlin-boot-test` artifact together with `report.md`, `result.env`, `qemu-command.txt` and the initramfs manifest (kept 14 days).

### Warnings seen in the kernel log

The harness lists the kernel log lines that mention warning, failed or error: three lines, none of which stopped the boot and none of which was investigated further:

- `x86/split lock detection: #DB: warning on user-space bus_locks`: an informational message about CPU split-lock handling.
- `faux_driver regulatory: Direct firmware load for regulatory.db failed with error -2` and `cfg80211: failed to load regulatory.db`: the kernel contains the Wi-Fi regulatory layer and looked for a firmware file the test initramfs does not have. Expected here; Wi-Fi is not configured or tested.

A manual read of the log also shows the usual q35 hint `PCI: Using host bridge windows from ACPI; if necessary, use "pci=nocrs" and report a bug`, which is not an error.

## How it works

1. `scripts/xlin-initramfs` builds the initramfs: `/init` (`tests/boot/init`), `/bin/xlin-pass`, one static BusyBox (Ubuntu `busybox-static` in CI) with its applet symlinks, `/dev/console` and `/dev/null` nodes and the empty mount points. It uses the kernel's own `usr/gen_init_cpio.c` from the pinned source, so no root privileges and no `cpio` program are needed, and the archive is byte-identical between builds (fixed timestamps). It is independent of XlinOS and is never committed.
2. `scripts/xlin-boot-test` starts QEMU: `q35`, OVMF as read-only code plus a **private copy** of the variable store (nothing on the host is modified), `-kernel`/`-initrd`/`-append`, serial on stdio, no display, no network, `-no-reboot`. Command line: `console=ttyS0,115200 loglevel=7 panic=-1 rdinit=/init xlin.expect_release=<release>`. The exact command is saved as `qemu-command.txt`.
3. `/init` mounts `/proc`, `/sys`, `/dev`, prints the identification banner, CPU and memory information, runs its own checks (including that `/sys/firmware/efi` exists, i.e. the guest really booted via UEFI) and starts a shell on the serial console.
4. The harness sends a command with random numbers to that shell, then the controlled success signal `xlin-pass`, which prints the marker and powers the VM off.

## Pass criteria

All of these must hold; a QEMU process that merely starts is not a pass.

| Criterion | Where it is shown |
|---|---|
| QEMU started and kept running | process state |
| Kernel started with the expected release | `Linux version 6.18.64-xlin` in the log |
| Booted through UEFI | `efi: EFI v...` in the kernel log and `/sys/firmware/efi` in the guest |
| No panic, oops or BUG | absence of those messages |
| Memory and CPUs initialised | `Memory: .../... available` and `smp: Brought up ... CPUs` |
| Initramfs unpacked | `Unpacking initramfs...`, no unpack error |
| `/init` executed, its checks passed | `Run /init as init process`, banner, `SHELL-READY failed=0` |
| Interactive shell on the serial console | the shell computed the random product |
| Explicit success marker | `XLIN-BOOT-TEST-RESULT: PASS` |
| Clean exit status | QEMU exited by itself with status 0 |
| Time limit | default 300 s overall, 30 s to power off after the marker |

## Failures

On failure the harness keeps the complete serial log, prints the earliest meaningful error with its line number, and classifies the failure: **firmware** (no kernel output at all), **kernel** (failed before `/init`), **initramfs** (`/init` missing or died, unpack error), **test-harness** (QEMU could not start, wrong kernel under test) or **timeout** (nothing failed, nothing finished). The criteria are not weakened to make a boot pass, and the approved kernel configuration is not changed by this test.

## Running it

    sudo apt-get install qemu-system-x86 ovmf busybox-static zstd
    scripts/xlin-fetch && scripts/xlin-verify --strict      # the pinned source (gen_init_cpio)
    scripts/xlin-build                                      # or use the bzImage of a CI build
    scripts/xlin-initramfs
    scripts/xlin-boot-test                                  # logs in build/boot-test/run/

Exit status: 0 pass, 1 boot test failed, 3 cannot run (missing input or tool). The harness uses KVM when `/dev/kvm` is usable and software emulation (TCG) otherwise; **the TCG path has not been run in CI**.

## Tests of the test tools

- `tests/boot-selftest.sh` (no QEMU, **not a boot**): runs the harness against a simulated guest to prove it passes only when everything is shown and that it rejects and classifies a panic, a dying `/init`, a wrong release, a silent firmware, a hang, a shell that does not answer, a failed `/init` check, a non-UEFI boot, a QEMU that does not exit, a QEMU that fails to start and a timeout. It also checks invalid inputs and missing dependencies (missing kernel, kernel without an EFI header, missing or empty initramfs, missing QEMU or OVMF, invalid limits) and the initramfs structure, determinism and input validation. This self-test found a real bug in the harness's failure classification while it was being written.
- `tests/boot-negative.sh` (real boots, CI): a `/init` that exits, a wrong expected release and a 1 second limit must all be reported as failures.

## Not done

Booting with Xlin Boot or on physical hardware; an installed or persistent system; networking, storage, graphics and input tests; Secure Boot (the log says it is disabled); the software-emulation path; any comparison with other kernels or boot-time benchmark; integration with XlinOS.
