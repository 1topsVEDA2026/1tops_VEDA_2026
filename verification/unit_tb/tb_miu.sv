`timescale 1ns / 1ps
// ============================================================================
// tb_miu.sv — Phase-1 Unit-Level Memory Interface Unit (MIU) Testbench
//
// Target Module: miu.sv
//
// Sign-off Criteria Verified:
//   - All size x offset combinations covered:
//       * Byte accesses at offsets 0, 1, 2, 3
//       * Halfword accesses at offsets 0, 2
//       * Word accesses at offset 0
//   - Signed and unsigned load extensions:
//       * LB  (sign-extended byte)
//       * LBU (zero-extended byte)
//       * LH  (sign-extended halfword)
//       * LHU (zero-extended halfword)
//       * LW  (full 32-bit word)
//   - Byte enable generation (wstrb) and store data replication/alignment
//   - One outstanding transaction FSM and pipeline stall (dmem_stall) timing
// ============================================================================

module tb_miu
    import rv32_pkg::*;
();

    // Clock & Reset
    logic clk, rst_n;
    localparam CLK_PERIOD = 10;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Core Pipeline Interface
    logic          rd_en_MW;
    logic          wr_en_MW;
    mem_acc_mode_t mem_acc_mode_MW;
    logic [31:0]   addr_MW;
    logic [31:0]   wdata_MW;
    logic [31:0]   rdata_ext;
    logic          dmem_stall;

    // AXI4 Bus Signals
    logic [31:0]   dmem_awaddr;
    logic          dmem_awvalid, dmem_awready;
    logic [ 7:0]   dmem_awlen;
    logic [ 2:0]   dmem_awsize;
    logic [ 1:0]   dmem_awburst;
    logic [ 3:0]   dmem_awcache;
    logic [ 2:0]   dmem_awprot;
    logic          dmem_awlock;

    logic [31:0]   dmem_wdata;
    logic [ 3:0]   dmem_wstrb;
    logic          dmem_wvalid, dmem_wready, dmem_wlast;

    logic          dmem_bvalid, dmem_bready;
    logic [ 1:0]   dmem_bresp;

    logic [31:0]   dmem_araddr;
    logic          dmem_arvalid, dmem_arready;
    logic [ 7:0]   dmem_arlen;
    logic [ 2:0]   dmem_arsize;
    logic [ 1:0]   dmem_arburst;
    logic [ 3:0]   dmem_arcache;
    logic [ 2:0]   dmem_arprot;
    logic          dmem_arlock;

    logic [31:0]   dmem_rdata;
    logic          dmem_rvalid, dmem_rready;
    logic [ 1:0]   dmem_rresp;
    logic          dmem_rlast;

    // DUT Instantiation
    miu u_dut (.*);

    integer pass_cnt = 0, fail_cnt = 0, test_cnt = 0;

    // ========================================================================
    // FUNCTIONAL COVERAGE
    // ========================================================================
    covergroup cg_miu @(posedge clk);
        cp_mode: coverpoint mem_acc_mode_MW {
            bins byte_s   = {MEM_BYTE};
            bins byte_u   = {MEM_BYTE_U};
            bins half_s   = {MEM_HALF};
            bins half_u   = {MEM_HALF_U};
            bins word     = {MEM_WORD};
        }
        cp_offset: coverpoint addr_MW[1:0] {
            bins off0 = {2'b00};
            bins off1 = {2'b01};
            bins off2 = {2'b10};
            bins off3 = {2'b11};
        }
        cp_op: coverpoint {rd_en_MW, wr_en_MW} {
            bins read_op  = {2'b10};
            bins write_op = {2'b01};
            bins idle     = {2'b00};
        }
        cx_mode_offset: cross cp_mode, cp_offset, cp_op;
    endgroup

    cg_miu cov = new();

    // ========================================================================
    // CHECK TASKS
    // ========================================================================
    task automatic check_store(
        input mem_acc_mode_t mode,
        input logic [31:0]   addr,
        input logic [31:0]   val,
        input logic [ 3:0]   exp_strb,
        input logic [31:0]   exp_wdata,
        input string         desc
    );
        test_cnt++;
        @(negedge clk);
        wr_en_MW        = 1'b1;
        rd_en_MW        = 1'b0;
        mem_acc_mode_MW = mode;
        addr_MW         = addr;
        wdata_MW        = val;
        dmem_awready    = 1'b1;
        dmem_wready     = 1'b1;
        dmem_bvalid     = 1'b1;
        dmem_bresp      = 2'b00;

        #1;
        if (dmem_wstrb === exp_strb && dmem_wdata === exp_wdata) begin
            pass_cnt++;
            $display("  [PASS] (Store) %-35s | strb=4'b%04b data=0x%08H",
                     desc, dmem_wstrb, dmem_wdata);
        end else begin
            fail_cnt++;
            $display("  [FAIL] (Store) %-35s | got_strb=4'b%04b exp=4'b%04b got_data=0x%08H exp=0x%08H",
                     desc, dmem_wstrb, exp_strb, dmem_wdata, exp_wdata);
        end

        @(posedge clk);
        @(negedge clk);
        wr_en_MW    = 1'b0;
        dmem_bvalid = 1'b0;
    endtask

    task automatic check_load(
        input mem_acc_mode_t mode,
        input logic [31:0]   addr,
        input logic [31:0]   bus_rdata,
        input logic [31:0]   exp_ext,
        input string         desc
    );
        test_cnt++;
        @(negedge clk);
        rd_en_MW        = 1'b1;
        wr_en_MW        = 1'b0;
        mem_acc_mode_MW = mode;
        addr_MW         = addr;
        dmem_arready    = 1'b1;
        dmem_rvalid     = 1'b1;
        dmem_rdata      = bus_rdata;
        dmem_rresp      = 2'b00;

        #1;
        if (rdata_ext === exp_ext) begin
            pass_cnt++;
            $display("  [PASS] (Load)  %-35s | got=0x%08H exp=0x%08H",
                     desc, rdata_ext, exp_ext);
        end else begin
            fail_cnt++;
            $display("  [FAIL] (Load)  %-35s | got=0x%08H exp=0x%08H (raw bus=0x%08H)",
                     desc, rdata_ext, exp_ext, bus_rdata);
        end

        @(posedge clk);
        @(negedge clk);
        rd_en_MW    = 1'b0;
        dmem_rvalid = 1'b0;
    endtask

    // ========================================================================
    // MAIN TEST SEQUENCE
    // ========================================================================
    initial begin
        $display("==================================================================");
        $display("  tb_miu: Memory Interface Unit Verification");
        $display("==================================================================");

        // Reset
        rst_n           = 0;
        rd_en_MW        = 0;
        wr_en_MW        = 0;
        mem_acc_mode_MW = MEM_WORD;
        addr_MW         = 0;
        wdata_MW        = 0;
        dmem_awready    = 0;
        dmem_wready     = 0;
        dmem_bvalid     = 0;
        dmem_bresp      = 0;
        dmem_arready    = 0;
        dmem_rvalid     = 0;
        dmem_rdata      = 0;
        dmem_rresp      = 0;
        dmem_rlast      = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // --------------------------------------------------------------------
        // 1. Store Byte Enables & Lane Alignment (All Sizes x Offsets)
        // --------------------------------------------------------------------
        $display("\n--- 1. Store Byte Enables & Alignment ---");

        // SB at offsets 0, 1, 2, 3
        check_store(MEM_BYTE, 32'h0000_1000, 32'h0000_00AA, 4'b0001, 32'hAAAAAAAA, "SB at offset 0");
        check_store(MEM_BYTE, 32'h0000_1001, 32'h0000_00BB, 4'b0010, 32'hBBBBBBBB, "SB at offset 1");
        check_store(MEM_BYTE, 32'h0000_1002, 32'h0000_00CC, 4'b0100, 32'hCCCCCCCC, "SB at offset 2");
        check_store(MEM_BYTE, 32'h0000_1003, 32'h0000_00DD, 4'b1000, 32'hDDDDDDDD, "SB at offset 3");

        // SH at offsets 0, 2
        check_store(MEM_HALF, 32'h0000_1000, 32'h0000_1234, 4'b0011, 32'h12341234, "SH at offset 0");
        check_store(MEM_HALF, 32'h0000_1002, 32'h0000_5678, 4'b1100, 32'h56785678, "SH at offset 2");

        // SW at offset 0
        check_store(MEM_WORD, 32'h0000_1000, 32'hDEADBEEF, 4'b1111, 32'hDEADBEEF, "SW at offset 0");

        // --------------------------------------------------------------------
        // 2. Load Extraction & Sign / Zero Extension (All Sizes x Offsets)
        // --------------------------------------------------------------------
        $display("\n--- 2. Load Extraction & Extension ---");

        // Test Word: 0x81F07E05
        // Byte 0 = 0x05 (pos, sign=0)
        // Byte 1 = 0x7E (pos, sign=0)
        // Byte 2 = 0xF0 (neg, sign=1)
        // Byte 3 = 0x81 (neg, sign=1)
        // Half 0 = 0x7E05 (pos, sign=0)
        // Half 1 = 0x81F0 (neg, sign=1)
        localparam logic [31:0] TEST_WORD = 32'h81F0_7E05;

        // Signed Byte Loads (LB)
        check_load(MEM_BYTE, 32'h0000_2000, TEST_WORD, 32'h0000_0005, "LB offset 0 (positive)");
        check_load(MEM_BYTE, 32'h0000_2001, TEST_WORD, 32'h0000_007E, "LB offset 1 (positive)");
        check_load(MEM_BYTE, 32'h0000_2002, TEST_WORD, 32'hFFFF_FFF0, "LB offset 2 (sign extended)");
        check_load(MEM_BYTE, 32'h0000_2003, TEST_WORD, 32'hFFFF_FF81, "LB offset 3 (sign extended)");

        // Unsigned Byte Loads (LBU)
        check_load(MEM_BYTE_U, 32'h0000_2000, TEST_WORD, 32'h0000_0005, "LBU offset 0 (zero extended)");
        check_load(MEM_BYTE_U, 32'h0000_2001, TEST_WORD, 32'h0000_007E, "LBU offset 1 (zero extended)");
        check_load(MEM_BYTE_U, 32'h0000_2002, TEST_WORD, 32'h0000_00F0, "LBU offset 2 (zero extended)");
        check_load(MEM_BYTE_U, 32'h0000_2003, TEST_WORD, 32'h0000_0081, "LBU offset 3 (zero extended)");

        // Signed Halfword Loads (LH)
        check_load(MEM_HALF, 32'h0000_2000, TEST_WORD, 32'h0000_7E05, "LH offset 0 (positive)");
        check_load(MEM_HALF, 32'h0000_2002, TEST_WORD, 32'hFFFF_81F0, "LH offset 2 (sign extended)");

        // Unsigned Halfword Loads (LHU)
        check_load(MEM_HALF_U, 32'h0000_2000, TEST_WORD, 32'h0000_7E05, "LHU offset 0 (zero extended)");
        check_load(MEM_HALF_U, 32'h0000_2002, TEST_WORD, 32'h0000_81F0, "LHU offset 2 (zero extended)");

        // Word Load (LW)
        check_load(MEM_WORD, 32'h0000_2000, TEST_WORD, 32'h81F0_7E05, "LW offset 0 (full word)");

        // --------------------------------------------------------------------
        // 3. One Outstanding Transaction & Pipeline Stall (dmem_stall)
        // --------------------------------------------------------------------
        $display("\n--- 3. One Outstanding Transaction & Stall Timing ---");

        // Initiate read with multi-cycle slave delay (2 wait states)
        test_cnt++;
        @(negedge clk);
        rd_en_MW        = 1'b1;
        mem_acc_mode_MW = MEM_WORD;
        addr_MW         = 32'h0000_3000;
        dmem_arready    = 1'b1;
        dmem_rvalid     = 1'b0; // Slave not ready yet
        #1;

        // Verify stall asserts immediately
        if (dmem_stall === 1'b1) begin
            pass_cnt++;
            $display("  [PASS] dmem_stall asserted on initial read request");
        end else begin
            fail_cnt++;
            $display("  [FAIL] dmem_stall not asserted during in-flight read");
        end

        // Cycle 1: in DM_RD, stall must remain high
        @(posedge clk);
        #1;
        test_cnt++;
        if (dmem_stall === 1'b1) begin
            pass_cnt++;
            $display("  [PASS] dmem_stall held during wait-state 1");
        end else begin
            fail_cnt++;
            $display("  [FAIL] dmem_stall dropped early during wait-state 1");
        end

        // Cycle 2: slave returns rvalid
        @(negedge clk);
        dmem_rvalid = 1'b1;
        dmem_rdata  = 32'hCAFEBABE;
        @(posedge clk);
        #1;
        test_cnt++;
        if (rdata_ext === 32'hCAFEBABE) begin
            pass_cnt++;
            $display("  [PASS] rdata_ext captured successfully on rvalid");
        end else begin
            fail_cnt++;
            $display("  [FAIL] rdata_ext mismatch on rvalid");
        end

        // Following cycle: returns to IDLE, stall deasserts
        @(negedge clk);
        rd_en_MW    = 1'b0;
        dmem_rvalid = 1'b0;
        @(posedge clk);
        #1;
        test_cnt++;
        if (dmem_stall === 1'b0) begin
            pass_cnt++;
            $display("  [PASS] dmem_stall deasserted after transaction completion");
        end else begin
            fail_cnt++;
            $display("  [FAIL] dmem_stall remained asserted after completion");
        end

        // --------------------------------------------------------------------
        // Final Summary
        // --------------------------------------------------------------------
        $display("\n==================================================================");
        $display("  MIU UNIT VERIFICATION SUMMARY");
        $display("    Total Tests : %0d", test_cnt);
        $display("    PASSED      : %0d", pass_cnt);
        $display("    FAILED      : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL MIU UNIT TESTS PASSED <<<");
        else
            $display("  >>> MIU UNIT VERIFICATION FAILED <<<");
        $display("==================================================================");

        $finish;
    end

endmodule
