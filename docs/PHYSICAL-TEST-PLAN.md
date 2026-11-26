<!--
SPDX-FileCopyrightText: 2026 Axion Co.
SPDX-License-Identifier: CC-BY-4.0
-->

# Xlin first physical-machine test plan

Non-destructive: boot from a removable USB stick or a separate partition only; never modify the machine's existing OS or firmware settings except the one-time boot selection. Record the model, CPU, firmware version and every deviation.

## Preparation (done from CI/QEMU, no laptop needed)
Release candidate artifacts with SHA256SUMS; an EFI-stub boot image (`bzImage` + initramfs) written to a USB stick by the runtime-test image builder; the QEMU baseline logs for comparison.

## Checks
| ID | Check | Pass criterion |
|---|---|---|
| P1 | Boots from firmware to user space | reaches the test init, no panic |
| P2 | `dmesg` capture saved to the stick | file saved; scanned with the same scanner as CI |
| P3 | Config identity | `/proc/config.gz` hash equals the release `.config` |
| P4 | CPU | online CPUs equal firmware count; `smp` suite passes |
| P5 | CPUID/AMX | host CPUID leaf 0x7/0x1d recorded; XTILE message present or absent recorded verbatim; `xtile-probe` output kept |
| P6 | Storage | internal NVMe/SATA enumerated, read-only checksum of a known file |
| P7 | Input and display | keyboard works; framebuffer console visible |
| P8 | Wired network | link, DHCP, ping the gateway (if a wired port exists) |
| P9 | Timers/clocks | `timer` suite passes; clocksource recorded |
| P10 | Reboot and poweroff | clean warm reboot x3 and ACPI poweroff |
| P11 | Warning review | every kernel warning compared with QEMU findings; new ones logged, not allowlisted |
| P12 | Soak | 24 h idle plus stress, no BUG/Oops/lockup |

Out of scope for the first test: Wi-Fi, Bluetooth, sound, suspend/resume, GPU acceleration (not yet configured or not yet specified).

## Output
A folder of raw logs and a results table with PASS/FAIL/NOT TESTED per ID. No result is generalised beyond the one machine tested.
