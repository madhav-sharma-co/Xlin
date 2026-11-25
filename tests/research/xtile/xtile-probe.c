/* SPDX-FileCopyrightText: 2026 Axion Co.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Research probe for the runtime finding XTILE-CPUID (NOT a gating test, not part of the kernel).
 * Prints raw CPUID leaves relevant to AMX/XSAVE, the permission and use of AMX tile state,
 * and (mode "kvm") what the running host kernel's KVM offers a VMM via KVM_GET_SUPPORTED_CPUID.
 *
 *   xtile-probe cpuid   raw CPUID leaves + decoded AMX bits + XGETBV
 *   xtile-probe amx     functional AMX test: permission request, tile config, zero, store, release
 *   xtile-probe kvm     KVM_GET_SUPPORTED_CPUID entries (needs /dev/kvm)
 *   xtile-probe all     cpuid + amx (+ kvm when /dev/kvm is usable)
 *
 * Every line starts with "XTILE: " so it can be grepped from a serial log.
 */
#define _GNU_SOURCE
#include <cpuid.h>
#include <errno.h>
#include <fcntl.h>
#include <immintrin.h>
#include <linux/kvm.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef ARCH_GET_XCOMP_SUPP
#define ARCH_GET_XCOMP_SUPP 0x1021
#define ARCH_GET_XCOMP_PERM 0x1022
#define ARCH_REQ_XCOMP_PERM 0x1023
#endif
#define XFEATURE_XTILE_DATA 18

static void leaf(uint32_t l, uint32_t s)
{
	uint32_t a, b, c, d;
	__cpuid_count(l, s, a, b, c, d);
	printf("XTILE: CPUID leaf=0x%x sub=%u eax=%08x ebx=%08x ecx=%08x edx=%08x\n", l, s, a, b, c, d);
}

static void do_cpuid(void)
{
	uint32_t a, b, c, d, maxb;
	char vendor[13];

	__cpuid(0, maxb, b, c, d);
	memcpy(vendor, &b, 4); memcpy(vendor + 4, &d, 4); memcpy(vendor + 8, &c, 4); vendor[12] = 0;
	printf("XTILE: vendor=%s max_basic_leaf=0x%x\n", vendor, maxb);
	leaf(0, 0); leaf(1, 0); leaf(7, 0); leaf(7, 1);
	leaf(0xd, 0); leaf(0xd, 1); leaf(0xd, 2); leaf(0xd, 17); leaf(0xd, 18);
	leaf(0x1d, 0); leaf(0x1d, 1); leaf(0x1e, 0);
	leaf(0x40000000, 0);
	/* decoded */
	__cpuid_count(1, 0, a, b, c, d);
	int xsave = (c >> 26) & 1, osxsave = (c >> 27) & 1, hyp = (c >> 31) & 1;
	printf("XTILE: decoded cpuid1 xsave=%d osxsave=%d hypervisor=%d family/model/stepping eax=%08x\n", xsave, osxsave, hyp, a);
	uint32_t e7 = 0, e71 = 0;
	if (maxb >= 7) {
		__cpuid_count(7, 0, a, b, c, d); e7 = d;
		__cpuid_count(7, 1, a, b, c, d); e71 = a;
	}
	printf("XTILE: decoded cpuid7 amx_bf16=%u amx_tile=%u amx_int8=%u amx_fp16(7.1.eax b21)=%u\n",
	       (e7 >> 22) & 1, (e7 >> 24) & 1, (e7 >> 25) & 1, (e71 >> 21) & 1);
	if (maxb >= 0xd) {
		uint32_t a0, b0, c0, d0;
		__cpuid_count(0xd, 0, a0, b0, c0, d0);
		printf("XTILE: decoded leaf0xd.0 supported_xcr0=%08x%08x tile_cfg(bit17)=%u tile_data(bit18)=%u xsave_size_enabled=%u xsave_size_max=%u\n",
		       d0, a0, (a0 >> 17) & 1, (a0 >> 18) & 1, b0, c0);
		__cpuid_count(0xd, 18, a, b, c, d);
		printf("XTILE: decoded leaf0xd.18 tile_data_size=%u offset=%u align64=%u xfd=%u\n", a, b, (c >> 1) & 1, (c >> 2) & 1);
	}
	if (maxb >= 0x1d) {
		uint32_t m, p1a, p1b, p1c;
		__cpuid_count(0x1d, 0, m, b, c, d);
		__cpuid_count(0x1d, 1, p1a, p1b, p1c, d);
		printf("XTILE: decoded leaf0x1d max_palette=%u palette1 total_tile_bytes=%u bytes_per_tile=%u bytes_per_row=%u max_names=%u max_rows=%u\n",
		       m, p1a & 0xffff, p1a >> 16, p1b & 0xffff, p1b >> 16, p1c & 0xffff);
		printf("XTILE: expected_by_kernel tile_state_bytes=%u (bytes_per_tile %u * max_names %u; the kernel's struct xtile_data is 1024 bytes)\n",
		       (p1a >> 16) * (p1b >> 16), p1a >> 16, p1b >> 16);
	} else {
		printf("XTILE: decoded leaf0x1d NOT REACHABLE max_basic_leaf=0x%x < 0x1d\n", maxb);
	}
	if (osxsave) {
		uint32_t lo, hi;
		__asm__ volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
		printf("XTILE: xgetbv xcr0=%08x%08x\n", hi, lo);
	}
}

