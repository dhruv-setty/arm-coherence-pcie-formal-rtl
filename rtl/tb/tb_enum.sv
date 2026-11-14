// Enumeration as root complex software performs it, against four device slots
// on bus 0. Slots 1 and 3 hold endpoints with different BAR sizes; empty slots
// return all ones for Vendor ID. The testbench discovers devices, sizes each
// BAR, assigns naturally aligned addresses from a 32 bit and a 64 bit window,
// enables Memory Space and Bus Master, and checks the result.
module tb_enum;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        v [4];
  logic        we;
  logic [3:0]  rg;
  logic [31:0] wd;
  logic [31:0] rd [4];
  logic        mse [4], bme [4];
  logic [31:0] b0 [4];
  logic [63:0] b2 [4];
  int errors = 0;
  int found = 0;

  cfg_space #(.DEVICE_ID(16'h0011), .BAR0_SIZE(4096),  .BAR2_SIZE(1 << 20)) d1 (
    .clk, .rst_n, .cfg_valid(v[1]), .cfg_we(we), .cfg_reg(rg), .cfg_wdata(wd), .cfg_rdata(rd[1]),
    .mem_space_en(mse[1]), .bus_master_en(bme[1]), .bar0_base(b0[1]), .bar2_base(b2[1]));
  cfg_space #(.DEVICE_ID(16'h0033), .BAR0_SIZE(65536), .BAR2_SIZE(1 << 24)) d3 (
    .clk, .rst_n, .cfg_valid(v[3]), .cfg_we(we), .cfg_reg(rg), .cfg_wdata(wd), .cfg_rdata(rd[3]),
    .mem_space_en(mse[3]), .bus_master_en(bme[3]), .bar0_base(b0[3]), .bar2_base(b2[3]));
  assign rd[0] = 32'hFFFF_FFFF;
  assign rd[2] = 32'hFFFF_FFFF;

  task automatic cfg_wr(input int dev, input logic [3:0] r, input logic [31:0] d);
    @(negedge clk); for (int i = 0; i < 4; i++) v[i] = (i == dev); we = 1; rg = r; wd = d;
    @(negedge clk); for (int i = 0; i < 4; i++) v[i] = 0; we = 0;
  endtask

  task automatic cfg_rd(input int dev, input logic [3:0] r, output logic [31:0] d);
    @(negedge clk); rg = r; we = 0; #1 d = rd[dev];
  endtask

  task automatic check(input string name, input logic cond);
    if (!cond) begin errors++; $display("FAIL %s", name); end
  endtask

  function automatic logic [63:0] align_up(input logic [63:0] a, input logic [63:0] sz);
    return (a + sz - 1) & ~(sz - 1);
  endfunction

  initial begin
    logic [31:0] id, lo, hi, orig;
    logic [63:0] sz0, sz2, win32, win64;
    for (int i = 0; i < 4; i++) v[i] = 0;
    we = 0; rg = 0; wd = 0;
    win32 = 64'h0000_0000_C000_0000;
    win64 = 64'h0000_0040_0000_0000;
    #22 rst_n = 1;

    for (int dev = 0; dev < 4; dev++) begin
      cfg_rd(dev, 0, id);
      if (id[15:0] != 16'hFFFF) begin
      found++;

      // BAR0: 32 bit memory
      cfg_rd(dev, 4, orig);
      cfg_wr(dev, 4, 32'hFFFF_FFFF);
      cfg_rd(dev, 4, lo);
      check("bar0 is memory", lo[0] == 1'b0);
      check("bar0 is 32 bit", lo[2:1] == 2'b00);
      sz0 = 64'(~(lo & 32'hFFFF_FFF0)) + 64'd1;
      sz0 = sz0 & 64'hFFFF_FFFF;
      cfg_wr(dev, 4, orig);

      // BAR2/BAR3: 64 bit prefetchable memory, sized as a pair
      cfg_wr(dev, 6, 32'hFFFF_FFFF);
      cfg_wr(dev, 7, 32'hFFFF_FFFF);
      cfg_rd(dev, 6, lo);
      cfg_rd(dev, 7, hi);
      check("bar2 is 64 bit", lo[2:1] == 2'b10);
      check("bar2 prefetchable", lo[3] == 1'b1);
      sz2 = ~{hi, lo & 32'hFFFF_FFF0} + 64'd1;

      win32 = align_up(win32, sz0);
      cfg_wr(dev, 4, win32[31:0]);
      win64 = align_up(win64, sz2);
      cfg_wr(dev, 6, win64[31:0]);
      cfg_wr(dev, 7, win64[63:32]);
      cfg_wr(dev, 1, 32'h0000_0006);

      $display("bus 0 dev %0d: vendor %h device %h  BAR0 %0d KiB at %h  BAR2 %0d KiB at %h",
               dev, id[15:0], id[31:16], sz0 / 1024, win32[31:0], sz2 / 1024, win64);
      win32 += sz0;
      win64 += sz2;
      end
    end

    check("two devices found", found == 2);
    check("d1 sizes", b0[1] == 32'hC000_0000 && b2[1] == 64'h0000_0040_0000_0000);
    check("d3 bar0 aligned to 64 KiB", b0[3] == 32'hC001_0000);
    check("d3 bar2 aligned to 16 MiB", b2[3] == 64'h0000_0040_0100_0000);
    check("d1 enabled", mse[1] && bme[1]);
    check("d3 enabled", mse[3] && bme[3]);

    if (errors == 0) $display("PASS tb_enum");
    else $fatal(1, "%0d check(s) failed", errors);
    $finish;
  end
endmodule
