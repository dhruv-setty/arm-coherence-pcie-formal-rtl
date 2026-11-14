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
  states=$(grep -oE "[0-9]+ distinct states found" <<<"$out" | head -1 || true)
  if [ "$got" = "$4" ]; then echo "ok    TLC $3 ($4 as expected; $states)";
  else echo "FAIL  TLC $3 expected $4, got $got"; fail=1; fi
}

tlc spec/coherence MESI  MESI  pass
tlc spec/coherence MOESI MOESI pass
tlc spec/tlb  TLBShootdown TLBShootdown     pass
tlc spec/tlb  TLBShootdown TLBShootdown_bug fail
tlc spec/pcie TLPOrdering  TLPOrdering      pass
tlc spec/pcie TLPOrdering  TLPOrdering_bug  fail

python3 memory-models/litmus.py || fail=1

verilator --lint-only -Wall rtl/tlp_hdr_decode.sv || fail=1
verilator --lint-only -Wall rtl/tlb.sv || fail=1
sim=$(mktemp -d)
iverilog -g2012 -o "$sim/hdr" rtl/tlp_hdr_decode.sv rtl/tb/tb_tlp_hdr_decode.sv && vvp "$sim/hdr" | grep -q "^PASS" && echo "ok    sim tb_tlp_hdr_decode" || { echo "FAIL  sim tb_tlp_hdr_decode"; fail=1; }
iverilog -g2012 -o "$sim/tlb" rtl/tlb.sv rtl/tb/tb_tlb.sv && vvp "$sim/tlb" | grep -q "^PASS" && echo "ok    sim tb_tlb" || { echo "FAIL  sim tb_tlb"; fail=1; }

exit $fail
