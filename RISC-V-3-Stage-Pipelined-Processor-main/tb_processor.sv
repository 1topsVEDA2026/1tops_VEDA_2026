module tb_processor();

    // add x3, x4, x2
    // 00000000001000100000000110110011

    logic clk;
    logic rst;

    processor dut 
    (
        .clk ( clk ),
        .rst ( rst )
    );

    // clock generator
    initial 
    begin
        clk = 0;
        forever 
        begin
            #5 clk = ~clk;
        end
    end

    // reset generator
    initial
    begin
        rst = 1;
        #10;
        rst = 0;
        #1000;
        $finish;
    end

    // initialize memory
    initial
    begin
        $readmemb("inst.mem", dut.inst_mem_i.mem);
        $readmemb("rf.mem", dut.reg_file_i.reg_mem);
        $readmemb("dm.mem", dut.data_mem_i.data_mem);
    end

    // dumping the waveform
    initial
    begin
        $dumpfile("processor.vcd");
        $dumpvars(0, dut);
    end

    final
    begin
        $writememh("rf_out.mem", dut.reg_file_i.reg_mem);
        $writememh("dm_out.mem", dut.data_mem_i.data_mem);
    end

endmodule