#!/usr/bin/env bash
# Runs every check in the repo. Passing specs must pass; *_bug configs must fail.
set -euo pipefail
cd "$(dirname "$0")/.."
TLA_JAR="${TLA_JAR:-tools/tla2tools.jar}"
if [ ! -f "$TLA_JAR" ]; then
  mkdir -p tools
  curl -sSL -o "$TLA_JAR" https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
fi
TLA_JAR="$(cd "$(dirname "$TLA_JAR")" && pwd)/$(basename "$TLA_JAR")"
fail=0

tlc() { # dir module cfg expect(pass|fail)
  local out
  out=$(cd "$1" && java -XX:+UseParallelGC -cp "$TLA_JAR" tlc2.TLC -workers auto -cleanup -config "$3.cfg" "$2.tla" 2>&1 || true)
  rm -rf "$1"/states "$1"/*_TTrace_* 2>/dev/null || true
  if grep -q "No error has been found" <<<"$out"; then got=pass; else got=fail; fi
  states=$(grep -oE "[0-9,]+ distinct states found" <<<"$out" | tail -1 || true)
  if [ "$got" = "$4" ]; then echo "ok    TLC $3 ($4 as expected; $states)";
  else echo "FAIL  TLC $3 expected $4, got $got"; fail=1; fi
}

tlc spec/coherence MESI  MESI  pass
tlc spec/coherence MOESI MOESI pass
tlc spec/tlb  TLBShootdown TLBShootdown     pass
tlc spec/tlb  TLBShootdown TLBShootdown_bug fail
tlc spec/pcie TLPOrdering  TLPOrdering      pass
tlc spec/pcie TLPOrdering  TLPOrdering_bug  fail
tlc spec/chi  CHIHome      CHIHome          pass
tlc spec/chi  CHIHome      CHIHome_starve   fail

python3 memory-models/litmus.py || fail=1

for f in rtl/pcie/tlp_hdr_decode.sv rtl/pcie/cfg_space.sv rtl/mmu/tlb.sv rtl/dma/dma_engine.sv; do
  verilator --lint-only -Wall "$f" && echo "ok    lint $f" || { echo "FAIL  lint $f"; fail=1; }
done
sim=$(mktemp -d)
iverilog -g2012 -o "$sim/hdr" rtl/pcie/tlp_hdr_decode.sv rtl/tb/tb_tlp_hdr_decode.sv && vvp "$sim/hdr" | grep -q "^PASS" && echo "ok    sim tb_tlp_hdr_decode" || { echo "FAIL  sim tb_tlp_hdr_decode"; fail=1; }
iverilog -g2012 -o "$sim/enum" rtl/pcie/cfg_space.sv rtl/tb/tb_enum.sv 2>/dev/null && vvp "$sim/enum" | grep -q "^PASS" && echo "ok    sim tb_enum" || { echo "FAIL  sim tb_enum"; fail=1; }
iverilog -g2012 -o "$sim/tlb" rtl/mmu/tlb.sv rtl/tb/tb_tlb.sv && vvp "$sim/tlb" | grep -q "^PASS" && echo "ok    sim tb_tlb" || { echo "FAIL  sim tb_tlb"; fail=1; }

# DMA engine with the C driver under Verilator: every run must copy correctly.
if bench/run.sh > "$sim/bench.txt" 2>&1 && ! grep -q ",NO$" bench/results/dma_maxrd*.csv; then
  echo "ok    dma bench (driver plus RTL, all copies verified)"
else echo "FAIL  dma bench"; cat "$sim/bench.txt"; fail=1; fi

# Same sweep with the SVA bound in and checked (--assert).
( cd bench && rm -rf obj_sva && verilator -Wall -Wno-UNUSEDSIGNAL -Wno-SYNCASYNCNET --assert --trace --cc --exe --build -O2 \
    --Mdir obj_sva ../rtl/dma/dma_engine.sv ../rtl/dma/dma_engine_sva.sv harness.cpp ../driver/dma_drv.c -CFLAGS -O2 -o dma_bench >/dev/null \
  && ./obj_sva/dma_bench > /dev/null; r=$?; rm -rf obj_sva; exit $r ) \
  && echo "ok    dma sva (6 assertions over the full sweep)" || { echo "FAIL  dma sva"; fail=1; }

# Litmus on the host CPU: fenced variants must never show the relaxed outcome.
cc -O2 -pthread memory-models/hw/litmus_hw.c -o "$sim/litmus_hw" && "$sim/litmus_hw" 200000 > "$sim/lh.txt" \
  && echo "ok    hardware litmus ($(uname -m))" || { echo "FAIL  hardware litmus"; cat "$sim/lh.txt"; fail=1; }

# Sail: typecheck, compile to C, run the executable checks.
if command -v sail >/dev/null; then
  L=$(sail -dir)/lib
  if sail -c spec/sail/aarch64_tlbi.sail spec/sail/dma_desc.sail spec/sail/main.sail -o "$sim/iato_sail" \
     && gcc -O1 "$sim/iato_sail.c" "$L"/*.c -I"$L" -lgmp -lz -o "$sim/iato_sail" 2>/dev/null \
     && "$sim/iato_sail" | grep -q "^PASS"; then echo "ok    sail (TLBI operand, DMA descriptor handoff)"
  else echo "FAIL  sail"; fail=1; fi
  rm -f sail_smt_cache spec/sail/sail_smt_cache
fi

if command -v yosys >/dev/null; then
  bench/synth.sh > "$sim/synth.txt" 2>&1 && echo "ok    yosys synth_ecp5" || { echo "FAIL  synth"; cat "$sim/synth.txt"; fail=1; }
fi

exit $fail
