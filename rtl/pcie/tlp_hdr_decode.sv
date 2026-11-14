// PCIe TLP header decoder for memory requests and completions.
// hdr holds DW0..DW3 with DW0 in [127:96] and byte 0 of each DW in its top byte,
// matching the byte order in which a TLP header is transmitted.
// Field positions follow the request and completion header layouts in the
// PCIe Base Specification, Transaction Layer chapter.
module tlp_hdr_decode (
  input  logic [127:0] hdr,
  output logic         is_4dw,
  output logic         has_data,
  output logic         is_mem_rd,
  output logic         is_mem_wr,
  output logic         is_cpl,
  output logic [2:0]   tc,
  output logic [2:0]   attr,      // {ID-Based Ordering, Relaxed Ordering, No Snoop}
  output logic         td,
  output logic         ep,
  output logic [10:0]  len_dw,    // 1..1024; an encoded 0 means 1024
  output logic [15:0]  req_id,
  output logic [7:0]   tag,
  output logic [3:0]   first_be,
  output logic [3:0]   last_be,
  output logic [63:0]  addr,
  output logic         be_malformed
);
  /* verilator lint_off UNUSEDSIGNAL */
  // Reserved, TH, LN and PH bits are not decoded here.
  logic [31:0] dw0, dw1, dw2, dw3;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [2:0]  fmt;
  logic [4:0]  typ;
  logic [9:0]  len_raw;

  assign dw0 = hdr[127:96];
  assign dw1 = hdr[95:64];
  assign dw2 = hdr[63:32];
  assign dw3 = hdr[31:0];

  assign fmt      = dw0[31:29];
  assign typ      = dw0[28:24];
  assign tc       = dw0[22:20];
  assign attr     = {dw0[18], dw0[13:12]};
  assign td       = dw0[15];
  assign ep       = dw0[14];
  assign len_raw  = dw0[9:0];
  assign len_dw   = (len_raw == 10'd0) ? 11'd1024 : {1'b0, len_raw};

  assign is_4dw   = fmt[0];
  assign has_data = fmt[1];

  // Fmt 100 marks a TLP Prefix, not a request header.
  assign is_mem_rd = !fmt[2] && (typ == 5'b00000) && !has_data;
  assign is_mem_wr = !fmt[2] && (typ == 5'b00000) &&  has_data;
  assign is_cpl    = !fmt[2] && (typ == 5'b01010);

  assign req_id   = dw1[31:16];
  assign tag      = dw1[15:8];
  assign last_be  = dw1[7:4];
  assign first_be = dw1[3:0];

  // 3DW carries addr[31:2] in DW2; 4DW carries addr[63:32] in DW2 and addr[31:2] in DW3.
  assign addr = is_4dw ? {dw2, dw3[31:2], 2'b00} : {32'd0, dw2[31:2], 2'b00};

  // Byte enable rules for memory requests: a 1 DW request has Last DW BE = 0000,
  // a longer request has nonzero First and Last DW BE.
  assign be_malformed = (is_mem_rd || is_mem_wr) &&
                        ((len_dw == 11'd1) ? (last_be != 4'b0000)
                                           : (last_be == 4'b0000 || first_be == 4'b0000));
endmodule
