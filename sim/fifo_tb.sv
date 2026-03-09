`timescale 1ns / 1ps

module fifo_tb;
  parameter DATA_WIDTH = 64;  // System address bus width

  logic aclk = 0;
  logic aresetn;
  logic [(DATA_WIDTH-1):0] data_in;
  logic push;
  logic pop;
  logic fifo_full;
  logic [(DATA_WIDTH-1):0] data_out;
  logic fifo_empty;

  // Clock generation (100MHz)
  always #5 aclk = ~aclk;


  // logic [10:0] mem_test[99:0];
  // logic mem_test[99:0];

  axi_fifo #(
      .WIDTH(DATA_WIDTH),
      .DEPTH(4)
  ) fifo_i (
      .aclk(aclk),
      .aresetn(aresetn),

      .data_in(data_in),
      .push(push),
      .full(fifo_full),

      .data_out(data_out),
      .pop(pop),
      .empty(fifo_empty)
  );

  // Simple integrity check in Icarus
  logic [(DATA_WIDTH-1):0] local_queue[$];  // SystemVerilog queue

  always @(posedge aclk) begin
    if (pop && !fifo_full) local_queue.push_back(data_in);
    if (push && !fifo_empty) begin
      logic [(DATA_WIDTH-1):0] expected;  // Standard declaration
      expected = local_queue.pop_front();
      if (data_out !== expected)
        $display("ERROR: Mismatch! Got %h, Expected %h", data_out, expected);
    end
  end

  initial begin
    aresetn = 0;
    push = 0;
    pop = 0;

    #10 aresetn = 1;

    push_word(64'h41234567890abcd1);
    push_word(64'h41234567890abcd2);
    push_word(64'h41234567890abcd3);
    pop <= 1;
    push_word(64'h41234567890abcd4);
    push_word(64'h41234567890abcd5);
    push_word(64'h41234567890abcd5);
    pop <= 0;
    push_word(64'h41234567890abcd6);
    push_word(64'h01234567890abcd7);

    push_word(64'h01234567890abcd8);
    push_word(64'h01234567890abcd9);
    push_word(64'h01234567890abcda);

    for (int i = 0; i < 8; i++) begin
      pop_word();
    end

    #50 $finish;
  end

  task push_word(input [(DATA_WIDTH-1):0] b);
    @(posedge aclk);
    data_in <= b;  // Use <= instead of =
    push    <= 1;  // Use <= instead of =
    @(posedge aclk);  // Wait for the NEXT edge to bring it low
    push <= 0;
  endtask

  task pop_word();
    @(posedge aclk);
    pop <= 1;
    @(posedge aclk);
    pop <= 0;
  endtask

endmodule
