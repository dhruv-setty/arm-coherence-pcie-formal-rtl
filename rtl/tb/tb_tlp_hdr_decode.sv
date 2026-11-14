module tb_tlp_hdr_decode;
  logic [127:0] hdr;
  logic is_4dw, has_data, is_mem_rd, is_mem_wr, is_cpl, td, ep, be_malformed;
  logic [2:0] tc, attr;
  logic [10:0] len_dw;
  logic [15:0] req_id;
  logic [7:0] tag;
  logic [3:0] first_be, last_be;
  logic [63:0] addr;
  int errors = 0;

  tlp_hdr_decode dut (.*);

  task automatic check(input string name, input logic cond);
    if (!cond) begin errors++; $display("FAIL %s", name); end
  endtask

  initial begin
    // 3DW MemRd, 1 DW, TC0, RO set, req 01:00.0, tag 0x2A, BE 0000/1111, addr 0x1000_0040
    hdr = {8'h00, 8'h00, 8'h20, 8'h01,  16'h0100, 8'h2A, 8'h0F,  32'h1000_0040, 32'h0};
    #1;
    check("mrd3 type", is_mem_rd && !is_mem_wr && !is_4dw && !has_data);
    check("mrd3 len",  len_dw == 11'd1);
    check("mrd3 attr", attr == 3'b010);
    check("mrd3 id",   req_id == 16'h0100 && tag == 8'h2A);
    check("mrd3 addr", addr == 64'h0000_0000_1000_0040);
    check("mrd3 be",   !be_malformed);

    // 4DW MemWr, 16 DW, TC2, addr 0x0000_0001_8000_0100
    hdr = {8'h60, 8'h20, 8'h00, 8'h10,  16'h0200, 8'h05, 8'hFF,  32'h0000_0001, 32'h8000_0100};
    #1;
    check("mwr4 type", is_mem_wr && is_4dw && has_data);
    check("mwr4 tc",   tc == 3'd2);
    check("mwr4 len",  len_dw == 11'd16);
    check("mwr4 addr", addr == 64'h0000_0001_8000_0100);
    check("mwr4 be",   !be_malformed);

    // Length field 0 encodes 1024 DW
    hdr = {8'h40, 8'h00, 8'h00, 8'h00,  16'h0300, 8'h00, 8'hFF,  32'h2000_0000, 32'h0};
    #1;
    check("len1024", len_dw == 11'd1024 && is_mem_wr);

    // CplD
    hdr = {8'h4A, 8'h00, 8'h00, 8'h01,  32'h0, 32'h0, 32'h0};
    #1;
    check("cpld", is_cpl && has_data && !is_mem_rd && !is_mem_wr);

    // Malformed: 1 DW request with nonzero Last DW BE
    hdr = {8'h00, 8'h00, 8'h00, 8'h01,  16'h0100, 8'h01, 8'hFF,  32'h1000_0000, 32'h0};
    #1;
    check("bad be 1dw", be_malformed);

    // Malformed: 4 DW request with Last DW BE = 0000
    hdr = {8'h40, 8'h00, 8'h00, 8'h04,  16'h0100, 8'h01, 8'h0F,  32'h1000_0000, 32'h0};
    #1;
    check("bad be ndw", be_malformed);

    if (errors == 0) $display("PASS tb_tlp_hdr_decode");
    else $fatal(1, "%0d check(s) failed", errors);
    $finish;
  end
endmodule
