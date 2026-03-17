module axi_lite_slave_ram #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 8,  // System address bus width
    parameter int RAM_DEPTH = 256,  // Must be power of 2 (e.g., 2^ADDR_WIDTH)
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) (
    // Global signals
    input logic aclk,
    input logic aresetn,

    // Write address channel
    input  logic [ADDR_WIDTH+1:0] awaddr,   // byte indexed
    input  logic                  awvalid,
    output logic                  awready,

    // Write data channel
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [STRB_WIDTH-1:0] wstrb,
    input  logic                  wvalid,
    output logic                  wready,

    // Write response channel
    output logic [1:0] bresp,
    output logic       bvalid,
    input  logic       bready,

    // Read address channel
    input  logic [ADDR_WIDTH+1:0] araddr,   // byte indexed
    input  logic                  arvalid,
    output logic                  arready,

    // Read data channel
    output logic [DATA_WIDTH-1:0] rdata,
    output logic [           1:0] rresp,
    output logic                  rvalid,
    input  logic                  rready
);
  // Local parameters
  parameter int RAM_ADDR_W = $clog2(RAM_DEPTH);

  //-----------------------------------------------------------------------
  // 1. Internal Handshake Signals (Beats)
  //-----------------------------------------------------------------------
  logic aw_beat, w_beat, b_beat, ar_beat, r_beat;

  assign aw_beat = awvalid && awready;
  assign w_beat  = wvalid && wready;
  assign b_beat  = bvalid && bready;
  assign ar_beat = arvalid && arready;
  assign r_beat  = rvalid && rready;

  //-----------------------------------------------------------------------
  // 2. FIFO Buffer Instantiations
  //-----------------------------------------------------------------------

  // Logic to trigger the RAM write when BOTH AW and W buffers have data
  logic aw_empty, w_empty;
  logic ram_write_ready;
  assign ram_write_ready = !aw_empty && !w_empty;

  logic [ADDR_WIDTH+1:0] write_addr_full;  // byte addressed
  logic [DATA_WIDTH-1:0] write_data_out;
  logic [STRB_WIDTH-1:0] write_strb_out;

  logic aw_fifo_full;
  logic w_fifo_full;
  logic ar_fifo_full;
  logic r_fifo_full;

  // AW FIFO
  axi_fifo #(
      .WIDTH(ADDR_WIDTH),
      .DEPTH(4)
  ) aw_fifo_i (
      .aclk(aclk),
      .aresetn(aresetn),

      .data_in(awaddr),
      .push(aw_beat),
      .full(aw_fifo_full),

      .data_out(write_addr_full),
      .pop(ram_write_ready),
      .empty(aw_empty)
  );

  // W FIFO
  axi_fifo #(
      .WIDTH(DATA_WIDTH + STRB_WIDTH),
      .DEPTH(4)
  ) w_fifo_i (
      .aclk(aclk),
      .aresetn(aresetn),

      .data_in({wstrb, wdata}),
      .push(w_beat),
      .full(w_fifo_full),

      .data_out({write_strb_out, write_data_out}),
      .pop(ram_write_ready),
      .empty(w_empty)
  );

  assign awready = !aw_fifo_full;
  assign wready  = !w_fifo_full;

  //-----------------------------------------------------------------------
  // 3. Main RAM Array & Write Logic
  //-----------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] ram[0:RAM_DEPTH-1];

  // Slice address to match RAM depth and ignore byte-offset (assuming 32-bit/4-byte)
  // For 32-bit data, we ignore bits [1:0]
  logic [RAM_ADDR_W-1:0] ram_write_idx;
  assign ram_write_idx = write_addr_full[RAM_ADDR_W+1 : 2];

  always_ff @(posedge aclk) begin
    if (ram_write_ready) begin
      // Simple byte-strobe handling
`ifndef SYNTHESIS
      $display("Time: %0t | Writing %h to %h", $time, write_data_out, ram_write_idx);
`endif
      for (int i = 0; i < STRB_WIDTH; i++) begin
        if (write_strb_out[i]) begin
          ram[ram_write_idx][i*8+:8] <= write_data_out[i*8+:8];
        end
      end
    end
  end

  //-----------------------------------------------------------------------
  // 4. Write Response (B) Logic
  //-----------------------------------------------------------------------
  // Push an "OKAY" response into the B-FIFO whenever a write happens
  logic b_fifo_full, b_fifo_empty;

  axi_fifo #(
      .WIDTH(2),
      .DEPTH(4)
  ) b_fifo_i (
      .aclk(aclk),
      .aresetn(aresetn),

      .data_in(2'b00),
      .push(ram_write_ready),
      .full(b_fifo_full),

      .data_out(bresp),
      .pop(bvalid && bready),
      .empty(b_fifo_empty)
  );

  assign bvalid = !b_fifo_empty;

  //-----------------------------------------------------------------------
  // 5. Read Address (AR) Logic
  //-----------------------------------------------------------------------

  // Logic to trigger the RAM read when BOTH AW and W buffers have data
  logic ar_empty;
  logic ram_read_ready;
  assign ram_read_ready = !ar_empty;

  logic [ADDR_WIDTH+1:0] read_addr_full;  // byte addressed
  logic [DATA_WIDTH-1:0] read_data_out;
  logic [STRB_WIDTH-1:0] read_strb_out;

  // AR FIFO
  axi_fifo #(
      .WIDTH(ADDR_WIDTH),
      .DEPTH(4)
  ) ar_fifo_i (
      .aclk(aclk),
      .aresetn(aresetn),

      .data_in(araddr),
      .push(ar_beat),
      .full(ar_fifo_full),

      .data_out(read_addr_full),
      .pop(ram_read_ready),
      .empty(ar_empty)
  );

  // We need to track if a read is "in flight" to drive rvalid correctly
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      rvalid <= 1'b0;
      rdata  <= '0;
      rresp  <= 2'b00;  // OKAY
    end else begin
      // If we are performing a read (RAM is ready and AR FIFO has data)
      if (ram_read_ready) begin
        rdata  <= ram[read_addr_full[RAM_ADDR_W+1 : 2]];
        rvalid <= 1'b1;
        rresp  <= 2'b00;
      end  // If the master accepted the data, clear rvalid
            else if (r_beat) begin
        rvalid <= 1'b0;
      end
    end
  end

  assign arready = !ar_fifo_full;

endmodule
