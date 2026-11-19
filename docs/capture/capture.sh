#!/usr/bin/env bash
# Produces the README captures on a real X display (Xvfb): RTL schematics from Yosys and
# netlistsvg, Geany with the testbenches open as tabs above an xterm running them, and
# GTKWave showing the TLB testbench waveform. Every image comes from the tools named here.
set -euo pipefail
cd "$(dirname "$0")/../.."
export OUT="$PWD/build/capture"; shots=docs/screenshots; mkdir -p "$OUT" "$shots"

# 1. Schematics straight from the RTL (Yosys prep, no technology mapping).
for spec in tlb:rtl/mmu/tlb.sv tlp_hdr_decode:rtl/pcie/tlp_hdr_decode.sv; do
  top=${spec%%:*}; src=${spec##*:}
  yosys -q -p "read_verilog -sv $src; hierarchy -top $top; proc; opt -full; clean; write_json $OUT/$top.json"
  netlistsvg "$OUT/$top.json" -o "$shots/schematic_$top.svg"
  rsvg-convert -b white -w 1600 "$shots/schematic_$top.svg" -o "$shots/schematic_$top.png"
done

# 2. Simulations, also writing VCDs.
docs/capture/run_tbs.sh > "$OUT/sim.log" 2>&1

# 3. Screenshots on a virtual display.
export DISPLAY=:99
Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp & sleep 2
openbox & sleep 1
cfg=$(mktemp -d); mkdir -p "$cfg"
printf '[geany]\npref_main_load_session=false\nmsgwindow_visible=false\nsidebar_visible=true\npref_toolbar_show=true\n' > "$cfg/geany.conf"
geany -c "$cfg" -i rtl/tb/tb_enum.sv rtl/tb/tb_tlp_hdr_decode.sv rtl/tb/tb_tlb.sv >/dev/null 2>&1 &
gw=$(xdotool search --sync --onlyvisible --class Geany | head -1)
xdotool windowmove "$gw" 0 0 windowsize "$gw" 1600 640; sleep 2
xterm -geometry 200x22+0+640 -fa 'DejaVu Sans Mono' -fs 10 -bg '#1e1e1e' -fg '#d4d4d4' -T 'iverilog: run_tbs.sh' \
  -e bash -c 'docs/capture/run_tbs.sh; exec sleep 600' &
sleep 8
i=1
for tb in tb_tlb tb_tlp_hdr_decode tb_enum; do
  xdotool windowactivate --sync "$gw"; sleep 1
  import -window root "$shots/testbench_$i-$tb.png"
  xdotool key --window "$gw" ctrl+Page_Up; sleep 1
  i=$((i+1))
done

# 4. GTKWave on the TLB testbench dump.
cat > "$OUT/tlb.tcl" <<'TCL'
set sigs [list tb_tlb.clk tb_tlb.rst_n tb_tlb.fill_en tb_tlb.fill_vpn tb_tlb.fill_ppn tb_tlb.lookup_vpn tb_tlb.hit tb_tlb.ppn tb_tlb.inv_en tb_tlb.inv_vpn tb_tlb.inv_all tb_tlb.errors]
gtkwave::addSignalsFromList $sigs
gtkwave::/Time/Zoom/Zoom_Best_Fit
TCL
gtkwave "$OUT/tb_tlb.vcd" -S "$OUT/tlb.tcl" >/dev/null 2>&1 &
ww=$(xdotool search --sync --onlyvisible --class gtkwave | head -1)
xdotool windowmove "$ww" 0 0 windowsize "$ww" 1600 1000; sleep 4
xdotool windowactivate --sync "$ww"; sleep 1
import -window root "$shots/waveform_tb_tlb.png"
cp "$OUT/sim.log" "$shots/sim.log"
cat "$OUT/sim.log"
