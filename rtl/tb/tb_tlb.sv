module tb_tlb;
  logic clk = 0, rst_n = 0;
  logic [19:0] lookup_vpn, fill_vpn, inv_vpn, ppn, fill_ppn;
  logic hit, fill_en = 0, inv_en = 0, inv_all = 0;
  int errors = 0;

  tlb #(.ENTRIES(4)) dut (.*);
  always #5 clk = ~clk;

  task automatic check(input string name, input logic cond);
    if (!cond) begin errors++; $display("FAIL %s", name); end
  endtask

  // No two valid entries may map the same VPN.
  always @(posedge clk) if (rst_n) begin
    for (int i = 0; i < 4; i++)
      for (int j = i + 1; j < 4; j++)
        if (dut.valid[i] && dut.valid[j] && dut.vpn_q[i] == dut.vpn_q[j]) begin
          errors++; $display("FAIL duplicate VPN in entries %0d and %0d", i, j);
        end
  end

  task automatic fill(input logic [19:0] v, input logic [19:0] p);
    @(negedge clk); fill_en = 1; fill_vpn = v; fill_ppn = p;
    @(negedge clk); fill_en = 0;
  endtask

  task automatic look(input logic [19:0] v);
    lookup_vpn = v; #1;
  endtask

  initial begin
    lookup_vpn = 0; fill_vpn = 0; fill_ppn = 0; inv_vpn = 0;
    #12 rst_n = 1;

    fill(20'h00010, 20'hA0010);
    look(20'h00010); check("hit after fill", hit && ppn == 20'hA0010);
    look(20'h00011); check("miss other vpn", !hit);

    fill(20'h00010, 20'hB0010);
    look(20'h00010); check("refill updates in place", hit && ppn == 20'hB0010);

    fill(20'h00020, 20'hA0020);
    fill(20'h00030, 20'hA0030);
    fill(20'h00040, 20'hA0040);
    fill(20'h00050, 20'hA0050);  // evicts the round robin victim
    look(20'h00050); check("hit newest", hit && ppn == 20'hA0050);

    @(negedge clk); inv_en = 1; inv_vpn = 20'h00050;
    @(negedge clk); inv_en = 0;
    look(20'h00050); check("miss after invalidate", !hit);

    @(negedge clk); inv_all = 1;
    @(negedge clk); inv_all = 0;
    look(20'h00030); check("miss after invalidate all", !hit);

    if (errors == 0) $display("PASS tb_tlb");
    else $fatal(1, "%0d check(s) failed", errors);
    $finish;
  end
endmodule
