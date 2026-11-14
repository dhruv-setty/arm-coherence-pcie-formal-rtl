#!/usr/bin/env bash
# Builds the Verilator model of dma_engine with the C driver and runs the sweep.
# Output: bench/results/dma_maxrd<N>.csv and a VCD capture of two descriptors.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p results
for N in 8 32; do
  rm -rf obj_$N
  verilator -Wall --cc --trace --exe --build -O2 -GMAX_RD=$N --Mdir obj_$N \
    ../rtl/dma/dma_engine.sv harness.cpp ../driver/dma_drv.c -CFLAGS -O2 -o dma_bench >/dev/null
  ./obj_$N/dma_bench > results/dma_maxrd$N.csv
  echo "MAX_RD=$N"; cat results/dma_maxrd$N.csv
done
./obj_8/dma_bench --vcd results/dma_two_descriptors.vcd
if python3 -c "import matplotlib" 2>/dev/null; then
  python3 vcd_view.py results/dma_two_descriptors.vcd wave/dma_two_descriptors.png 0 70
fi
rm -rf obj_8 obj_32
