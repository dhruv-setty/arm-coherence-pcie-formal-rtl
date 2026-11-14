# IĀTŌ

[![check](https://github.com/whatheheckisthis/Intent-to-Auditable-Trust-Object/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/whatheheckisthis/Intent-to-Auditable-Trust-Object/actions/workflows/check.yml)
[![results](https://github.com/whatheheckisthis/Intent-to-Auditable-Trust-Object/actions/workflows/results.yml/badge.svg?branch=main)](https://github.com/whatheheckisthis/Intent-to-Auditable-Trust-Object/actions/workflows/results.yml)
![release](https://img.shields.io/badge/release-v0.2.0-blue)
![license](https://img.shields.io/badge/license-Apache%202.0-blue)
![TLA+](https://img.shields.io/badge/spec-TLA%2B-4b6cb7)
![Sail](https://img.shields.io/badge/spec-Sail-259dd5)
![RTL](https://img.shields.io/badge/RTL-SystemVerilog-b2b7f8)
![FPGA](https://img.shields.io/badge/ECP5-129.10%20MHz%20DMA-success)
![silicon](https://img.shields.io/badge/litmus-Neoverse%20V2-orange)

**Intent to Auditable Trust Object.** The monolith of the series: one repo where hardware behaviour is written down as something a machine can check, then built, simulated, synthesised and measured.

The series sits under the operating system. How caches agree on a value. How a CHI home node serialises requests. How a page stops being reachable after it is unmapped. How PCIe orders posted writes and how software finds and sizes a device. How a DMA engine and its driver hand descriptors back and forth. What a load may return on real Arm silicon. Every number below comes from a run of `./scripts/check.sh` or the bench scripts, and CI repeats the checks on every push.

## Contents

1. [Results at a glance](#1-results-at-a-glance)
2. [System](#2-system)
3. [DMA engine and driver](#3-dma-engine-and-driver)
4. [Synthesis](#4-synthesis)
5. [Litmus tests on silicon](#5-litmus-tests-on-silicon)
6. [CHI mapping](#6-chi-mapping)
7. [Layout](#7-layout)
8. [Roadmap](#8-roadmap)


## 1. Results at a glance

| Area | Artefact | Result |
|---|---|---|
| CHI coherence | `spec/chi/CHIHome.tla` | RN-F states I, UC, UD, SC, SD with an HN-F that serialises ReadShared, ReadUnique and WriteBackFull, one snoop per step. SWMR, single dirty copy, data value and memory currency hold over 11,590 states (3 RN-F, 2 values). Request progress holds with a fair home arbiter; with weak fairness TLC finds a starving requester |
| Coherence | `spec/coherence/MESI.tla`, `MOESI.tla` | Atomic bus baselines, 120 and 216 states, all invariants hold |
| Virtual memory | `spec/tlb/TLBShootdown.tla` | No core keeps a translation to a freed frame; freeing before every IPI ack fails |
| PCIe ordering | `spec/pcie/TLPOrdering.tla` | Flag then data is safe with strict posted ordering; Relaxed Ordering on the flag write lets the consumer read stale data |
| PCIe enumeration | `rtl/pcie/cfg_space.sv`, `rtl/tb/tb_enum.sv` | Type 0 header with a 32 bit BAR and a 64 bit prefetchable BAR pair. The testbench scans bus 0, skips empty slots, sizes every BAR by writing all ones, assigns naturally aligned addresses and enables Memory Space and Bus Master |
| PCIe TLPs | `rtl/pcie/tlp_hdr_decode.sv` | 3DW and 4DW memory request and completion decode with byte enable checks |
| DMA | `rtl/dma/dma_engine.sv`, `driver/dma_drv.c` | Descriptor ring engine with OWN and DONE handoff, driven by a C driver under Verilator. Every copy in the sweep is verified byte for byte |
| MMU | `rtl/mmu/tlb.sv` | Fully associative TLB with fill, invalidate by VPN and invalidate all |
| Memory models | `memory-models/litmus.py` | 15 expected allow or forbid results under SC, TSO and a simplified relaxed model all hold |
| Sail | `spec/sail/` | TLBI by-VA operand layout from DDI0487K and the DMA descriptor OWN and DONE handoff, typechecked and compiled to C, with 14 executable assertions |
| Silicon | `memory-models/hw/litmus_hw.c` | Litmus runs on a Neoverse V2 host; see below |

## 2. System

How one copy moves through the pieces, and which spec covers each hop.

```
  software                         device (rtl/)                       checked by
 ----------                       ---------------                     ------------
 enumeration (tb_enum.sv)
   |  cfg read/write, BAR sizing
   v
 +----------------+   Type 0    +-------------------+                  tb_enum (sim)
 | host / driver  |-----------> | cfg_space.sv      |                  synth (Yosys)
 | dma_drv.c      |   header    | BAR0 regs, BAR2/3 |
 | (Linux: PR 28) |             +-------------------+
 +----------------+                      |
   | 1 write desc: src, dst, len         | BAR0 MMIO
   | 2 dma_wmb, set OWN                  v
   | 3 doorbell TAIL ------------> +-------------------+               Sail dma_desc
   |                               | dma_engine.sv     |               SVA (PR 26)
   |                               | fetch desc        |               bench (Verilator)
   |                               | copy, MAX_RD reads|
   |                               | writeback OWN=0,  |
   |                               | DONE=1, HEAD++    |
   |                               +-------------------+
   |                                  | 8 B beats, one port
   v                                  v
 +-----------------------------------------------------+
 | host memory: descriptor ring, source, destination   |              TLPOrdering.tla
 +-----------------------------------------------------+              tlp_hdr_decode.sv
   ^  4 reap: read DONE from memory, dma_rmb                          
   |                                                                  
 +----------------+    coherence     +--------------------+           CHIHome.tla
 | CPU caches     |<---------------->| CHI home node HN-F |           MESI / MOESI.tla
 | RN-F I UC UD   |   snoops, data   | serialises requests|           litmus (Neoverse V2)
 | SC SD          |                  +--------------------+
 +----------------+
   | unmap, TLBI, IPI                                                 TLBShootdown.tla
   v                                                                  Sail aarch64_tlbi
 +----------------+                                                   tlb.sv (sim, synth)
 | TLB (tlb.sv)   |
 +----------------+
```

Full tables for every run are in [docs/RESULTS.md](docs/RESULTS.md).

## 3. DMA engine and driver

The engine walks a ring of 32 byte descriptors in host memory. The driver writes source, destination and length, sets OWN last, issues a write barrier and rings the TAIL doorbell. The engine fetches the descriptor, copies 8 bytes per beat, writes back OWN cleared and DONE set, and only then advances HEAD and DONE_CNT in the same cycle. The driver reaps by reading DONE from memory, so the fast path never touches a register.

An early version updated DONE_CNT one cycle after writing DONE, and the driver could read a stale count. The fix is in the RTL, and the harness checks the count after every run.

**Benchmark** (`bench/run.sh`). The memory port takes one request per cycle and is shared between reads and writes, so the ceiling is 4 bytes per cycle. Reads can be outstanding up to `MAX_RD`.

| Copy size | Latency 1 | Latency 8 | Latency 32, MAX_RD 8 | Latency 32, MAX_RD 32 |
|---|---|---|---|---|
| 64 B | 2.46 B/cycle | 1.88 | 0.78 | 0.78 |
| 512 B | 3.71 | 3.35 | 1.39 | 2.99 |
| 4 KiB | 3.96 | 3.71 | 1.54 | 3.79 |
| 64 KiB | 4.00 | 3.76 | 1.56 | 3.93 |

At latency 32 with 8 reads in flight the engine is bound by Little's law: 8 beats of 8 bytes per round trip. With 32 in flight it gets back to within 2 percent of the ceiling. Small copies are bound by the descriptor fetch and writeback, which is the case for batching or prefetching descriptors.

**Waveform.** `bench/wave/dma_two_descriptors.png` is the simulated logic analyser view of two 64 byte descriptors at latency 4, rendered from the VCD by `bench/vcd_view.py`.

## 4. Synthesis

Yosys `synth_ecp5`, then nextpnr place and route out of context (no IO buffers) on a Lattice LFE5U-25F, seed 1. These are open tool estimates on a small FPGA, not vendor tool or ASIC numbers.

| Module | LUT4 | FF | Carry | Post route Fmax |
|---|---|---|---|---|
| dma_engine (MAX_RD 8) | 966 | 954 | 154 | 129.10 MHz |
| tlb (4 entries) | 912 | 166 | 0 | 115.47 MHz |
| cfg_space | 138 | 75 | 0 | no register to register path |
| tlp_hdr_decode | 74 | 0 | 0 | combinational |

At 129.10 MHz the DMA ceiling of 4 bytes per cycle is about 516 MB/s. Fmax for MAX_RD 32 has not been measured.

## 5. Litmus tests on silicon

`memory-models/hw/litmus_hw.c` runs each test 2,000,000 times on two threads with plain LDR and STR, DMB ISH, or LDAR and STLR. Host: Arm Neoverse V2 (MIDR part 0xd4f), Linux, run 2026-11-14.

| Test | Relaxed outcome | Seen |
|---|---|---|
| SB | r0=0, r1=0 | 10,576 |
| SB+dmb | r0=0, r1=0 | 0 |
| MP | r0=1, r1=0 | 181 |
| MP+dmb | r0=1, r1=0 | 0 |
| MP+stlr+ldar | r0=1, r1=0 | 0 |
| LB | r0=1, r1=1 | 0 |

MP reordering shows up on real hardware, and both fixes remove it. LB is allowed by the architecture and was not observed in this run, which is usual on current cores and is not proof it cannot happen. Counts vary run to run; CI only asserts that fenced variants never show the relaxed outcome.

## 6. CHI mapping

| MOESI | CHI | Meaning |
|---|---|---|
| M | UD | Only copy, modified |
| E | UC | Only copy, clean |
| S | SC | Shared, not responsible for writeback |
| O | SD | Shared, responsible for writeback |
| I | I | No copy |

`CHIHome.tla` does not model UCE, UDP, direct memory or cache transfer (DMT, DCT), retry with protocol credits, or CompAck timing. The fairness result says what the arbiter has to guarantee, not how CHI implements it.

## 7. Layout

```
spec/            TLA+: chi/, coherence/, tlb/, pcie/; Sail: sail/
rtl/pcie/        cfg_space.sv, tlp_hdr_decode.sv
rtl/dma/         dma_engine.sv
rtl/mmu/         tlb.sv
rtl/tb/          Icarus testbenches
driver/          dma_drv.c, dma_drv.h
bench/           Verilator harness, run.sh, synth.sh, vcd_view.py, results/, wave/
memory-models/   litmus.py (models), hw/litmus_hw.c (silicon)
scripts/check.sh everything, with expected passes and expected failures
docs/            references.md, RESULTS.md
```

Requirements: Java 11 or later, Python 3, Icarus Verilog, Verilator, a C compiler, and optionally Yosys, nextpnr-ecp5 and Sail 0.20 (with libgmp). Matplotlib only for the waveform image.

## 8. Roadmap

1. CHI: transient states at the RN-F, DCT, and retry with credits instead of strong fairness.
2. DMA: descriptor prefetch, scatter gather, MSI on completion, and a Linux PCI driver skeleton using the same register map.
3. PCIe: completion ordering and a TLP generator wired to the DMA engine.
4. Formal: SystemVerilog assertions on the DMA handoff, checked with SymbiYosys.
5. Arm: Stage 2 translation and TLBI semantics from DDI0487K, cross checked against QEMU target/arm.
