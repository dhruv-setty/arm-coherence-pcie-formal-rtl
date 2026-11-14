// Descriptor ring DMA engine (memory to memory copy).
//
// Registers (32 bit, byte offsets on the reg port):
//   0x00 CTRL       bit0 enable, bit1 interrupt enable
//   0x04 STATUS     bit0 busy (RO), bit1 interrupt pending (write 1 to clear)
//   0x08 RING_LO    ring base, low 32 bits (32 byte aligned)
//   0x0C RING_HI    ring base, high 32 bits
//   0x10 RING_SIZE  number of descriptors, power of two
//   0x14 TAIL       doorbell: index one past the last descriptor the driver posted
//   0x18 HEAD       index of the next descriptor the engine will process (RO)
//   0x1C DONE_CNT   descriptors completed since reset (RO)
//
// Descriptor, 32 bytes, four 64 bit words in host memory:
//   word0 source address      word1 destination address
//   word2 [31:0] length in bytes (multiple of 8), [32] OWN (device owns), [33] IRQ on completion
//   word3 [0] DONE, written back by the engine
// The engine clears OWN and sets DONE when a copy finishes, then advances HEAD.
//
// Memory port: one request per cycle when ready. Writes are posted (no response),
// like PCIe memory writes; reads return rsp_valid with data, in order.
// Up to MAX_RD reads may be outstanding, so copy throughput hides read latency.
module dma_engine #(
  parameter int MAX_RD = 8
) (
  input  logic        clk,
  input  logic        rst_n,
  // register port
  input  logic        reg_valid,
  input  logic        reg_we,
  input  logic [7:0]  reg_addr,
  input  logic [31:0] reg_wdata,
  output logic [31:0] reg_rdata,
  // memory request
  output logic        mem_req_valid,
  input  logic        mem_req_ready,
  output logic        mem_req_we,
  output logic [63:0] mem_req_addr,
  output logic [63:0] mem_req_wdata,
  // memory read response
  input  logic        mem_rsp_valid,
  input  logic [63:0] mem_rsp_rdata,
  output logic        irq
);
  localparam int CW = $clog2(MAX_RD + 1);

  typedef enum logic [2:0] {
    S_IDLE, S_FETCH, S_FETCH_WAIT, S_CHECK, S_COPY, S_WB2, S_WB3
  } state_t;
  state_t state;

  logic        en, irq_en, irq_pend;
  logic [63:0] ring_base;
  logic [15:0] ring_size, tail, head;
  logic [31:0] done_cnt;

  // current descriptor
  logic [63:0] d_src, d_dst, d_w2;
  logic [1:0]  fetch_issued, fetch_got;

  // copy bookkeeping, in 8 byte words
  logic [28:0] words, rd_issued, wr_done;
  logic [CW-1:0] outstanding;
  // small FIFO of read data waiting to be written
  logic [63:0] fifo [MAX_RD];
  logic [$clog2(MAX_RD)-1:0] f_wp, f_rp;
  logic [CW-1:0] f_cnt;

  logic [15:0] idx_mask;
  assign idx_mask = ring_size - 16'd1;
  logic [63:0] desc_addr;
  assign desc_addr = ring_base + {43'd0, head & idx_mask, 5'd0};

  assign irq = irq_pend & irq_en;

  // register reads
  always_comb begin
    case (reg_addr)
      8'h00: reg_rdata = {30'd0, irq_en, en};
      8'h04: reg_rdata = {30'd0, irq_pend, state != S_IDLE};
      8'h08: reg_rdata = ring_base[31:0];
      8'h0C: reg_rdata = ring_base[63:32];
      8'h10: reg_rdata = {16'd0, ring_size};
      8'h14: reg_rdata = {16'd0, tail};
      8'h18: reg_rdata = {16'd0, head};
      8'h1C: reg_rdata = done_cnt;
      default: reg_rdata = 32'd0;
    endcase
  end

  // memory request mux
  logic want_rd, want_wr;
  assign want_rd = (state == S_COPY) && (rd_issued != words) &&
                   (outstanding + f_cnt < CW'(MAX_RD));
  assign want_wr = (state == S_COPY) && (f_cnt != 0);

  always_comb begin
    mem_req_valid = 1'b0;
    mem_req_we    = 1'b0;
    mem_req_addr  = '0;
    mem_req_wdata = '0;
    case (state)
      S_FETCH: begin
        mem_req_valid = 1'b1;
        mem_req_addr  = desc_addr + {59'd0, fetch_issued, 3'd0};
      end
      S_COPY: begin
        if (want_wr) begin            // drain first: keeps the FIFO from filling
          mem_req_valid = 1'b1;
          mem_req_we    = 1'b1;
          mem_req_addr  = d_dst + {32'd0, wr_done, 3'd0};
          mem_req_wdata = fifo[f_rp];
        end else if (want_rd) begin
          mem_req_valid = 1'b1;
          mem_req_addr  = d_src + {32'd0, rd_issued, 3'd0};
        end
      end
      S_WB2: begin
        mem_req_valid = 1'b1;
        mem_req_we    = 1'b1;
        mem_req_addr  = desc_addr + 64'd16;
        mem_req_wdata = d_w2 & ~(64'd1 << 32);   // clear OWN
      end
      S_WB3: begin
        mem_req_valid = 1'b1;
        mem_req_we    = 1'b1;
        mem_req_addr  = desc_addr + 64'd24;
        mem_req_wdata = 64'd1;                   // DONE
      end
      default: ;
    endcase
  end

  logic fire;
  assign fire = mem_req_valid && mem_req_ready;
  logic fire_rd, fire_wr;
  assign fire_rd = fire && !mem_req_we && state == S_COPY;
  assign fire_wr = fire &&  mem_req_we && state == S_COPY;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      en <= 0; irq_en <= 0; irq_pend <= 0;
      ring_base <= '0; ring_size <= 16'd1; tail <= '0; head <= '0; done_cnt <= '0;
      fetch_issued <= '0; fetch_got <= '0;
      words <= '0; rd_issued <= '0; wr_done <= '0; outstanding <= '0;
      f_wp <= '0; f_rp <= '0; f_cnt <= '0;
      d_src <= '0; d_dst <= '0; d_w2 <= '0;
    end else begin
      // register writes
      if (reg_valid && reg_we) begin
        case (reg_addr)
          8'h00: begin en <= reg_wdata[0]; irq_en <= reg_wdata[1]; end
          8'h04: if (reg_wdata[1]) irq_pend <= 1'b0;
          8'h08: ring_base[31:0]  <= {reg_wdata[31:5], 5'd0};
          8'h0C: ring_base[63:32] <= reg_wdata;
          8'h10: ring_size <= reg_wdata[15:0];
          8'h14: tail <= reg_wdata[15:0];
          default: ;
        endcase
      end

      case (state)
        S_IDLE: if (en && head != tail) begin
          fetch_issued <= '0; fetch_got <= '0;
          state <= S_FETCH;
        end
        S_FETCH: begin
          // descriptor words 0..2 are needed; word3 is write only
          if (fire) begin
            fetch_issued <= fetch_issued + 2'd1;
            if (fetch_issued == 2'd2) state <= S_FETCH_WAIT;
          end
        end
        S_FETCH_WAIT: if (fetch_got == 2'd3) state <= S_CHECK;
        S_CHECK: begin
          if (!d_w2[32]) begin
            state <= S_IDLE;                // driver has not handed it over: stop
          end else begin
            words <= d_w2[31:3];
            rd_issued <= '0; wr_done <= '0;
            state <= (d_w2[31:3] == 0) ? S_WB2 : S_COPY;
          end
        end
        S_COPY: if (wr_done == words && outstanding == 0) state <= S_WB2;
        S_WB2: if (fire) state <= S_WB3;
        // HEAD, DONE_CNT and the interrupt update in the same cycle as the DONE
        // writeback, so a driver that sees DONE in memory never reads a stale count.
        S_WB3: if (fire) begin
          head <= head + 16'd1;
          done_cnt <= done_cnt + 32'd1;
          if (d_w2[33]) irq_pend <= 1'b1;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase

      // read responses: descriptor words while fetching, data while copying
      if (mem_rsp_valid && (state == S_FETCH || state == S_FETCH_WAIT)) begin
        case (fetch_got)
          2'd0: d_src <= mem_rsp_rdata;
          2'd1: d_dst <= mem_rsp_rdata;
          default: d_w2 <= mem_rsp_rdata;
        endcase
        fetch_got <= fetch_got + 2'd1;
      end

      if (state == S_COPY) begin
        if (fire_rd) rd_issued <= rd_issued + 29'd1;
        if (fire_wr) wr_done <= wr_done + 29'd1;
        if (mem_rsp_valid) begin
          fifo[f_wp] <= mem_rsp_rdata;
          f_wp <= f_wp + 1'b1;
        end
        if (fire_wr) f_rp <= f_rp + 1'b1;
        f_cnt <= f_cnt + CW'(mem_rsp_valid) - CW'(fire_wr);
        outstanding <= outstanding + CW'(fire_rd) - CW'(mem_rsp_valid);
      end
    end
  end
endmodule
