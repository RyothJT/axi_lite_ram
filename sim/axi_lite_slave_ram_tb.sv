`timescale 1ns / 1ps

module axi_lite_slave_ram_tb;
  parameter int DATA_WIDTH = 32;
  parameter int ADDR_WIDTH = 8;
  parameter int RAM_DEPTH = 256;
  parameter int STRB_WIDTH = DATA_WIDTH / 8;
  parameter int RAM_ADDR_W = $clog2(RAM_DEPTH);


  // Global signals
  logic aclk = 0;
  logic aresetn = 0;

  // Write address channel
  logic [ADDR_WIDTH-1:0] awaddr = 0;
  logic awvalid = 0;

  // Write data channel
  logic [DATA_WIDTH-1:0] wdata = 0;
  logic [STRB_WIDTH-1:0] wstrb = 0;
  logic wvalid = 0;

  // Write response channel
  logic bready = 0;

  // Read address channel
  logic [ADDR_WIDTH-1:0] araddr = 0;
  logic arvalid = 0;

  // Read data channel
  logic rready = 0;

  // Output signals
  logic awready;
  logic wready;
  logic [1:0] bresp;
  logic bvalid;
  logic arready;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0] rresp;
  logic rvalid;

  // Shadow memory: [Address] = Data
  // Using 32-bit logic for both key and value
  // Use a fixed array that matches your RAM depth
  logic [31:0] shadow_mem[RAM_DEPTH];
  bit shadow_written[RAM_DEPTH];

  initial begin
    for (int i = 0; i < RAM_DEPTH; i++) begin
      shadow_written[i] = 1'b0;
    end
  end

  int match_count = 0;
  int error_count = 0;
  logic [DATA_WIDTH-1:0] expected;

  // Output wires:
  axi_lite_slave_ram #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),  // System address bus width
      .RAM_DEPTH (RAM_DEPTH)    // Must be power of 2 (e.g., 2^ADDR_WIDTH)
  ) uut (
      // Global signals
      .aclk(aclk),
      .aresetn(aresetn),

      // Write address channel
      .awaddr (awaddr),
      .awvalid(awvalid),
      .awready(awready),

      // Write data channel
      .wdata (wdata),
      .wstrb (wstrb),
      .wvalid(wvalid),
      .wready(wready),

      // Write response channel
      .bresp (bresp),
      .bvalid(bvalid),
      .bready(bready),

      // Read address channel
      .araddr (araddr),
      .arvalid(arvalid),
      .arready(arready),

      // Read data channel
      .rdata (rdata),
      .rresp (rresp),
      .rvalid(rvalid),
      .rready(rready)
  );

  always #5 aclk = !aclk;

  initial begin
    #(10000);
    $display("TIMEOUT: Simulation forced to end at %0t", $time);
    $finish;
  end

  initial begin
    // --- Reset Sequence ---
    aresetn = 0;
    #20;
    aresetn = 1;
    #20;

    $display("--- Starting Extended Test Suite ---");
    // TEST 1: Boundary Check (First and Last Addressable Words)
    // Note: RAM_DEPTH-1 is the last index
    $display("\nTEST 1: Boundary Check");
    axi_write_wait(0, 32'hAAAA_BBBB);
    axi_write_wait((RAM_DEPTH - 1) << 2, 32'hCCCC_DDDD);
    axi_read_wait(0);
    axi_read_wait((RAM_DEPTH - 1) << 2);


    // TEST 2: Consecutive "Back-to-Back" Writes
    // This checks if your tasks correctly de-assert signals so the slave doesn't see a single long transaction.
    $display("\nTEST 2: Sequential Write/Read Block");
    for (int i = 5; i < 10; i++) begin
      axi_write_wait(i << 2, i * 32'h0101_0101);
    end
    for (int i = 5; i < 10; i++) begin
      axi_read_wait(i << 2);
    end

    // TEST 3: Data Pattern Stress (Walking 1s)
    // Checks if any bits in the DATA_WIDTH are cross-talking or stuck.
    $display("\nTEST 3: Walking Ones Pattern");
    for (int i = 0; i < 32; i++) begin
      axi_write_wait(15 << 2, (1 << i));
      axi_read_wait(15 << 2);
    end

    // TEST 4: Overwriting an existing address
    $display("\nTEST 4: Overwrite Check");
    axi_write_wait(20 << 2, 32'hDEAD_BEEF);
    axi_read_wait(20 << 2);
    axi_write_wait(20 << 2, 32'hCAFE_BABE);
    axi_read_wait(20 << 2);

    // --- Final Report ---
    $display("\n--- Simulation Summary ---");
    $display("Matches: %0d", match_count);
    $display("Errors:  %0d", error_count);
    if (error_count == 0 && match_count > 0) $display("RESULT: PASSED");
    else $display("RESULT: FAILED");

    $display("FINISH: Simulation finished at %0t", $time);
    $finish;
  end

  task automatic axi_write_wait(input logic [31:0] addr, input logic [31:0] data);
    begin
      // Drive signals on the clock edge
      @(posedge aclk);
      awaddr  <= addr;
      awvalid <= 1'b1;
      wdata   <= data;
      wvalid  <= 1'b1;
      wstrb   <= 4'hF;
      bready  <= 1'b1;

      // Wait for Address and Data handshakes
      // Using fork/join allows AW and W to happen in any order
      fork
        begin
          wait (awvalid && awready);
          @(posedge aclk) awvalid <= 1'b0;
        end
        begin
          wait (wvalid && wready);
          @(posedge aclk) wvalid <= 1'b0;
        end
      join

      // Wait for the Write Response (BRESP)
      wait (bvalid && bready);

      // Final check on the response status
      if (bresp !== 2'b00) begin
        $error("AXI Write Error at addr %0h: BRESP = %0b", addr, bresp);
      end

      @(posedge aclk);
      bready <= 1'b0;
      $display("[SCOREBOARD] Stored %0h at addr %0h", data, addr);
      shadow_mem[addr>>2] = data;
      shadow_written[addr>>2] = 1;
    end
  endtask

  task automatic axi_read_wait(input logic [31:0] addr);
    begin
      // 1. Drive Address and signal readiness for Data
      @(posedge aclk);
      araddr  <= addr;
      arvalid <= 1'b1;
      rready  <= 1'b1;  // Signal that we are ready to receive data

      // 2. Wait for Address Handshake (Address accepted by Slave)
      wait (arvalid && arready);
      @(posedge aclk);
      arvalid <= 1'b0;  // De-assert address valid after handshake
      $display("[SCOREBOARD] Address Accepted at %0t", $time);

      // 3. Wait for Data Handshake (Data provided by Slave)
      wait (rvalid && rready);
      // Capture data here if needed: data_buffer = rdata;
      @(posedge aclk);
      rready <= 1'b0;  // De-assert ready after receiving data
      $display("[SCOREBOARD] Data Received at %0t", $time);

      // --- THE CHECK ---
      if (shadow_written[addr>>2]) begin
        expected = shadow_mem[addr>>2];
        if (rdata === expected) begin
          $display("[PASS] Time %0t: Addr %0h | Read: %0h | Expected: %0h", $time, addr, rdata,
                   expected);
          match_count++;
        end else begin
          $display("[FAIL] Time %0t: Addr %0h | Read: %0h | Expected: %0h", $time, addr, rdata,
                   expected);
          error_count++;
        end
      end else begin
        $display("[WARN] Time %0t: Read uninitialized Addr %0h (Value: %0h)", $time, addr, rdata);
      end

      @(posedge aclk);
      $display("[SCOREBOARD] Read to %0h complete at %0t: %0h", addr, rdata, $time);
    end
  endtask
endmodule
