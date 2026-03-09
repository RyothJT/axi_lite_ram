`timescale 1ns / 1ps

module example_tb;
    logic clk = 0;
    logic rst_n;
    logic [7:0] data_in;
    logic valid_in;
    logic [7:0] data_out;
    logic [7:0] count_out;
    logic valid_out;

    // Clock generation (100MHz)
    always #5 clk = ~clk;

    rle_compressor dut (.*);

    initial begin
        // Initialize
        rst_n = 0;
        valid_in = 0;
        data_in = 0;

        #20 rst_n = 1;

        // Feed data: AAAABBC
        send_byte(8'h41); // A
        send_byte(8'h41); // A
        send_byte(8'h41); // A
        send_byte(8'h41); // A
        send_byte(8'h42); // B
        send_byte(8'h42); // B
        send_byte(8'h43); // C
        send_byte(8'h00); // Flush last byte

        #50 $finish;
    end

    task send_byte(input [7:0] b);
        @(posedge clk);
        data_in = b;
        valid_in = 1;
        #1; // Small delay for waveform readability
    endtask

endmodule
