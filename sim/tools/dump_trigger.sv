module dump_trigger;
    /* verilator public_module */
    initial begin
        // Use the macro provided by the compiler
        $dumpfile(`DUMP_FILE);
        $dumpvars(0);
        // $dumpvars(0, fifo_tb.fifo_i.mem[0]);
        // $dumpvars(0, fifo_tb.fifo_i.mem[1]);
        // $dumpvars(0, fifo_tb.fifo_i.mem[2]);
        // $dumpvars(0, fifo_tb.fifo_i.mem[3]);
        for (int i = 0; i < 32; i++) begin
            $dumpvars(0, axi_lite_slave_ram_tb.uut.ram[i]);
        end
    end
endmodule
