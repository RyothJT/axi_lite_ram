
module axi_generic_fifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 16  // Must be a power of 2
)(
    input  logic             aclk,
    input  logic             aresetn,
    // Write Port (Push)
    input  logic [WIDTH-1:0] data_in,
    input  logic             push,
    output logic             full,
    // Read Port (Pop)
    output logic [WIDTH-1:0] data_out,
    input  logic             pop,
    output logic             empty
);

    // 1. Calculate pointer width: log2(DEPTH) + 1 for the wrap bit
    localparam PTR_W = $clog2(DEPTH) + 1;

    // 2. Storage Array
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // 3. Pointers
    logic [PTR_W-1:0] wr_ptr, rd_ptr;

    // 4. Status Flags
    // Empty: All bits match
    assign empty = (wr_ptr == rd_ptr);
    // Full: Index bits match, but MSB (wrap bit) is different
    assign full  = (wr_ptr[PTR_W-2:0] == rd_ptr[PTR_W-2:0]) && 
                   (wr_ptr[PTR_W-1]   != rd_ptr[PTR_W-1]);

    // 5. Read/Write Logic
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            // Write when pushed and not full
            if (push && !full) begin
                mem[wr_ptr[PTR_W-2:0]] <= data_in;
                wr_ptr <= wr_ptr + 1'b1;
            end
            // Read when popped and not empty
            if (pop && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    // Continuous assignment for output data (pointing to current head)
    assign data_out = mem[rd_ptr[PTR_W-2:0]];

endmodule


module axi_slave_ram#
(
  parameter DATA_WIDTH   = 32,
  parameter STRB_WIDTH   = DATA_WIDTH / 8,
  parameter ADDR_WIDTH   = 8,
  parameter MAX_BURST    = 16;
  parameter RAM_DEPTH    = 10;
)(
  // Global signals
  input                         aclk,
  input                         aresetn,

  // Write address channel
  input [ADDR_WIDTH - 1 : 0]    awaddr,
  // input [7:0]                   awlen,
  // input [2:0]                   awsize,
  // input [1:0]                   awburst,
  input                         awvalid,
  output                        awready,

  // Write data channel
  input [DATA_WIDTH - 1 : 0]    wdata,
  input [STRB_WIDTH - 1 : 0]    wstrb,
  input                         wlast,
  input                         wvalid,
  output                        wready,

  // Write response channel
  output [1:0]                  bresp,
  output                        bvalid,
  input                         bready,

  // Read address channel
  input [ADDR_WIDTH - 1 : 0]    araddr,
  // input [7:0]                   arlen,
  // input [2:0]                   arsize,
  // input [1:0]                   arburst,
  input                         arvalid,
  output                        arready,

  // Read data channel
  output [DATA_WIDTH - 1 : 0]   rdata,
  output [1:0]                  rresp,
  output                        rlast,
  output                        rvalid,
  input                         rready
);


logic [DATA_WIDTH-1:0] ram [0:(RAM_DEPTH**2)-1]; 

assign aw_beat  = s_axi_awvalid   && s_axi_awready;
assign w_beat   = s_axi_wvalid    && s_axi_wready;
assign bw_beat  = s_axi_bwvalid   && s_axi_bwready;
assign ar_beat  = s_axi_arvalid   && s_axi_arready;
assign r_beat   = s_axi_rvalid    && s_axi_rready;

logic ram_write_ready;
assign ram_write_ready = !aw_empty && !w_empty;

axi_generic_fifo aw_fifo #
(
  WIDTH = ADDR_WIDTH,
  DEPTH = 4;
)(
  .aclk(aclk),
  .aresetn(aresetn),

  .data_in(awaddr),
  .push(aw_beat),
  .full(aw_fifo_full),

  .data_out(write_address),
  .pop(ram_write_ready),
  .empty(aw_empty);
)

axi_generic_fifo w_fifo #
(
  WIDTH = DATA_WIDTH + STRB_WIDTH + 1,
  DEPTH = (MAX_BURST * 2) - 1;
)(
  .aclk(aclk),
  .aresetn(aresetn),
  .data_in({wdata, wstrb, wvalid}),

  .data_in(waddr),
  .push(w_beat),
  .full(w_fifo_full),

  .data_out(write_data),
  .pop(ram_write_ready),
  .empty(w_empty);
)

axi_generic_fifo bw_fifo #
(
  WIDTH = DATA_WIDTH + STRB_WIDTH + 1 + 1,
  DEPTH = (MAX_BURST * 2) - 1;
)(
  .aclk(aclk),
  .aresetn(aresetn),
  .data_in({bresp, bvalid, bready}),

  .data_in(waddr),
  .push(w_beat),
  .full(w_fifo_full),

  .data_out(write_data),
  .pop(ram_write_ready),
  .empty(w_empty);
)

// 1. AW FIFO (Stores the Write Address + Control Bits)
logic [ADDR_WIDTH-1:0] aw_fifo [0:3]; 
localparam AW_PTR_WIDTH = $clog2(ADDR_DEPTH) + 1;
logic [AW_PTR_WIDTH-1:0] aw_wr_ptr, aw_rd_ptr;

// 2. W FIFO (Stores Write Data + Byte Strobes)
logic [DATA_WIDTH + STRB_WIDTH - 1 : 0] w_fifo [0:(MAX_BURST * 2) - 1];
logic [4:0] w_wr_ptr, w_rd_ptr;

// 3. B FIFO (Write Response)
logic [1:0] b_fifo [0:3];
logic [3:0] b_wr_ptr, b_rd_ptr;

// 4. AR FIFO (Stores the Read Address)
logic [ADDR_WIDTH-1:0] ar_fifo [0:3];
logic [3:0] ar_wr_ptr, ar_rd_ptr;

// 5. R FIFO (Stores the Read Data + Response Status)
logic [DATA_WIDTH + 1 : 0] r_fifo [0:MAX_BURST - 1];
logic [0:4] r_wr_ptr, r_rd_ptr;



always_ff @(posedge aclk) begin
  // Write address control
  if (areset == 1) begin
    
  end
  if (awvalid && awready) begin
    // Beat hit
    aw_fifo[aw_wr_ptr] <= 
    
  end
end

