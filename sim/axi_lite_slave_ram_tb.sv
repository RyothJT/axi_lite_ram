`timescale 1ns / 1ps

module axi_lite_slave_ram_tb;

    parameter int DATA_WIDTH = 32;
    parameter int ADDR_WIDTH = 8;
    parameter int RAM_DEPTH = 256;
    parameter int STRB_WIDTH = DATA_WIDTH / 8;
    parameter int RAM_ADDR_W = $clog2(RAM_DEPTH);


    // Global signals
    logic                  aclk = 0;
    logic                  aresetn = 0;

    // Write address channel
    logic [ADDR_WIDTH-1:0] awaddr = 0;
    logic                  awvalid = 0;

    // Write data channel
    logic [DATA_WIDTH-1:0] wdata = 0;
    logic [STRB_WIDTH-1:0] wstrb = 0;
    logic                  wvalid = 0;

    // Write response channel
    logic                  bready = 0;

    // Read address channel
    logic [ADDR_WIDTH-1:0] araddr = 0;
    logic                  arvalid = 0;

    // Read data channel
    logic                  rready = 0;

    // Output signals
    logic                  awready;
    logic                  wready;
    logic [           1:0] bresp;
    logic                  bvalid;
    logic                  arready;
    logic [DATA_WIDTH-1:0] rdata;
    logic [           1:0] rresp;
    logic                  rvalid;



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
        #(1000);
        $display("TIMEOUT: Simulation forced to end at %t", $time);
        $finish;
    end

    initial begin
        aresetn = 0;
        #20;
        aresetn = 1;
        #20;
        // Write 0x1234 5678 to addr 3
        axi_write_wait(3 * 8, 32'h1234_5678);

        // Read from 0x1234 5678
        axi_read_wait(3 * 8);
        $display("FINISH: Simulation finished at %t", $time);
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
                $error("AXI Write Error at addr %h: BRESP = %b", addr, bresp);
            end

            @(posedge aclk);
            bready <= 1'b0;
            $display("Write to %h complete at %t", addr, $time);
        end
    endtask

    task automatic axi_read_wait(input logic [31:0] addr);
        begin
            // Drive signals on the clock edge
            @(posedge aclk);
            araddr  <= addr;
            arvalid <= 1'b1;
            rready  <= 1'b1;

            // Wait for Address and Data handshakes
            // Using fork/join allows AW and W to happen in any order
            fork
                begin
                    wait (arvalid && arready);
                    @(posedge aclk) awvalid <= 1'b0;
                end
                begin
                    wait (rvalid && rready);
                    @(posedge aclk) wvalid <= 1'b0;
                end
            join

            @(posedge aclk);
            $display("Read to %h complete at %t: %h", addr, rdata, $time);
        end
    endtask
endmodule
