/* SPDX-FileCopyrightText: 2026 Axion Co.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Basic kernel micro-benchmarks for the Xlin performance baseline. Static, no libraries.
 * Output: "XLIN-BENCH: <name> <value> <unit>". Single-threaded, one CPU's worth of work per test;
 * numbers are only comparable between kernels run in the same VM configuration on the same host.
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1e9 + t.tv_nsec;
}
static void out(const char *n, double v, const char *u) { printf("XLIN-BENCH: %s %.2f %s\n", n, v, u); fflush(stdout); }
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y); }

int main(void)
{
	cpu_set_t s;
	CPU_ZERO(&s); CPU_SET(0, &s);
	sched_setaffinity(0, sizeof s, &s);   /* keep pipes' two processes on one CPU: measures the kernel path, not IPIs */

	double t0 = now();
	for (int i = 0; i < 2000000; i++) syscall(SYS_getppid);
	out("syscall-getppid", (now() - t0) / 2000000, "ns/call");

	int a[2], b[2];
	if (pipe(a) || pipe(b)) return 1;
	pid_t c = fork();
	char x = 'x';
	if (c == 0) { for (;;) { if (read(a[0], &x, 1) != 1) _exit(0); if (write(b[1], &x, 1) != 1) _exit(1); } }
	t0 = now();
	for (int i = 0; i < 200000; i++) { if (write(a[1], &x, 1) != 1 || read(b[0], &x, 1) != 1) return 1; }
	out("pipe-pingpong-roundtrip", (now() - t0) / 200000, "ns");
	kill(c, SIGKILL); waitpid(c, NULL, 0);

	t0 = now();
	for (int i = 0; i < 2000; i++) { pid_t p = fork(); if (p == 0) _exit(0); waitpid(p, NULL, 0); }
	out("fork-exit-wait", (now() - t0) / 2000 / 1000, "us");

	size_t len = 64UL << 20, pg = 4096;
	t0 = now();
	char *m = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	for (size_t i = 0; i < len; i += pg) m[i] = 1;
	double t1 = now();
	munmap(m, len);
	out("page-fault", (t1 - t0) / (len / pg), "ns/page");
	out("munmap-64MiB", (now() - t1) / 1000, "us");

	size_t n = 32UL << 20;
	char *s1 = malloc(n), *s2 = malloc(n);
	memset(s1, 1, n); memset(s2, 2, n);
	t0 = now();
	for (int i = 0; i < 20; i++) memcpy(s2, s1, n);
	out("memcpy", (double)n * 20 / ((now() - t0) / 1e9) / 1e9, "GB/s");

	int fd = open("/tmp/xlin-bench.dat", O_CREAT | O_RDWR | O_TRUNC, 0600);
	if (fd >= 0) {
		static char buf[1 << 16];
		memset(buf, 7, sizeof buf);
		t0 = now();
		for (int i = 0; i < 1024; i++) if (write(fd, buf, sizeof buf) < 0) break;
		out("tmpfs-write-64MiB", 64.0 / ((now() - t0) / 1e9), "MiB/s");
		lseek(fd, 0, SEEK_SET);
		t0 = now();
		for (int i = 0; i < 1024; i++) if (read(fd, buf, sizeof buf) < 0) break;
		out("tmpfs-read-64MiB", 64.0 / ((now() - t0) / 1e9), "MiB/s");
		close(fd); unlink("/tmp/xlin-bench.dat");
	}

	enum { N = 2000 };
	static double d[N];
	for (int i = 0; i < N; i++) {
		struct timespec rq = {0, 1000000}, a1, a2;
		clock_gettime(CLOCK_MONOTONIC, &a1);
		nanosleep(&rq, NULL);
		clock_gettime(CLOCK_MONOTONIC, &a2);
		d[i] = (a2.tv_sec - a1.tv_sec) * 1e9 + (a2.tv_nsec - a1.tv_nsec) - 1e6;
	}
	qsort(d, N, sizeof d[0], cmpd);
	out("timer-lateness-1ms-median", d[N / 2] / 1000, "us");
	out("timer-lateness-1ms-p99", d[N * 99 / 100] / 1000, "us");
	out("timer-lateness-1ms-max", d[N - 1] / 1000, "us");
	printf("XLIN-BENCH-DONE\n");
	return 0;
}
