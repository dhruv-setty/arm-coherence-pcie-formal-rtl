// PCIe Type 0 configuration header for one function (endpoint).
// Dword addressed (reg_idx 0..15). Implements the header fields enumeration
// software touches: IDs, Command and Status, Class Code, Header Type, three
// BAR slots, Subsystem IDs and Interrupt Pin and Line.
//   BAR0       32 bit memory, non prefetchable, size BAR0_SIZE (power of two, >= 16)
//   BAR2/BAR3  64 bit memory, prefetchable, size BAR2_SIZE (power of two, >= 16)
// Sizing follows the usual protocol: software writes all ones, reads back,
// and the read only zero low bits reveal the size.
module cfg_space #(
  parameter logic [15:0] VENDOR_ID = 16'hABCD,   // placeholder, not a PCI-SIG assignment
  parameter logic [15:0] DEVICE_ID = 16'h0001,
  parameter logic [23:0] CLASS_CODE = 24'h088000, // base 08 (system peripheral), sub 80 (other)
  parameter logic [7:0]  REVISION = 8'h01,
  parameter int unsigned BAR0_SIZE = 4096,
  parameter int unsigned BAR2_SIZE = 1 << 20
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cfg_valid,
  input  logic        cfg_we,
  input  logic [3:0]  cfg_reg,
  input  logic [31:0] cfg_wdata,
  output logic [31:0] cfg_rdata,
  output logic        mem_space_en,
  output logic        bus_master_en,
  output logic [31:0] bar0_base,
  output logic [63:0] bar2_base
);
  localparam logic [31:0] BAR0_MASK = ~(BAR0_SIZE - 1);
  localparam logic [63:0] BAR2_MASK = ~(64'(BAR2_SIZE) - 64'd1);

  logic [15:0] command;
  logic [31:0] bar0;
  logic [63:0] bar2;
  logic [7:0]  int_line;

  assign mem_space_en  = command[1];
  assign bus_master_en = command[2];
  assign bar0_base     = bar0 & BAR0_MASK;
  assign bar2_base     = bar2 & BAR2_MASK;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      command  <= '0;
      bar0     <= '0;
      bar2     <= '0;
      int_line <= 8'hFF;
    end else if (cfg_valid && cfg_we) begin
      case (cfg_reg)
        4'd1:  command  <= cfg_wdata[15:0] & 16'h0406; // Memory Space, Bus Master, INTx Disable
        4'd4:  bar0     <= cfg_wdata & BAR0_MASK;
        4'd6:  bar2[31:0]  <= cfg_wdata & BAR2_MASK[31:0];
        4'd7:  bar2[63:32] <= cfg_wdata & BAR2_MASK[63:32];
        4'd15: int_line <= cfg_wdata[7:0];
        default: ;
      endcase
    end
  end

  always_comb begin
    case (cfg_reg)
      4'd0:  cfg_rdata = {DEVICE_ID, VENDOR_ID};
      4'd1:  cfg_rdata = {16'h0000, command};
      4'd2:  cfg_rdata = {CLASS_CODE, REVISION};
      4'd3:  cfg_rdata = 32'h0000_0000;                          // Header Type 0, single function
      4'd4:  cfg_rdata = {bar0[31:4], 4'b0000};                   // memory, 32 bit, non prefetchable
      4'd6:  cfg_rdata = {bar2[31:4], 4'b1100};                   // memory, 64 bit, prefetchable
      4'd7:  cfg_rdata = bar2[63:32];
      4'd11: cfg_rdata = {DEVICE_ID, VENDOR_ID};                  // Subsystem ID, Subsystem Vendor ID
      4'd15: cfg_rdata = {16'h0000, 8'h01, int_line};             // Interrupt Pin INTA
      default: cfg_rdata = 32'h0000_0000;
    endcase
  end
endmodule
