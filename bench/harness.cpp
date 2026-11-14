// Verilator harness: host memory model, the C driver, a benchmark sweep and
// an optional VCD capture (the simulated logic analyser).
#include "Vdma_engine.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <vector>
#include <string>
#include "../driver/dma_drv.h"

struct Sim {
  Vdma_engine *m;
  VerilatedVcdC *vcd = nullptr;
  uint64_t t = 0, cycles = 0;
  std::vector<uint8_t> mem;
  int latency;
  struct Rsp { uint64_t due, data; };
  std::deque<Rsp> rsp;

  Sim(int lat, size_t bytes) : mem(bytes, 0), latency(lat) {
    m = new Vdma_engine;
    m->rst_n = 0; m->clk = 0; m->reg_valid = 0; m->mem_req_ready = 1; m->mem_rsp_valid = 0;
    m->eval();
    tick(); tick();
    m->rst_n = 1;
    tick();
  }
  ~Sim() { if (vcd) vcd->close(); delete m; }

  uint64_t rd64(uint64_t a) { uint64_t v; memcpy(&v, &mem[a], 8); return v; }
  void wr64(uint64_t a, uint64_t v) { memcpy(&mem[a], &v, 8); }

  void tick() {
    // present a response that is due this cycle
    if (!rsp.empty() && rsp.front().due <= cycles) {
      m->mem_rsp_valid = 1; m->mem_rsp_rdata = rsp.front().data; rsp.pop_front();
    } else {
      m->mem_rsp_valid = 0;
    }
    m->clk = 0; m->eval();
    if (vcd) vcd->dump(t++);
    // sample the request on the rising edge
    if (m->mem_req_valid && m->mem_req_ready) {
      if (m->mem_req_we) wr64(m->mem_req_addr, m->mem_req_wdata);
      else rsp.push_back({cycles + (uint64_t)latency, rd64(m->mem_req_addr)});
    }
    m->clk = 1; m->eval();
    if (vcd) vcd->dump(t++);
    m->reg_valid = 0; m->reg_we = 0;
    cycles++;
  }
};

static uint32_t op_rd32(void *c, uint32_t off) {
  Sim *s = (Sim *)c; s->m->reg_addr = off; s->m->reg_valid = 0; s->m->eval();
  uint32_t v = s->m->reg_rdata; s->tick(); return v;
}
static void op_wr32(void *c, uint32_t off, uint32_t v) {
  Sim *s = (Sim *)c; s->m->reg_valid = 1; s->m->reg_we = 1; s->m->reg_addr = off; s->m->reg_wdata = v; s->tick();
}
static void op_wmb(void *) {}
static const dma_ops OPS = {op_rd32, op_wr32, op_wmb};

static const uint64_t RING_PA = 0x1000, SRC_PA = 0x100000, DST_PA = 0x800000;

// Copies n descriptors of len bytes and returns cycles from doorbell to the last DONE.
static uint64_t run(int lat, uint32_t len, int n, const char *vcd_path, bool *ok) {
  Sim s(lat, 16u << 20);
  if (vcd_path) {
    Verilated::traceEverOn(true);
    s.vcd = new VerilatedVcdC; s.m->trace(s.vcd, 2); s.vcd->open(vcd_path);
  }
  for (uint64_t i = 0; i < (uint64_t)len * n; i += 8) s.wr64(SRC_PA + i, 0x9E3779B97F4A7C15ull * (i + 1));
  dma_dev d;
  dma_init(&d, &OPS, &s, (dma_desc *)&s.mem[RING_PA], RING_PA, 64, 0);
  int posted = 0, reaped = 0;
  uint64_t start = s.cycles;
  while (reaped < n) {
    bool kicked = false;
    while (posted < n && dma_submit(&d, SRC_PA + (uint64_t)posted * len, DST_PA + (uint64_t)posted * len, len, 0) == 0) {
      posted++; kicked = true;
    }
    if (kicked) dma_kick(&d);
    s.tick();
    reaped += dma_reap(&d);
    if (s.cycles - start > 50000000ull) { *ok = false; return 0; }
  }
  uint64_t cyc = s.cycles - start;
  size_t bad = (size_t)-1;
  for (size_t i = 0; i < (size_t)len * n; i++) if (s.mem[SRC_PA + i] != s.mem[DST_PA + i]) { bad = i; break; }
  uint32_t dc = op_rd32(&s, DMA_DONE_CNT);
  if (getenv("DMA_DEBUG")) fprintf(stderr, "first mismatch %zd done_cnt %u\n", (ssize_t)bad, dc);
  *ok = bad == (size_t)-1 && dc == (uint32_t)n;
  return cyc;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  if (argc > 1 && std::string(argv[1]) == "--vcd") {
    bool ok; uint64_t c = run(4, 64, 2, argc > 2 ? argv[2] : "dma.vcd", &ok);
    printf("vcd: 2 x 64 B at latency 4: %llu cycles, %s\n", (unsigned long long)c, ok ? "data ok" : "MISMATCH");
    return ok ? 0 : 1;
  }
  const int lats[] = {1, 8, 32};
  const uint32_t lens[] = {64, 512, 4096, 65536};
  int fail = 0;
  printf("len_bytes,descriptors,mem_latency_cycles,cycles,bytes_per_cycle,data_ok\n");
  for (int lat : lats)
    for (uint32_t len : lens) {
      int n = len >= 65536 ? 8 : 32;
      bool ok; uint64_t c = run(lat, len, n, nullptr, &ok);
      printf("%u,%d,%d,%llu,%.3f,%s\n", len, n, lat, (unsigned long long)c,
             c ? (double)len * n / c : 0.0, ok ? "yes" : "NO");
      if (!ok) fail = 1;
    }
  return fail;
}
