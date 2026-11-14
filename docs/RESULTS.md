# IĀTŌ results

Every table is generated from the files in `bench/results/` or from `./scripts/check.sh` at tag v0.2.0. Simulation, open tool synthesis and one silicon run; no physical FPGA, no vendor tools.

## Contents

1. [Model checking (TLC)](#1-model-checking-tlc)
2. [Simulation and executable specs](#2-simulation-and-executable-specs)
3. [DMA benchmark, MAX_RD 8](#3-dma-benchmark-max_rd-8)
4. [DMA benchmark, MAX_RD 32](#4-dma-benchmark-max_rd-32)
5. [Synthesis, Lattice ECP5](#5-synthesis-lattice-ecp5)
6. [Litmus on Neoverse V2](#6-litmus-on-neoverse-v2)

## 1. Model checking (TLC)

| Config | Directory | Expected result | Distinct states |
|---|---|---|---|
| MESI | spec/coherence | pass | 120 |
| MOESI | spec/coherence | pass | 216 |
| TLBShootdown | spec/tlb | pass | 22 |
| TLBShootdown_bug | spec/tlb | fail, as expected | 25 |
| TLPOrdering | spec/pcie | pass | 8 |
| TLPOrdering_bug | spec/pcie | fail, as expected | 11 |
| CHIHome | spec/chi | pass | 11,590 |
| CHIHome_starve | spec/chi | fail, as expected (starvation under weak fairness) | 11,590 |

`CHIHomeCredits` (FIFO credit grant, 16,500 states, progress under weak fairness) is in pull request 27 (`feat/chi-retry-credits`) and lands with it.

## 2. Simulation and executable specs

| Check | Tool | What it covers | Result |
|---|---|---|---|
| tb_tlp_hdr_decode | Icarus | 3DW and 4DW requests and completions | pass |
| tb_enum | Icarus | Two devices found, BARs sized and assigned, Memory Space and Bus Master on | pass |
| tb_tlb | Icarus | Fill, hit, invalidate by VPN, invalidate all | pass |
| dma bench | Verilator + dma_drv.c | 24 runs, every copy compared byte for byte | pass |
| Sail | Sail 0.20.3 to C | TLBI operand and descriptor handoff, 14 assertions | pass |
| litmus.py | Python | 15 allow or forbid results under SC, TSO, relaxed | pass |

## 3. DMA benchmark, MAX_RD 8

Shared memory port, one request per cycle, ceiling 4 bytes per cycle.

| Copy size | Descriptors | Memory latency (cycles) | Cycles | Bytes per cycle | Verified |
|---|---|---|---|---|---|
| 64 B | 32 | 1 | 833 | 2.459 | yes |
| 512 B | 32 | 1 | 4,417 | 3.709 | yes |
| 4 KiB | 32 | 1 | 33,089 | 3.961 | yes |
| 64 KiB | 8 | 1 | 131,153 | 3.998 | yes |
| 64 B | 32 | 8 | 1,089 | 1.881 | yes |
| 512 B | 32 | 8 | 4,897 | 3.346 | yes |
| 4 KiB | 32 | 8 | 35,361 | 3.707 | yes |
| 64 KiB | 8 | 8 | 139,401 | 3.761 | yes |
| 64 B | 32 | 32 | 2,625 | 0.780 | yes |
| 512 B | 32 | 32 | 11,809 | 1.387 | yes |
| 4 KiB | 32 | 32 | 85,281 | 1.537 | yes |
| 64 KiB | 8 | 32 | 336,201 | 1.559 | yes |

## 4. DMA benchmark, MAX_RD 32

| Copy size | Descriptors | Memory latency (cycles) | Cycles | Bytes per cycle | Verified |
|---|---|---|---|---|---|
| 64 B | 32 | 1 | 833 | 2.459 | yes |
| 512 B | 32 | 1 | 4,417 | 3.709 | yes |
| 4 KiB | 32 | 1 | 33,089 | 3.961 | yes |
| 64 KiB | 8 | 1 | 131,153 | 3.998 | yes |
| 64 B | 32 | 8 | 1,089 | 1.881 | yes |
| 512 B | 32 | 8 | 4,897 | 3.346 | yes |
| 4 KiB | 32 | 8 | 33,345 | 3.931 | yes |
| 64 KiB | 8 | 8 | 131,265 | 3.994 | yes |
| 64 B | 32 | 32 | 2,625 | 0.780 | yes |
| 512 B | 32 | 32 | 5,473 | 2.994 | yes |
| 4 KiB | 32 | 32 | 34,593 | 3.789 | yes |
| 64 KiB | 8 | 32 | 133,449 | 3.929 | yes |

## 5. Synthesis, Lattice ECP5

Yosys `synth_ecp5`, nextpnr out of context on LFE5U-25F, seed 1.

| Module | LUT4 | FF | Carry (CCU2C) | Post route Fmax |
|---|---|---|---|---|
| dma_engine | 966 | 954 | 154 | 129.10 MHz |
| cfg_space | 138 | 75 | 0 | no reg to reg path |
| tlb | 912 | 166 | 0 | 115.47 MHz |
| tlp_hdr_decode | 74 | 0 | 0 | no reg to reg path |

## 6. Litmus on Neoverse V2

2,000,000 iterations per test, host MIDR part 0xd4f, run 2026-11-14. Counts vary run to run.

| Test | Iterations | r0=0, r1=0 | r0=0, r1=1 | r0=1, r1=0 | r0=1, r1=1 | Relaxed outcome seen |
|---|---|---|---|---|---|---|
| SB | 2,000,000 | 10,576 | 994,429 | 994,995 | 0 | 10,576 |
| SB+dmb | 2,000,000 | 0 | 1,001,528 | 997,188 | 1,284 | 0 |
| MP | 2,000,000 | 1,004,043 | 627,499 | 181 | 368,277 | 181 |
| MP+dmb | 2,000,000 | 999,822 | 999,661 | 0 | 517 | 0 |
| MP+stlr+ldar | 2,000,000 | 1,002,095 | 686,901 | 0 | 311,004 | 0 |
| LB | 2,000,000 | 818,335 | 260,871 | 920,794 | 0 | 0 |
