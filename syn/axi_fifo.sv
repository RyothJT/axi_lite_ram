`timescale 1ns / 1ps

module axi_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 16   // Must be a power of 2
) (
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
    logic [WIDTH-1:0] mem[DEPTH-1];

    // 3. Pointers
    logic [PTR_W-1:0] wr_ptr, rd_ptr;

    // 4. Status Flags
    // Empty: All bits match
    assign empty = (wr_ptr == rd_ptr);
    // Full: Index bits match, but MSB (wrap bit) is different
    assign full  = (wr_ptr[PTR_W-2:0] == rd_ptr[PTR_W-2:0]) && (wr_ptr[PTR_W-1] != rd_ptr[PTR_W-1]);

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