static sigjmp_buf jb;
static volatile sig_atomic_t got;
static void on_sig(int s) { got = s; siglongjmp(jb, 1); }

struct tilecfg { uint8_t palette, start_row, rsvd[14]; uint16_t colsb[16]; uint8_t rows[16]; } __attribute__((packed, aligned(64)));

__attribute__((target("amx-tile"), noinline)) static void tile_use(unsigned char *out)
{
	struct tilecfg cfg;
	memset(&cfg, 0, sizeof(cfg));
	cfg.palette = 1; cfg.colsb[0] = 64; cfg.rows[0] = 16;
	_tile_loadconfig(&cfg);
	_tile_zero(0);
	_tile_stored(0, out, 64);
	_tile_release();
}

/* int8 tile matrix multiply: C(16x16 int32) = A(16x64 int8, all 1) x B(16x64 int8, all 1); every C element must be 64 */
__attribute__((target("amx-tile,amx-int8"), noinline)) static void tile_matmul(int32_t *c_out)
{
	static unsigned char a[1024] __attribute__((aligned(64))), b[1024] __attribute__((aligned(64)));
	struct tilecfg cfg;
	memset(a, 1, sizeof(a)); memset(b, 1, sizeof(b));
	memset(&cfg, 0, sizeof(cfg));
	cfg.palette = 1;
	for (int i = 0; i < 3; i++) { cfg.colsb[i] = 64; cfg.rows[i] = 16; }
	_tile_loadconfig(&cfg);
	_tile_zero(0);
	_tile_loadd(1, a, 64);
	_tile_loadd(2, b, 64);
	_tile_dpbssd(0, 1, 2);
	_tile_stored(0, c_out, 64);
	_tile_release();
}

static const char *try_matmul(int *ok)
{
	static int32_t c[256] __attribute__((aligned(64)));
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_sig;
	sigaction(SIGILL, &sa, NULL); sigaction(SIGSEGV, &sa, NULL);
	memset(c, 0xAA, sizeof(c));
	got = 0; *ok = 0;
	if (sigsetjmp(jb, 1) == 0) {
		tile_matmul(c);
		for (int i = 0; i < 256; i++) if (c[i] != 64) return "executed but a result element is not 64";
		*ok = 1;
		return "executed; TDPBSSD int8 16x16 result correct (all 256 elements = 64)";
	}
	return got == SIGILL ? "SIGILL" : "SIGSEGV";
}

static const char *try_tile(unsigned char *buf, int *ok)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_sig;
	sigaction(SIGILL, &sa, NULL); sigaction(SIGSEGV, &sa, NULL); sigaction(SIGFPE, &sa, NULL);
	memset(buf, 0xAA, 1024);
	got = 0; *ok = 0;
	if (sigsetjmp(jb, 1) == 0) {
		tile_use(buf);
		for (int i = 0; i < 1024; i++) if (buf[i] != 0) return "executed but tile store is not all zero";
		*ok = 1;
		return "executed; tilezero+tilestored gave 1024 zero bytes";
	}
	return got == SIGILL ? "SIGILL" : got == SIGSEGV ? "SIGSEGV" : "other signal";
}

