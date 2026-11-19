#!/usr/bin/env bash
# Produces the README captures on a real X display (Xvfb): RTL schematics from Yosys and
# netlistsvg, Geany with the testbenches open as tabs above an xterm running them, and
# GTKWave showing the TLB testbench waveform. Every image comes from the tools named here.
set -euo pipefail
cd "$(dirname "$0")/../.."
export OUT="$PWD/build/capture"; shots=docs/screenshots; mkdir -p "$OUT" "$shots"

# 1. Schematics straight from the RTL (Yosys prep, no technology mapping).
for spec in tlb:rtl/mmu/tlb.sv tlp_hdr_decode:rtl/pcie/tlp_hdr_decode.sv cfg_space:rtl/pcie/cfg_space.sv dma_engine:rtl/dma/dma_engine.sv; do
  top=${spec%%:*}; src=${spec##*:}
  yosys -q -p "read_verilog -sv $src; hierarchy -top $top; proc; opt -full; clean; write_json $OUT/$top.json"
  netlistsvg "$OUT/$top.json" -o "$shots/schematic_$top.svg"
  case $top in tlb|cfg_space) w=3200;; dma_engine) w=4800;; *) w=1600;; esac
  rsvg-convert -b white -w "$w" "$shots/schematic_$top.svg" -o "$shots/schematic_$top.png"
done

# 2. Simulations, also writing VCDs.
docs/capture/run_tbs.sh > "$OUT/sim.log" 2>&1

# 3. Screenshots on a virtual display.
export DISPLAY=:99
Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp & sleep 2
openbox & sleep 1
cfg=$(mktemp -d); mkdir -p "$cfg"
printf '[geany]\npref_main_load_session=false\nmsgwindow_visible=false\nsidebar_visible=true\npref_toolbar_show=true\n' > "$cfg/geany.conf"
geany -c "$cfg" rtl/tb/tb_enum.sv rtl/tb/tb_tlp_hdr_decode.sv rtl/tb/tb_tlb.sv >/dev/null 2>&1 &
gw=$(xdotool search --sync --onlyvisible --class Geany | head -1)
xdotool windowmove "$gw" 0 0 windowsize "$gw" 1600 640; sleep 2
xterm -geometry 200x22+0+640 -fa 'DejaVu Sans Mono' -fs 10 -bg '#1e1e1e' -fg '#d4d4d4' -T 'iverilog: run_tbs.sh' \
  -e bash -c 'docs/capture/run_tbs.sh; exec sleep 600' &
sleep 8
i=1
for tb in tb_tlb tb_tlp_hdr_decode tb_enum; do
  geany -c "$cfg" "rtl/tb/$tb.sv" >/dev/null 2>&1; sleep 2   # switches the running instance to this tab
  xdotool windowactivate --sync "$gw"; sleep 1
  import -window root "$shots/testbench_$i-$tb.png"
  i=$((i+1))
done

# 4. GTKWave views of the testbench dumps and the Verilator DMA capture.
wave() { # name vcd height signals...
  local name=$1 vcd=$2 h=$3; shift 3
  { echo "gtkwave::addSignalsFromList [list $*]"; echo "gtkwave::/Time/Zoom/Zoom_Best_Fit"; } > "$OUT/$name.tcl"
  gtkwave --rcvar "initial_window_x 1600" --rcvar "initial_window_y $h" "$vcd" -S "$OUT/$name.tcl" >/dev/null 2>&1 &
  local pid=$! ww
  ww=$(xdotool search --sync --onlyvisible --class gtkwave | tail -1)
  xdotool windowmove "$ww" 0 0; sleep 4
  xdotool windowactivate --sync "$ww"; sleep 1
  import -window "$ww" "$shots/waveform_$name.png"
  kill $pid; sleep 2
}
T=tb_tlb
wave tb_tlb "$OUT/tb_tlb.vcd" 560 $T.clk $T.rst_n $T.fill_en $T.fill_vpn $T.fill_ppn $T.lookup_vpn $T.hit $T.ppn $T.inv_en $T.inv_vpn $T.inv_all $T.errors
T=tb_tlp_hdr_decode
wave tb_tlp_hdr_decode "$OUT/tb_tlp_hdr_decode.vcd" 600 $T.hdr $T.is_mem_rd $T.is_mem_wr $T.is_cpl $T.is_4dw $T.has_data $T.len_dw $T.attr $T.tc $T.req_id $T.tag $T.addr $T.be_malformed $T.errors
T=tb_enum
wave tb_enum "$OUT/tb_enum.vcd" 620 $T.clk $T.rst_n $T.we $T.rg $T.wd $T.found $T.d1.cfg_rdata $T.d1.bar0_base $T.d1.bar2_base $T.d1.mem_space_en $T.d1.bus_master_en $T.d3.bar0_base $T.d3.bar2_base $T.errors
T=TOP.dma_engine
wave dma_two_descriptors bench/results/dma_two_descriptors.vcd 680 $T.clk $T.rst_n $T.reg_valid $T.reg_addr $T.state $T.head $T.tail $T.mem_req_valid $T.mem_req_we $T.mem_req_addr $T.mem_rsp_valid $T.outstanding $T.done_cnt $T.irq

# 5. Lint and synthesis in a terminal.
xterm -geometry 200x50+0+0 -fa 'DejaVu Sans Mono' -fs 10 -bg '#1e1e1e' -fg '#d4d4d4' -T 'verilator lint and yosys synth_ecp5' -e bash -c '
for f in rtl/pcie/tlp_hdr_decode.sv rtl/pcie/cfg_space.sv rtl/mmu/tlb.sv rtl/dma/dma_engine.sv; do
  echo "\$ verilator --lint-only -Wall $f"; verilator --lint-only -Wall "$f" && echo "ok    lint $f"; done
verilator --version
echo "\$ bench/synth.sh"; bench/synth.sh 2>&1 | tee '"$OUT"'/synth.log
echo "\$ yosys -V"; yosys -V; exec sleep 600' &
xpid=$!
for _ in $(seq 1 90); do grep -q "tlp_hdr_decode," "$OUT/synth.log" 2>/dev/null && break; sleep 2; done; sleep 3
import -window root "$shots/terminal_lint_synth.png"
kill $xpid || true
cp "$OUT/sim.log" "$shots/sim.log"
cat "$OUT/sim.log"
