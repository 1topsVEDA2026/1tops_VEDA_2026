`timescale 1ns / 1ps
// ============================================================
// tb_register_file.sv — Phase-1 Register File TB (XSim-safe)
//
// Write protocol: set rf_en/rd_addr/wdata at negedge,
//                 let posedge capture (setup-time correct)
// Read protocol:  set rs1_addr/rs2_addr, wait #1 (async read)
// ============================================================
module tb_register_file
    import rv32_pkg::*;
();

    logic        clk, rst_n;
    logic [ 4:0] rs1_addr, rs2_addr, rd_addr;
    logic [31:0] rsdata1, rsdata2, wdata;
    logic        rf_en;

    initial clk = 0;
    always #5 clk = ~clk;

    register_file u_dut (.*);

    integer pass_cnt = 0, fail_cnt = 0;

    task automatic check(input string desc, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            pass_cnt++;
            $display("  [PASS] %s  (0x%08H)", desc, got);
        end else begin
            $display("  [FAIL] %s: got=0x%08H exp=0x%08H", desc, got, exp);
            fail_cnt++;
        end
    endtask

    // ---- Write helper: setup at negedge, captured at next posedge ----
    task automatic write_reg(input logic [4:0] addr, input logic [31:0] data);
        @(negedge clk);
        rf_en  = 1;
        rd_addr = addr;
        wdata   = data;
        @(posedge clk);  // data captured here
        @(negedge clk);
        rf_en = 0;
    endtask

    // ---- Read helper: async read ----
    task automatic read_check(input string desc, input logic [4:0] addr, input logic [31:0] exp);
        rs1_addr = addr;
        #1;
        check(desc, rsdata1, exp);
    endtask

    // ---- Variables ----
    integer ri;
    logic [4:0]  rand_addr;
    logic [31:0] rand_val;

    // ---- Covergroup ----
    covergroup cg_rf @(posedge clk);
        cp_rd:  coverpoint rd_addr  { bins regs[] = {[0:31]}; }
        cp_rs1: coverpoint rs1_addr { bins regs[] = {[0:31]}; }
        cp_wen: coverpoint rf_en    { bins on = {1}; bins off = {0}; }
    endgroup

    cg_rf cov = new();

    initial begin
        $display("\n========== Register File Unit Testbench ==========");

        // ---- Reset ----
        rst_n = 0; rf_en = 0; rd_addr = 0; wdata = 0;
        rs1_addr = 0; rs2_addr = 0;
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk); // one clean cycle after reset

        // ---- Test 1: All registers zero after reset ----
        $display("\n--- Test 1: Post-reset all zeros ---");
        for (ri = 0; ri < 32; ri = ri + 1) begin
            read_check($sformatf("x%0d after reset", ri), ri[4:0], 32'd0);
        end

        // ---- Test 2: Write and read each register ----
        $display("\n--- Test 2: Write/read all 32 registers ---");
        for (ri = 0; ri < 32; ri = ri + 1) begin
            write_reg(ri[4:0], 32'hA000_0000 + ri);
            if (ri == 0)
                read_check($sformatf("x%0d (x0=0)", ri), ri[4:0], 32'd0);
            else
                read_check($sformatf("x%0d", ri), ri[4:0], 32'hA000_0000 + ri);
        end

        // ---- Test 3: x0 write ignored ----
        $display("\n--- Test 3: x0 hardwired zero ---");
        write_reg(5'd0, 32'hDEADBEEF);
        read_check("x0 after write", 5'd0, 32'd0);

        // ---- Test 4: Write-through bypass ----
        $display("\n--- Test 4: Write-through bypass ---");
        @(negedge clk);
        rf_en = 1; rd_addr = 5'd5; wdata = 32'hCAFEBABE;
        rs1_addr = 5'd5; rs2_addr = 5'd5;
        #1;
        check("bypass rs1", rsdata1, 32'hCAFEBABE);
        check("bypass rs2", rsdata2, 32'hCAFEBABE);
        @(posedge clk); // commit
        @(negedge clk); rf_en = 0;

        // ---- Test 5: rf_en=0 prevents write ----
        $display("\n--- Test 5: No spurious write (rf_en=0) ---");
        @(negedge clk);
        rf_en = 0; rd_addr = 5'd5; wdata = 32'h12345678;
        @(posedge clk); @(negedge clk);
        read_check("no-write x5", 5'd5, 32'hCAFEBABE);

        // ---- Test 6: Dual-port read ----
        $display("\n--- Test 6: Dual-port read ---");
        write_reg(5'd10, 32'h10101010);
        write_reg(5'd20, 32'h20202020);
        rs1_addr = 5'd10; rs2_addr = 5'd20; #1;
        check("port1 x10", rsdata1, 32'h10101010);
        check("port2 x20", rsdata2, 32'h20202020);

        // ---- Test 7: Random (200 vectors) ----
        $display("\n--- Test 7: Random write/read (200 vectors) ---");
        for (ri = 0; ri < 200; ri = ri + 1) begin
            rand_addr = $urandom_range(1, 31);
            rand_val  = $urandom;
            write_reg(rand_addr, rand_val);
            read_check($sformatf("rand x%0d", rand_addr), rand_addr, rand_val);
        end

        // ---- Summary ----
        $display("\n========================================");
        $display("  REGFILE FINAL: %0d PASS, %0d FAIL (of %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("========================================");
        if (fail_cnt > 0) $display("  *** FAILURES DETECTED ***");
        else              $display("  *** ALL TESTS PASSED ***");
        #10; $finish;
    end

endmodule
