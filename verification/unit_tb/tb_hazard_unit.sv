`timescale 1ns / 1ps
// ============================================================
// tb_hazard_unit.sv - Phase-1 Hazard Unit TB (XSim-safe)
// ============================================================
module tb_hazard_unit
    import rv32_pkg::*;
();

    logic [4:0] rs1_addr_DE, rs2_addr_DE, rd_addr_MW;
    logic       rf_en_MW, rd_en_MW;
    logic       br_take_DE, is_mret_DE, epc_taken_IF;
    logic       imem_stall, dmem_stall, mdu_stall;   // mdu_stall: MDU multi-cycle stall
    logic       forward_a, forward_b;
    logic       stall_IF, stall_MW, flush_DE, flush_MW;

    hazard_unit u_dut (.*);

    integer pass_cnt = 0, fail_cnt = 0;

    // ---- Golden reference ----
    logic exp_fa, exp_fb, exp_sif, exp_smw, exp_fde, exp_fmw;
    logic ref_lu, ref_ms;

    task automatic compute_ref();
        exp_fa = !rd_en_MW && rf_en_MW && (rs1_addr_DE != 5'd0) && (rs1_addr_DE == rd_addr_MW);
        exp_fb = !rd_en_MW && rf_en_MW && (rs2_addr_DE != 5'd0) && (rs2_addr_DE == rd_addr_MW);
        ref_lu = rd_en_MW && rf_en_MW &&
                 ((rs1_addr_DE != 5'd0 && rs1_addr_DE == rd_addr_MW) ||
                  (rs2_addr_DE != 5'd0 && rs2_addr_DE == rd_addr_MW));
        // mdu_stall is part of mem_stall — freezes the whole pipeline
        ref_ms = imem_stall || dmem_stall || mdu_stall;
        exp_sif = ref_lu || ref_ms;
        exp_smw = ref_ms;
        exp_fde = (br_take_DE || is_mret_DE || epc_taken_IF) && !(ref_lu || ref_ms);
        exp_fmw = ref_lu && !ref_ms;
    endtask

    task automatic check(input string desc);
        compute_ref();
        #1;
        if (forward_a !== exp_fa || forward_b !== exp_fb ||
            stall_IF  !== exp_sif || stall_MW  !== exp_smw ||
            flush_DE  !== exp_fde || flush_MW  !== exp_fmw) begin
            $display("  [FAIL] %s", desc);
            $display("         fwd_a=%b(%b) fwd_b=%b(%b) s_if=%b(%b) s_mw=%b(%b) fl_de=%b(%b) fl_mw=%b(%b)",
                     forward_a, exp_fa, forward_b, exp_fb,
                     stall_IF, exp_sif, stall_MW, exp_smw,
                     flush_DE, exp_fde, flush_MW, exp_fmw);
            fail_cnt++;
        end else begin
            pass_cnt++;
            if (desc != "") $display("  [PASS] %s  fwd=%b%b stl=%b%b fl=%b%b",
                     desc, forward_a, forward_b, stall_IF, stall_MW, flush_DE, flush_MW);
        end
    endtask

    task automatic clear();
        rs1_addr_DE = 0; rs2_addr_DE = 0; rd_addr_MW = 0;
        rf_en_MW = 0; rd_en_MW = 0;
        br_take_DE = 0; is_mret_DE = 0; epc_taken_IF = 0;
        imem_stall = 0; dmem_stall = 0; mdu_stall = 0;
    endtask

    // ---- Covergroup with cross coverage ----
    covergroup cg_hz;
        cp_fwd_a:    coverpoint forward_a;
        cp_fwd_b:    coverpoint forward_b;
        cp_stall_if: coverpoint stall_IF;
        cp_stall_mw: coverpoint stall_MW;
        cp_flush_de: coverpoint flush_DE;
        cp_flush_mw: coverpoint flush_MW;

        // Cross coverage: forwarding vs stall
        cx_fwd_a_stall_if: cross cp_fwd_a, cp_stall_if;
        cx_fwd_b_stall_if: cross cp_fwd_b, cp_stall_if;

        // Cross coverage: stall vs flush
        cx_stall_if_flush_de: cross cp_stall_if, cp_flush_de;
        cx_stall_mw_flush_mw: cross cp_stall_mw, cp_flush_mw;

        // Cross coverage: flush_de vs flush_mw
        cx_flush_de_flush_mw: cross cp_flush_de, cp_flush_mw;

        // Cross coverage: forward both simultaneously
        cx_fwd_a_fwd_b: cross cp_fwd_a, cp_fwd_b;
    endgroup

    cg_hz cov = new();

    integer ri;

    // ---- Task: print coverage summary ----
    task automatic print_coverage();
        $display("\n========== Coverage Report ==========");
        $display("  Overall Functional Coverage : %.2f%%", cov.get_coverage());
        $display("  cp_fwd_a    : %.2f%%", cov.cp_fwd_a.get_coverage());
        $display("  cp_fwd_b    : %.2f%%", cov.cp_fwd_b.get_coverage());
        $display("  cp_stall_if : %.2f%%", cov.cp_stall_if.get_coverage());
        $display("  cp_stall_mw : %.2f%%", cov.cp_stall_mw.get_coverage());
        $display("  cp_flush_de : %.2f%%", cov.cp_flush_de.get_coverage());
        $display("  cp_flush_mw : %.2f%%", cov.cp_flush_mw.get_coverage());
        $display("  cx_fwd_a_stall_if   : %.2f%%", cov.cx_fwd_a_stall_if.get_coverage());
        $display("  cx_fwd_b_stall_if   : %.2f%%", cov.cx_fwd_b_stall_if.get_coverage());
        $display("  cx_stall_if_flush_de: %.2f%%", cov.cx_stall_if_flush_de.get_coverage());
        $display("  cx_stall_mw_flush_mw: %.2f%%", cov.cx_stall_mw_flush_mw.get_coverage());
        $display("  cx_flush_de_flush_mw: %.2f%%", cov.cx_flush_de_flush_mw.get_coverage());
        $display("  cx_fwd_a_fwd_b      : %.2f%%", cov.cx_fwd_a_fwd_b.get_coverage());
        $display("=====================================\n");
    endtask

    initial begin
        $display("\n========== Hazard Unit Testbench ==========");

        // ---- No hazard ----
        $display("\n--- No hazard ---");
        clear(); check("no hazard");
        cov.sample();

        // ---- Forward A only ----
        $display("\n--- Forwarding ---");
        clear(); rf_en_MW = 1; rd_en_MW = 0;
        rs1_addr_DE = 5'd5; rd_addr_MW = 5'd5;
        check("fwd_a: rs1=rd=5");
        cov.sample();

        // ---- Forward B only ----
        clear(); rf_en_MW = 1; rd_en_MW = 0;
        rs2_addr_DE = 5'd10; rd_addr_MW = 5'd10;
        check("fwd_b: rs2=rd=10");
        cov.sample();

        // ---- Forward both ----
        clear(); rf_en_MW = 1; rd_en_MW = 0;
        rs1_addr_DE = 5'd3; rs2_addr_DE = 5'd3; rd_addr_MW = 5'd3;
        check("fwd_a+b: rs1=rs2=rd=3");
        cov.sample();

        // ---- No forward to x0 ----
        clear(); rf_en_MW = 1; rd_en_MW = 0;
        rs1_addr_DE = 5'd0; rd_addr_MW = 5'd0;
        check("no fwd to x0");
        cov.sample();

        // ---- No forward when rf_en=0 ----
        clear(); rf_en_MW = 0; rd_en_MW = 0;
        rs1_addr_DE = 5'd5; rd_addr_MW = 5'd5;
        check("no fwd: rf_en=0");
        cov.sample();

        // ---- Load-use stall ----
        $display("\n--- Load-use stall ---");
        clear(); rf_en_MW = 1; rd_en_MW = 1;
        rs1_addr_DE = 5'd7; rd_addr_MW = 5'd7;
        check("load-use rs1");
        cov.sample();

        clear(); rf_en_MW = 1; rd_en_MW = 1;
        rs2_addr_DE = 5'd7; rd_addr_MW = 5'd7;
        check("load-use rs2");
        cov.sample();

        // ---- Memory stall ----
        $display("\n--- Memory stalls ---");
        clear(); imem_stall = 1;
        check("imem stall");
        cov.sample();

        clear(); dmem_stall = 1;
        check("dmem stall");
        cov.sample();

        clear(); imem_stall = 1; dmem_stall = 1;
        check("both stall");
        cov.sample();

        // ---- Flush on branch ----
        $display("\n--- Flush ---");
        clear(); br_take_DE = 1;
        check("flush: branch");
        cov.sample();

        clear(); is_mret_DE = 1;
        check("flush: mret");
        cov.sample();

        clear(); epc_taken_IF = 1;
        check("flush: exc");
        cov.sample();

        // ---- Stall suppresses flush ----
        $display("\n--- Stall vs flush priority ---");
        clear(); br_take_DE = 1; imem_stall = 1;
        check("stall suppresses flush (imem)");
        cov.sample();

        clear(); br_take_DE = 1; dmem_stall = 1;
        check("stall suppresses flush (dmem)");
        cov.sample();

        clear(); br_take_DE = 1;
        rf_en_MW = 1; rd_en_MW = 1;
        rs1_addr_DE = 5'd3; rd_addr_MW = 5'd3;
        check("load-use + branch: stall wins");
        cov.sample();

        // ---- Load-use + mem_stall ----
        clear(); rf_en_MW = 1; rd_en_MW = 1;
        rs1_addr_DE = 5'd3; rd_addr_MW = 5'd3;
        dmem_stall = 1;
        check("load-use + dmem_stall: no flush_MW");
        cov.sample();

        // ---- MDU stall (mdu_stall alone) ----
        // MDU busy: should freeze IF and MW, no flush
        $display("\n--- MDU stall ---");
        clear(); mdu_stall = 1;
        check("mdu_stall alone: stall_IF=1 stall_MW=1 flush_DE=0");
        cov.sample();

        // MDU stall + branch: stall suppresses flush (same priority as mem_stall)
        clear(); mdu_stall = 1; br_take_DE = 1;
        check("mdu_stall + branch: stall suppresses flush");
        cov.sample();

        // MDU stall + load-use: both stall, no flush_MW (mem_stall takes priority)
        clear(); mdu_stall = 1; rf_en_MW = 1; rd_en_MW = 1;
        rs1_addr_DE = 5'd5; rd_addr_MW = 5'd5;
        check("mdu_stall + load-use: stall_IF=1 stall_MW=1 flush_MW=0");
        cov.sample();

        // All three stalls simultaneously
        clear(); imem_stall = 1; dmem_stall = 1; mdu_stall = 1;
        check("all three stalls simultaneously");
        cov.sample();

        // ---- Random (500 vectors) - silent unless FAIL ----
        $display("\n--- Random (500 vectors, includes mdu_stall) ---");
        for (ri = 0; ri < 500; ri = ri + 1) begin
            rs1_addr_DE  = $urandom_range(0, 31);
            rs2_addr_DE  = $urandom_range(0, 31);
            rd_addr_MW   = $urandom_range(0, 31);
            rf_en_MW     = $urandom_range(0, 1);
            rd_en_MW     = $urandom_range(0, 1);
            br_take_DE   = $urandom_range(0, 1);
            is_mret_DE   = $urandom_range(0, 1) & ~br_take_DE;
            epc_taken_IF = $urandom_range(0, 1) & ~br_take_DE & ~is_mret_DE;
            imem_stall   = $urandom_range(0, 1);
            dmem_stall   = $urandom_range(0, 1);
            mdu_stall    = $urandom_range(0, 1);
            check("");
            cov.sample();
        end

        // ---- Extra 10 random vectors - always printed ----
        $display("\n--- Extra 10 random vectors (printed) ---");
        $display("  %-4s | %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s %-5s | fwd_a fwd_b stl_IF stl_MW fl_DE fl_MW",
                 "idx", "rs1", "rs2", "rd", "rfEN", "rdEN", "brTk", "mret", "epc", "imS", "dmS");
        $display("  %-4s-+-%-5s-%-5s-%-5s-%-5s-%-5s-%-5s-%-5s-%-5s-%-5s-%-5s-+------+------+------+------+-----+-----",
                 "----","-----","-----","-----","-----","-----","-----","-----","-----","-----","-----");
        for (ri = 0; ri < 10; ri = ri + 1) begin
            rs1_addr_DE  = $urandom_range(0, 31);
            rs2_addr_DE  = $urandom_range(0, 31);
            rd_addr_MW   = $urandom_range(0, 31);
            rf_en_MW     = $urandom_range(0, 1);
            rd_en_MW     = $urandom_range(0, 1);
            br_take_DE   = $urandom_range(0, 1);
            is_mret_DE   = $urandom_range(0, 1) & ~br_take_DE;
            epc_taken_IF = $urandom_range(0, 1) & ~br_take_DE & ~is_mret_DE;
            imem_stall   = $urandom_range(0, 1);
            dmem_stall   = $urandom_range(0, 1);
            mdu_stall    = $urandom_range(0, 1);
            compute_ref(); #1;
            $display("  %-40d | x%-4d x%-4d x%-4d %-5b %-5b %-5b %-5b %-5b %-5b %-5b | %-5b %-5b %-6b %-6b %-5b %-5b",
                     ri,
                     rs1_addr_DE, rs2_addr_DE, rd_addr_MW,
                     rf_en_MW, rd_en_MW, br_take_DE, is_mret_DE, epc_taken_IF,
                     imem_stall, dmem_stall,
                     forward_a, forward_b, stall_IF, stall_MW, flush_DE, flush_MW);
            // check and sample after print so result column matches
            check($sformatf("rand_extra[%0d]", ri));
            cov.sample();
        end

        // ---- Coverage report ----
        print_coverage();

        $display("========================================");
        $display("  HAZARD UNIT FINAL: %0d PASS, %0d FAIL (of %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("========================================");
        if (fail_cnt > 0) $display("  *** FAILURES DETECTED ***");
        else              $display("  *** ALL TESTS PASSED ***");
        #10; $finish;
    end
endmodule