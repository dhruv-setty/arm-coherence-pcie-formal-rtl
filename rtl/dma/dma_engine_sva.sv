// Concurrent assertions for the descriptor handoff in dma_engine, bound into
// every instance. Checked in simulation by Verilator with --assert while the
// benchmark sweep runs; a formal run with SymbiYosys is the next step.
module dma_engine_sva #(parameter int MAX_RD = 8, localparam int CW = $clog2(MAX_RD + 1)) (
  input logic          clk,
  input logic          rst_n,
  input logic [2:0]    state,
  input logic          mem_req_valid,
  input logic          mem_req_we,
  input logic [63:0]   mem_req_addr,
  input logic [63:0]   mem_req_wdata,
  input logic          fire,
  input logic [63:0]   d_w2,
  input logic [15:0]   head,
  input logic [31:0]   done_cnt,
  input logic [CW-1:0] outstanding,
  input logic [CW-1:0] f_cnt
);
  localparam logic [2:0] S_COPY = 3'd4, S_WB2 = 3'd5, S_WB3 = 3'd6;

  // Every beat is a naturally aligned 8 byte access.
  a_aligned: assert property (@(posedge clk) disable iff (!rst_n)
    mem_req_valid |-> mem_req_addr[2:0] == 3'b000);

  // Reads in flight plus buffered data never exceed the FIFO.
  a_no_overflow: assert property (@(posedge clk) disable iff (!rst_n)
    outstanding + f_cnt <= CW'(MAX_RD));

  // Data moves only for a descriptor the driver handed over.
  a_copy_needs_own: assert property (@(posedge clk) disable iff (!rst_n)
    state == S_COPY |-> d_w2[32]);

  // The control word written back gives ownership to the driver.
  a_wb_clears_own: assert property (@(posedge clk) disable iff (!rst_n)
    (state == S_WB2 && mem_req_valid) |-> mem_req_we && !mem_req_wdata[32]);

  // The DONE writeback and the HEAD and DONE_CNT updates happen together.
  a_head_with_done: assert property (@(posedge clk) disable iff (!rst_n)
    (state == S_WB3 && fire) |=> head == $past(head) + 16'd1 && done_cnt == $past(done_cnt) + 32'd1);

  // HEAD never moves except on that writeback.
  a_head_stable: assert property (@(posedge clk) disable iff (!rst_n)
    !(state == S_WB3 && fire) |=> head == $past(head));
endmodule

bind dma_engine dma_engine_sva #(.MAX_RD(MAX_RD)) u_sva (.*);
