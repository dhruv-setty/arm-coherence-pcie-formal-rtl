#!/usr/bin/env bash
# Compiles and runs every Verilog testbench with Icarus Verilog and dumps a VCD per bench.
set -uo pipefail
cd "$(dirname "$0")/../.."
out=${OUT:-build/capture}; mkdir -p "$out"
run() { # tb sources...
  local tb=$1; shift
  printf 'module dump_%s; initial begin $dumpfile("%s/%s.vcd"); $dumpvars(0, %s); end endmodule\n' "$tb" "$out" "$tb" "$tb" > "$out/dump_$tb.sv"
  echo "\$ iverilog -g2012 -s $tb -o $tb.vvp $* rtl/tb/$tb.sv"
  iverilog -g2012 -s "$tb" -s "dump_$tb" -o "$out/$tb.vvp" "$@" "rtl/tb/$tb.sv" "$out/dump_$tb.sv" || return 1
  echo "\$ vvp $tb.vvp"
  vvp -n "$out/$tb.vvp" | grep -v "^VCD info"
}
iverilog -V 2>&1 | head -1
fail=0
run tb_tlb rtl/mmu/tlb.sv || fail=1
run tb_tlp_hdr_decode rtl/pcie/tlp_hdr_decode.sv || fail=1
run tb_enum rtl/pcie/cfg_space.sv || fail=1
echo "exit status $fail"
exit $fail
