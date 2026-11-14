// Litmus tests run on real hardware with two threads.
// Each iteration resets shared locations, releases both threads through a spin
// barrier, and records the registers. Shared accesses are C11 relaxed atomics,
// which compile to plain LDR/STR on AArch64, so the hardware decides ordering.
// Barrier and acquire/release variants use DMB ISH and LDAR/STLR.
// Build: cc -O2 -pthread litmus_hw.c -o litmus_hw ; Run: ./litmus_hw [iterations]
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__aarch64__)
#define FULL_FENCE() __asm__ volatile("dmb ish" ::: "memory")
#elif defined(__x86_64__)
#define FULL_FENCE() __asm__ volatile("mfence" ::: "memory")
#else
#define FULL_FENCE() atomic_thread_fence(memory_order_seq_cst)
#endif

typedef struct { _Alignas(128) atomic_int v; } line_t;
static line_t X, Y;
static int r0s, r1s;
static atomic_int go_count, round_no;

static void barrier(int *local_round) {
  int my = ++*local_round;
  if (atomic_fetch_add(&go_count, 1) == 1) {
    atomic_store(&go_count, 0);
    atomic_store(&round_no, my);
  } else {
    while (atomic_load_explicit(&round_no, memory_order_acquire) != my) {}
  }
}

enum { SB, SB_FENCE, MP, MP_FENCE, MP_RELACQ, LB, NTEST };
static const char *names[NTEST] = {"SB", "SB+dmb", "MP", "MP+dmb", "MP+stlr+ldar", "LB"};
static int test;
static long iters;
static long hist[NTEST][4];

#define ST(l, x) atomic_store_explicit(&(l).v, x, memory_order_relaxed)
#define LD(l)    atomic_load_explicit(&(l).v, memory_order_relaxed)

static void *t0(void *arg) {
  int lr = 0; (void)arg;
  for (long i = 0; i < iters; i++) {
    barrier(&lr);
    switch (test) {
      case SB:       ST(X, 1); r0s = LD(Y); break;
      case SB_FENCE: ST(X, 1); FULL_FENCE(); r0s = LD(Y); break;
      case MP:       ST(X, 1); ST(Y, 1); break;
      case MP_FENCE: ST(X, 1); FULL_FENCE(); ST(Y, 1); break;
      case MP_RELACQ:ST(X, 1); atomic_store_explicit(&Y.v, 1, memory_order_release); break;
      case LB:       r0s = LD(X); ST(Y, 1); break;
    }
    barrier(&lr);
    barrier(&lr); // thread 1 records, resets
  }
  return NULL;
}

static void *t1(void *arg) {
  int lr = 0; (void)arg;
  for (long i = 0; i < iters; i++) {
    barrier(&lr);
    switch (test) {
      case SB:       ST(Y, 1); r1s = LD(X); break;
      case SB_FENCE: ST(Y, 1); FULL_FENCE(); r1s = LD(X); break;
      case MP:       r0s = LD(Y); r1s = LD(X); break;
      case MP_FENCE: r0s = LD(Y); FULL_FENCE(); r1s = LD(X); break;
      case MP_RELACQ:r0s = atomic_load_explicit(&Y.v, memory_order_acquire); r1s = LD(X); break;
      case LB:       r1s = LD(Y); ST(X, 1); break;
    }
    barrier(&lr);
    hist[test][(r0s << 1) | r1s]++;
    ST(X, 0); ST(Y, 0); r0s = r1s = 0;
    barrier(&lr);
  }
  return NULL;
}

int main(int argc, char **argv) {
  iters = argc > 1 ? atol(argv[1]) : 2000000;
  printf("test           iterations   r0=0,r1=0   r0=0,r1=1   r0=1,r1=0   r0=1,r1=1   relaxed outcome\n");
  for (test = 0; test < NTEST; test++) {
    pthread_t a, b;
    atomic_store(&go_count, 0); atomic_store(&round_no, 0);
    pthread_create(&a, NULL, t0, NULL);
    pthread_create(&b, NULL, t1, NULL);
    pthread_join(a, NULL); pthread_join(b, NULL);
    // Outcome forbidden under SC: SB 0,0 ; MP r0=1,r1=0 ; LB 1,1
    int key = (test == SB || test == SB_FENCE) ? 0 : (test == LB ? 3 : 2);
    printf("%-14s %10ld %11ld %11ld %11ld %11ld   %ld\n", names[test], iters,
           hist[test][0], hist[test][1], hist[test][2], hist[test][3], hist[test][key]);
  }
  // Fenced and acquire/release variants must never show the relaxed outcome.
  int bad = hist[SB_FENCE][0] + hist[MP_FENCE][2] + hist[MP_RELACQ][2] != 0;
  if (bad) printf("FAIL: a fenced test showed its relaxed outcome\n");
  return bad;
}