static void do_amx(void)
{
	uint32_t a, b, c, d, maxb;
	unsigned char buf[1024] __attribute__((aligned(64)));
	unsigned long supp = 0, perm = 0;
	int ok;

	__cpuid(0, maxb, b, c, d);
	int has_tile = 0;
	if (maxb >= 7) { __cpuid_count(7, 0, a, b, c, d); has_tile = (d >> 24) & 1; }
	long r = syscall(SYS_arch_prctl, ARCH_GET_XCOMP_SUPP, &supp);
	printf("XTILE: arch_prctl(ARCH_GET_XCOMP_SUPP) ret=%ld errno=%d supported_mask=0x%lx tile_data_bit18=%lu\n", r, r ? errno : 0, supp, (supp >> 18) & 1);
	r = syscall(SYS_arch_prctl, ARCH_GET_XCOMP_PERM, &perm);
	printf("XTILE: arch_prctl(ARCH_GET_XCOMP_PERM) ret=%ld permitted_mask=0x%lx\n", r, perm);
	if (!has_tile) {
		printf("XTILE: amx test cpuid7.edx amx_tile=0: user space is told there is no AMX; tile instructions NOT attempted (they would be #UD by definition)\n");
		/* still ask the kernel what it would do, for the record */
		errno = 0;
		r = syscall(SYS_arch_prctl, ARCH_REQ_XCOMP_PERM, XFEATURE_XTILE_DATA);
		printf("XTILE: arch_prctl(ARCH_REQ_XCOMP_PERM, 18) with amx_tile=0 ret=%ld errno=%d\n", r, r ? errno : 0);
		return;
	}
	printf("XTILE: amx test before permission: %s\n", try_tile(buf, &ok));
	errno = 0;
	r = syscall(SYS_arch_prctl, ARCH_REQ_XCOMP_PERM, XFEATURE_XTILE_DATA);
	printf("XTILE: arch_prctl(ARCH_REQ_XCOMP_PERM, 18) ret=%ld errno=%d\n", r, r ? errno : 0);
	r = syscall(SYS_arch_prctl, ARCH_GET_XCOMP_PERM, &perm);
	printf("XTILE: arch_prctl(ARCH_GET_XCOMP_PERM) ret=%ld permitted_mask=0x%lx\n", r, perm);
	const char *res = try_tile(buf, &ok);
	printf("XTILE: amx test after permission: %s\n", res);
	int ok2 = 0;
	if (ok) printf("XTILE: amx matmul test: %s\n", try_matmul(&ok2));
	printf("XTILE: AMX_RESULT %s\n", ok && ok2 ? "WORKS" : "DOES-NOT-WORK");
}

static int do_kvm(void)
{
	int fd = open("/dev/kvm", O_RDWR);
	if (fd < 0) { printf("XTILE: kvm /dev/kvm not usable (errno=%d)\n", errno); return 1; }
	printf("XTILE: kvm api_version=%d\n", ioctl(fd, KVM_GET_API_VERSION, 0));
	struct { struct kvm_cpuid2 h; struct kvm_cpuid_entry2 e[256]; } *cp = calloc(1, sizeof(*cp));
	cp->h.nent = 256;
	if (ioctl(fd, KVM_GET_SUPPORTED_CPUID, cp) < 0) { printf("XTILE: kvm KVM_GET_SUPPORTED_CPUID failed errno=%d\n", errno); return 1; }
	printf("XTILE: kvm KVM_GET_SUPPORTED_CPUID entries=%u\n", cp->h.nent);
	for (unsigned i = 0; i < cp->h.nent; i++) {
		struct kvm_cpuid_entry2 *e = &cp->e[i];
		if (e->function == 7 || e->function == 0xd || e->function == 0x1d || e->function == 0x1e || e->function == 0)
			printf("XTILE: kvm supported function=0x%x index=%u flags=0x%x eax=%08x ebx=%08x ecx=%08x edx=%08x\n",
			       e->function, e->index, e->flags, e->eax, e->ebx, e->ecx, e->edx);
	}
	return 0;
}

int main(int argc, char **argv)
{
	const char *m = argc > 1 ? argv[1] : "all";
	setvbuf(stdout, NULL, _IOLBF, 0);
	if (!strcmp(m, "cpuid")) do_cpuid();
	else if (!strcmp(m, "amx")) do_amx();
	else if (!strcmp(m, "kvm")) return do_kvm();
	else if (!strcmp(m, "all")) { do_cpuid(); do_amx(); if (access("/dev/kvm", R_OK | W_OK) == 0) do_kvm(); }
	else { fprintf(stderr, "usage: xtile-probe cpuid|amx|kvm|all\n"); return 2; }
	return 0;
}
