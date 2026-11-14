// Small fully associative TLB: lookup, fill, invalidate by VPN, invalidate all.
// Round robin replacement. A fill to a VPN already present updates that entry,
// so the array never holds two valid entries for one VPN.
module tlb #(
  parameter int ENTRIES = 4,
  parameter int VPN_W   = 20,
  parameter int PPN_W   = 20
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic [VPN_W-1:0] lookup_vpn,
  output logic             hit,
  output logic [PPN_W-1:0] ppn,
  input  logic             fill_en,
  input  logic [VPN_W-1:0] fill_vpn,
  input  logic [PPN_W-1:0] fill_ppn,
  input  logic             inv_en,
  input  logic [VPN_W-1:0] inv_vpn,
  input  logic             inv_all
);
  localparam int IW = (ENTRIES > 1) ? $clog2(ENTRIES) : 1;

  logic [ENTRIES-1:0] valid;
  logic [VPN_W-1:0]   vpn_q [ENTRIES];
  logic [PPN_W-1:0]   ppn_q [ENTRIES];
  logic [IW-1:0]      victim;

  always_comb begin
    hit = 1'b0;
    ppn = '0;
    for (int i = 0; i < ENTRIES; i++) begin
      if (valid[i] && vpn_q[i] == lookup_vpn) begin
        hit = 1'b1;
        ppn = ppn_q[i];
      end
    end
  end

  logic             fill_match;
  logic [IW-1:0]    fill_idx;
  always_comb begin
    fill_match = 1'b0;
    fill_idx   = victim;
    for (int i = 0; i < ENTRIES; i++) begin
      if (valid[i] && vpn_q[i] == fill_vpn) begin
        fill_match = 1'b1;
        fill_idx   = IW'(i);
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid  <= '0;
      victim <= '0;
    end else if (inv_all) begin
      valid <= '0;
    end else begin
      if (inv_en) begin
        for (int i = 0; i < ENTRIES; i++)
          if (vpn_q[i] == inv_vpn) valid[i] <= 1'b0;
      end
      if (fill_en && !(inv_en && fill_vpn == inv_vpn)) begin
        valid[fill_idx] <= 1'b1;
        vpn_q[fill_idx] <= fill_vpn;
        ppn_q[fill_idx] <= fill_ppn;
        if (!fill_match) victim <= (victim == IW'(ENTRIES - 1)) ? '0 : victim + 1'b1;
      end
    end
  end
endmodule
