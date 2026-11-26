/* SPDX-FileCopyrightText: 2026 Axion Co.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Guest-side helper of the Xlin runtime validation: memory management, timer and CPU-affinity
 * checks that BusyBox cannot do. Static, no libraries. Output follows tests/runtime/lib.sh:
 *   XLIN-TEST: <suite> <name> PASS|FAIL|SKIP|INFO <detail>
 * usage: coretest mm | timer | affinity
 */
#define _GNU_SOURCE
#include <errno.h>
#include <setjmp.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static const char *suite;
static void rep(const char *name, const char *st, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
#include <stdarg.h>
static void rep(const char *name, const char *st, const char *fmt, ...)
{
	char d[256];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(d, sizeof d, fmt, ap);
	va_end(ap);
	printf("XLIN-TEST: %s %s %s %s\n", suite, name, st, d);
	fflush(stdout);
}
#define CHECK(name, cond, ...) do { if (cond) rep(name, "PASS", __VA_ARGS__); else rep(name, "FAIL", __VA_ARGS__); } while (0)

static sigjmp_buf jb;
static volatile sig_atomic_t got_segv;
static void on_segv(int s) { (void)s; got_segv = 1; siglongjmp(jb, 1); }

volatile sig_atomic_t alrm_count;
static void alrm_h(int s) { (void)s; alrm_count++; }

static long long ms_since(const struct timespec *a)
{
	struct timespec b;
	clock_gettime(CLOCK_MONOTONIC, &b);
	return (b.tv_sec - a->tv_sec) * 1000LL + (b.tv_nsec - a->tv_nsec) / 1000000;
}

static long meminfo_kb(const char *key)
{
	FILE *f = fopen("/proc/meminfo", "r");
	char l[128], fmt[64];
	long v = -1;
	snprintf(fmt, sizeof fmt, "%s: %%ld kB", key);
	while (f && fgets(l, sizeof l, f)) if (sscanf(l, fmt, &v) == 1) break;
	if (f) fclose(f);
	return v;
}

static int mm(void)
{
	/* direct accounting test first: the kernel's AnonPages counter must follow a 64 MiB mapping up
	 * (by at least 60 MiB) and back down (to within 4 MiB of where it was) */
	long a0 = meminfo_kb("AnonPages");
	size_t al = 64UL << 20;
	unsigned char *q = mmap(NULL, al, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (q != MAP_FAILED) for (size_t k = 0; k < al; k += 4096) q[k] = 1;
	long a1 = meminfo_kb("AnonPages");
	if (q != MAP_FAILED) munmap(q, al);
	long a2 = meminfo_kb("AnonPages");
	CHECK("anonpages-accounting", a0 >= 0 && a1 - a0 >= 60 * 1024 && a1 - a0 <= 72 * 1024 && a2 - a0 < 4 * 1024 && a2 - a0 > -4 * 1024,
	      "AnonPages %ld kB before, %ld kB with 64 MiB touched (+%ld), %ld kB after munmap (%+ld vs before)", a0, a1, a1 - a0, a2, a2 - a0);

	long pg = sysconf(_SC_PAGESIZE);
	size_t len = 64UL << 20;
	unsigned char *p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	CHECK("mmap-anon", p != MAP_FAILED, "64 MiB anonymous private mapping, page size %ld", pg);
	if (p == MAP_FAILED) return 0;
	size_t i, bad = 0;
	for (i = 0; i < len; i += pg) p[i] = (unsigned char)(i / pg * 7 + 1);
	for (i = 0; i < len; i += pg) if (p[i] != (unsigned char)(i / pg * 7 + 1)) bad++;
	CHECK("anon-readback", bad == 0, "%zu pages written then read back, %zu mismatches", len / pg, bad);

	/* fresh anonymous pages are zero */
	unsigned char *z = mmap(NULL, 8UL << 20, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
	for (i = 0, bad = 0; z != MAP_FAILED && i < (8UL << 20); i += 512) if (z[i]) bad++;
	CHECK("anon-zero-filled", z != MAP_FAILED && bad == 0, "populated 8 MiB read as zero (%zu non-zero samples)", bad);

	/* madvise(DONTNEED) returns zero pages */
	int r = madvise(p, len, MADV_DONTNEED);
	for (i = 0, bad = 0; i < len; i += pg) if (p[i]) bad++;
	CHECK("madvise-dontneed", r == 0 && bad == 0, "after MADV_DONTNEED %zu of %zu pages were not zero", bad, len / pg);

	/* PROT_NONE faults, PROT_READ blocks writes */
	struct sigaction sa;
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_segv;
	sa.sa_flags = SA_NODEFER;
	sigaction(SIGSEGV, &sa, NULL);
	p[0] = 1;
	mprotect(p, pg, PROT_NONE);
	got_segv = 0;
	if (!sigsetjmp(jb, 1)) { volatile unsigned char c = p[0]; (void)c; }
	CHECK("prot-none-faults", got_segv == 1, "read of a PROT_NONE page raised SIGSEGV");
	mprotect(p, pg, PROT_READ);
	got_segv = 0;
	if (!sigsetjmp(jb, 1)) p[0] = 2;
	CHECK("prot-read-blocks-write", got_segv == 1, "write to a PROT_READ page raised SIGSEGV");
	mprotect(p, pg, PROT_READ | PROT_WRITE);
	signal(SIGSEGV, SIG_DFL);

	/* NULL page is not mappable without privilege rules: mmap_min_addr */
	void *n = mmap((void *)0, pg, PROT_READ, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
	if (n == MAP_FAILED) rep("mmap-min-addr", "PASS", "a fixed mapping at address 0 was refused (errno %d)", errno);
	else { rep("mmap-min-addr", "INFO", "mapping at address 0 allowed (running as root with mmap_min_addr 0?)"); munmap(n, pg); }

	/* mremap grows a mapping and keeps its contents */
	unsigned char *m = mmap(NULL, pg * 4, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	memset(m, 0xA5, pg * 4);
	unsigned char *m2 = mremap(m, pg * 4, pg * 64, MREMAP_MAYMOVE);
	CHECK("mremap-grow", m2 != MAP_FAILED && m2[0] == 0xA5 && m2[pg * 4 - 1] == 0xA5, "4 -> 64 pages, old contents kept");

	/* fork copy-on-write isolation */
	memset(p, 0x11, pg * 16);
	pid_t c = fork();
	if (c == 0) { memset(p, 0x22, pg * 16); _exit(p[0] == 0x22 ? 0 : 1); }
	int st = 0;
	waitpid(c, &st, 0);
	CHECK("fork-cow", WIFEXITED(st) && WEXITSTATUS(st) == 0 && p[0] == 0x11 && p[pg * 16 - 1] == 0x11,
	      "child wrote its copy, parent still sees the original");

	/* shared anonymous mapping is shared across fork */
	unsigned char *s = mmap(NULL, pg, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	s[0] = 1;
	c = fork();
	if (c == 0) { s[0] = 9; _exit(0); }
	waitpid(c, &st, 0);
	CHECK("shared-mapping", s[0] == 9, "child's write to MAP_SHARED is seen by the parent");

	/* mlock */
	r = mlock(p, pg * 16);
	if (r == 0) { rep("mlock", "PASS", "16 pages locked"); munlock(p, pg * 16); }
	else rep("mlock", "SKIP", "mlock failed errno %d (RLIMIT_MEMLOCK)", errno);

	/* brk/sbrk */
	void *b0 = sbrk(0), *b1 = sbrk(pg * 32);
	CHECK("brk-grow", b1 == b0 && sbrk(0) == (char *)b0 + pg * 32, "heap grew by 32 pages");
	sbrk(-(long)(pg * 32));

	/* transparent huge pages are reported, not required */
	FILE *f = fopen("/sys/kernel/mm/transparent_hugepage/enabled", "r");
	char line[128] = "";
	if (f) { if (!fgets(line, sizeof line, f)) line[0] = 0; fclose(f); line[strcspn(line, "\n")] = 0; rep("thp", "INFO", "transparent_hugepage/enabled: %s", line); }
	else rep("thp", "SKIP", "no /sys/kernel/mm/transparent_hugepage (CONFIG_TRANSPARENT_HUGEPAGE not set)");

	/* munmap releases memory: MemAvailable must recover */
	munmap(p, len);
	rep("munmap", "PASS", "64 MiB mapping released");
	return 0;
}

static int timer(void)
{
	struct timespec res, a, b, t0;
	clock_getres(CLOCK_MONOTONIC, &res);
	CHECK("clock-resolution", res.tv_sec == 0 && res.tv_nsec <= 1000000, "CLOCK_MONOTONIC resolution %ld ns (<= 1 ms)", res.tv_nsec);

	/* monotonic never goes back over many calls */
	long long bad = 0;
	clock_gettime(CLOCK_MONOTONIC, &a);
	for (int i = 0; i < 2000000; i++) {
		clock_gettime(CLOCK_MONOTONIC, &b);
		if (b.tv_sec < a.tv_sec || (b.tv_sec == a.tv_sec && b.tv_nsec < a.tv_nsec)) bad++;
		a = b;
	}
	CHECK("monotonic", bad == 0, "2,000,000 reads, %lld went backwards", bad);

	/* sleeps never return early and are not wildly late */
	int early = 0, late = 0;
	long long worst = 0;
	for (int i = 0; i < 10; i++) {
		clock_gettime(CLOCK_MONOTONIC, &t0);
		struct timespec rq = {0, 50 * 1000000L};
		nanosleep(&rq, NULL);
		long long e = ms_since(&t0);
		if (e < 50) early++;
		if (e > 50 + 250) late++;
		if (e > worst) worst = e;
	}
	CHECK("nanosleep-50ms", early == 0 && late == 0, "10 sleeps of 50 ms: %d early, %d later than +250 ms, longest %lld ms", early, late, worst);

	/* periodic timerfd: 20 ticks of 10 ms take about 200 ms */
	int tf = timerfd_create(CLOCK_MONOTONIC, 0);
	struct itimerspec its = {{0, 10 * 1000000L}, {0, 10 * 1000000L}};
	timerfd_settime(tf, 0, &its, NULL);
	unsigned long long total = 0, x;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	while (total < 20) { if (read(tf, &x, sizeof x) != sizeof x) break; total += x; }
	long long el = ms_since(&t0);
	CHECK("timerfd-periodic", total >= 20 && el >= 190 && el < 190 + 400, "20 expirations of a 10 ms timer in %lld ms", el);
	close(tf);

	/* interval timer signal */
	struct sigaction sa;
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = alrm_h;
	sigaction(SIGALRM, &sa, NULL);
	struct itimerval iv = {{0, 20000}, {0, 20000}};
	setitimer(ITIMER_REAL, &iv, NULL);
	clock_gettime(CLOCK_MONOTONIC, &t0);
	while (alrm_count < 10 && ms_since(&t0) < 2000) pause();
	struct itimerval off = {{0, 0}, {0, 0}};
	setitimer(ITIMER_REAL, &off, NULL);
	CHECK("setitimer-sigalrm", alrm_count >= 10, "%d SIGALRM in %lld ms from a 20 ms interval timer", (int)alrm_count, ms_since(&t0));

	/* wall clock vs monotonic advance together */
	struct timespec r1, r2, m1, m2;
	clock_gettime(CLOCK_REALTIME, &r1); clock_gettime(CLOCK_MONOTONIC, &m1);
	usleep(200000);
	clock_gettime(CLOCK_REALTIME, &r2); clock_gettime(CLOCK_MONOTONIC, &m2);
	long long dr = (r2.tv_sec - r1.tv_sec) * 1000 + (r2.tv_nsec - r1.tv_nsec) / 1000000;
	long long dm = (m2.tv_sec - m1.tv_sec) * 1000 + (m2.tv_nsec - m1.tv_nsec) / 1000000;
	CHECK("realtime-vs-monotonic", dr - dm > -20 && dr - dm < 20, "over 200 ms REALTIME advanced %lld ms, MONOTONIC %lld ms", dr, dm);
	return 0;
}
static int affinity(void)
{
	int ncpu = (int)sysconf(_SC_NPROCESSORS_ONLN), ok = 0, bad = 0;
	for (int c = 0; c < ncpu; c++) {
		cpu_set_t s;
		CPU_ZERO(&s);
		CPU_SET(c, &s);
		if (sched_setaffinity(0, sizeof s, &s) != 0) { bad++; continue; }
		sched_yield();
		volatile unsigned long sink = 0;
		for (unsigned long i = 0; i < 20000000UL; i++) sink += i;
		if (sched_getcpu() == c) ok++; else bad++;
	}
	CHECK("pin-each-cpu", bad == 0 && ok == ncpu, "a process pinned to each of %d online CPUs ran on it (%d ok, %d not)", ncpu, ok, bad);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 2) return 2;
	suite = argv[1];
	setvbuf(stdout, NULL, _IOLBF, 0);
	if (!strcmp(argv[1], "mm")) return mm();
	if (!strcmp(argv[1], "timer")) return timer();
	if (!strcmp(argv[1], "affinity")) { suite = "smp"; return affinity(); }
	return 2;
}
