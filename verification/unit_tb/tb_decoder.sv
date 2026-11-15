`timescale 1ns / 1ps
// ============================================================
// tb_decoder.sv — Phase-1 Decoder Testbench (XSim-safe)
//
// Tests: All RV32I + M-ext opcode decode, field extraction,
//        funct3/funct7 validation, illegal instruction detection
// ============================================================
module tb_decoder
    import rv32_pkg::*;
();

    // ---- DUT ports (match decoder.sv exactly) ----
    logic [31:0]  inst;
    logic [ 4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [11:0]  csr_addr;
    imm_type_t    imm_type;
    exec_class_t  exec_class;
    alu_func_t    alu_func;
    mdu_func_t    mdu_func;        // M-extension operation select
    br_type_t     br_type;
    mem_acc_t     mem_acc_mode;
    csr_cmd_t     csr_cmd;

    decoder u_dut (
        .inst         (inst),
        .rs1_addr     (rs1_addr),
        .rs2_addr     (rs2_addr),
        .rd_addr      (rd_addr),
        .csr_addr     (csr_addr),
        .imm_type     (imm_type),
        .exec_class   (exec_class),
        .alu_func     (alu_func),
        .mdu_func     (mdu_func),
        .csr_cmd      (csr_cmd),
        .br_type      (br_type),
        .mem_acc_mode (mem_acc_mode)
    );

    integer pass_cnt = 0, fail_cnt = 0;

    // ---- Scoreboard ----
    task automatic check_class(input string desc, input exec_class_t exp_class);
        #1;
        if (exec_class !== exp_class) begin
            $display("  [FAIL] %s: exec_class=%0d (exp %0d)  inst=0x%08H",
                     desc, exec_class, exp_class, inst);
            fail_cnt++;
        end else begin
            pass_cnt++;
            $display("  [PASS] %s  inst=0x%08H", desc, inst);
        end
    endtask

    // ---- MDU func check ----
    task automatic check_mdu(input string desc, input mdu_func_t exp_func);
        #1;
        if (exec_class !== EXEC_MDU) begin
            $display("  [FAIL] %s: exec_class=%0d (exp EXEC_MDU)  inst=0x%08H",
                     desc, exec_class, inst);
            fail_cnt++;
        end else if (mdu_func !== exp_func) begin
            $display("  [FAIL] %s: mdu_func=%0d (exp %0d)  inst=0x%08H",
                     desc, mdu_func, exp_func, inst);
            fail_cnt++;
        end else begin
            pass_cnt++;
            $display("  [PASS] %s  mdu_func=%0d  inst=0x%08H", desc, mdu_func, inst);
        end
    endtask

    task automatic check_field5(input string desc, input logic [4:0] got, input logic [4:0] exp);
        if (got !== exp) begin
            $display("  [FAIL] %s: got=%0d exp=%0d", desc, got, exp);
            fail_cnt++;
        end else begin
            pass_cnt++;
            $display("  [PASS] %s  =%0d", desc, got);
        end
    endtask

    task automatic check_csr(input string desc, input csr_cmd_t exp_cmd);
        #1;
        if (csr_cmd !== exp_cmd) begin
            $display("  [FAIL] %s: csr_cmd=%0d (exp %0d)", desc, csr_cmd, exp_cmd);
            fail_cnt++;
        end else begin
            pass_cnt++;
            $display("  [PASS] %s", desc);
        end
    endtask

    // ---- Covergroup ----
    logic [6:0] opcode_w;
    logic [2:0] funct3_w;
    logic [6:0] funct7_w;
    assign opcode_w = inst[6:0];
    assign funct3_w = inst[14:12];
    assign funct7_w = inst[31:25];

    covergroup cg_dec @(inst);
        cp_opcode: coverpoint opcode_w {
            bins r_type  = {7'b0110011}; bins i_alu   = {7'b0010011};
            bins load    = {7'b0000011}; bins store   = {7'b0100011};
            bins branch  = {7'b1100011}; bins jal     = {7'b1101111};
            bins jalr    = {7'b1100111}; bins lui     = {7'b0110111};
            bins auipc   = {7'b0010111}; bins system  = {7'b1110011};
            bins fence   = {7'b0001111}; bins illegal = default;
        }
        cp_funct3: coverpoint funct3_w { bins vals[] = {[0:7]}; }
    endgroup

    cg_dec cov = new();

    // ---- Instruction builders ----
    function automatic logic [31:0] mk_r(
        logic [6:0] f7, logic [4:0] r2, logic [4:0] r1, logic [2:0] f3, logic [4:0] rd
    );
        return {f7, r2, r1, f3, rd, 7'b0110011};
    endfunction

    function automatic logic [31:0] mk_i(
        logic [11:0] imm, logic [4:0] r1, logic [2:0] f3, logic [4:0] rd, logic [6:0] op
    );
        return {imm, r1, f3, rd, op};
    endfunction

    function automatic logic [31:0] mk_s(
        logic [11:0] imm, logic [4:0] r2, logic [4:0] r1, logic [2:0] f3
    );
        return {imm[11:5], r2, r1, f3, imm[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] mk_b(
        logic [12:0] imm, logic [4:0] r2, logic [4:0] r1, logic [2:0] f3
    );
        return {imm[12], imm[10:5], r2, r1, f3, imm[4:1], imm[11], 7'b1100011};
    endfunction

    // ---- Variables for random block ----
    reg [31:0] rand_bits;
    integer ri;

    // ============================================================
    initial begin
        $display("\n========== Decoder Unit Testbench ==========");

        // ---- R-type base (10 checks) ----
        $display("\n--- R-type base ---");
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd0, 5'd3); check_class("R:ADD",  EXEC_ALU);
        inst = mk_r(7'b0100000, 5'd2, 5'd1, 3'd0, 5'd3); check_class("R:SUB",  EXEC_ALU);
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd1, 5'd3); check_class("R:SLL",  EXEC_ALU);
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd2, 5'd3); check_class("R:SLT",  EXEC_ALU);
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd3, 5'd3); check_class("R:SLTU", EXEC_ALU);
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd4, 5'd3); check_class("R:XOR",  EXEC_ALU);
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd5, 5'd3); check_class("R:SRL",  EXEC_ALU);
        inst = mk_r(7'b0100000, 5'd2, 5'd1, 3'd5, 5'd3); check_class("R:SRA",  EXEC_ALU);
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd6, 5'd3); check_class("R:OR",   EXEC_ALU);
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd7, 5'd3); check_class("R:AND",  EXEC_ALU);


        // ---- I-type ALU (6 checks) ----
        $display("\n--- I-type ALU ---");
        inst = mk_i(12'd10,  5'd1, 3'd0, 5'd3, 7'b0010011); check_class("I:ADDI",  EXEC_ALU_IMM);
        inst = mk_i(12'd5,   5'd1, 3'd2, 5'd3, 7'b0010011); check_class("I:SLTI",  EXEC_ALU_IMM);
        inst = mk_i(12'd5,   5'd1, 3'd3, 5'd3, 7'b0010011); check_class("I:SLTIU", EXEC_ALU_IMM);
        inst = mk_i(12'hFF,  5'd1, 3'd4, 5'd3, 7'b0010011); check_class("I:XORI",  EXEC_ALU_IMM);
        inst = mk_i(12'h30,  5'd1, 3'd6, 5'd3, 7'b0010011); check_class("I:ORI",   EXEC_ALU_IMM);
        inst = mk_i(12'h03,  5'd1, 3'd7, 5'd3, 7'b0010011); check_class("I:ANDI",  EXEC_ALU_IMM);
        // SLLI/SRLI/SRAI with correct funct7
        inst = {7'b0000000, 5'd3, 5'd1, 3'b001, 5'd3, 7'b0010011}; check_class("I:SLLI", EXEC_ALU_IMM);
        inst = {7'b0000000, 5'd3, 5'd1, 3'b101, 5'd3, 7'b0010011}; check_class("I:SRLI", EXEC_ALU_IMM);
        inst = {7'b0100000, 5'd3, 5'd1, 3'b101, 5'd3, 7'b0010011}; check_class("I:SRAI", EXEC_ALU_IMM);

        // ---- Loads — valid funct3 only (5 checks) ----
        $display("\n--- Loads ---");
        inst = mk_i(12'd0, 5'd1, 3'd0, 5'd3, 7'b0000011); check_class("LB",  EXEC_LOAD);
        inst = mk_i(12'd0, 5'd1, 3'd1, 5'd3, 7'b0000011); check_class("LH",  EXEC_LOAD);
        inst = mk_i(12'd0, 5'd1, 3'd2, 5'd3, 7'b0000011); check_class("LW",  EXEC_LOAD);
        inst = mk_i(12'd0, 5'd1, 3'd4, 5'd3, 7'b0000011); check_class("LBU", EXEC_LOAD);
        inst = mk_i(12'd0, 5'd1, 3'd5, 5'd3, 7'b0000011); check_class("LHU", EXEC_LOAD);

        // ---- Stores — valid funct3 only (3 checks) ----
        $display("\n--- Stores ---");
        inst = mk_s(12'd16, 5'd2, 5'd1, 3'd0); check_class("SB", EXEC_STORE);
        inst = mk_s(12'd16, 5'd2, 5'd1, 3'd1); check_class("SH", EXEC_STORE);
        inst = mk_s(12'd16, 5'd2, 5'd1, 3'd2); check_class("SW", EXEC_STORE);

        // ---- Branches — valid funct3 only (6 checks) ----
        $display("\n--- Branches ---");
        inst = mk_b(13'd8, 5'd2, 5'd1, 3'd0); check_class("BEQ",  EXEC_BRANCH);
        inst = mk_b(13'd8, 5'd2, 5'd1, 3'd1); check_class("BNE",  EXEC_BRANCH);
        inst = mk_b(13'd8, 5'd2, 5'd1, 3'd4); check_class("BLT",  EXEC_BRANCH);
        inst = mk_b(13'd8, 5'd2, 5'd1, 3'd5); check_class("BGE",  EXEC_BRANCH);
        inst = mk_b(13'd8, 5'd2, 5'd1, 3'd6); check_class("BLTU", EXEC_BRANCH);
        inst = mk_b(13'd8, 5'd2, 5'd1, 3'd7); check_class("BGEU", EXEC_BRANCH);

        // ---- LUI, AUIPC, JAL, JALR (4 checks) ----
        $display("\n--- U/J types ---");
        inst = {20'hABCDE, 5'd3, 7'b0110111}; check_class("LUI",   EXEC_LUI);
        inst = {20'h00001, 5'd3, 7'b0010111}; check_class("AUIPC", EXEC_AUIPC);
        inst = {20'd0, 5'd1, 7'b1101111};     check_class("JAL",   EXEC_JAL);
        inst = mk_i(12'd16, 5'd1, 3'd0, 5'd3, 7'b1100111); check_class("JALR", EXEC_JALR);

        // ---- SYSTEM: CSR (3 checks) ----
        $display("\n--- SYSTEM ---");
        inst = {12'h300, 5'd0, 3'b001, 5'd1, 7'b1110011}; check_class("CSRRW", EXEC_SYS);
        inst = {12'h300, 5'd0, 3'b010, 5'd1, 7'b1110011}; check_class("CSRRS", EXEC_SYS);
        inst = {12'h300, 5'd0, 3'b011, 5'd1, 7'b1110011}; check_class("CSRRC", EXEC_SYS);

        // ---- MRET: check csr_cmd (1 check) ----
        inst = 32'h30200073; check_csr("MRET:csr_cmd", CSR_MRET);

        // ---- ECALL/EBREAK → trap (2 checks) ----
        inst = 32'h00000073; check_class("ECALL",  EXEC_ILL);
        inst = 32'h00100073; check_class("EBREAK", EXEC_ILL);

        // ---- FENCE → NOP (1 check) ----
        inst = 32'h0FF0000F; check_class("FENCE", EXEC_ALU_IMM);

        // ---- Illegal opcodes (2 checks) ----
        $display("\n--- Illegal ---");
        inst = 32'h00000000; check_class("ILL:all-zero", EXEC_ILL);
        inst = 32'hFFFFFFFF; check_class("ILL:all-ones", EXEC_ILL);

        // ---- Invalid funct3 should be illegal (4 checks) ----
        $display("\n--- Invalid funct3 ---");
        inst = mk_i(12'd0, 5'd1, 3'd3, 5'd3, 7'b0000011); check_class("LOAD:f3=3 ILL",  EXEC_ILL);
        inst = mk_s(12'd0, 5'd2, 5'd1, 3'd3);              check_class("STORE:f3=3 ILL", EXEC_ILL);
        inst = mk_b(13'd8, 5'd2, 5'd1, 3'd2);              check_class("BR:f3=2 ILL",    EXEC_ILL);
        inst = mk_b(13'd8, 5'd2, 5'd1, 3'd3);              check_class("BR:f3=3 ILL",    EXEC_ILL);

        // ---- M-Extension (funct7=0000001, opcode=0110011): 8 variants ----
        // Each instruction: rd=x3, rs1=x1, rs2=x2
        // funct3 maps 1:1: 000=MUL, 001=MULH, 010=MULHSU, 011=MULHU,
        //                  100=DIV, 101=DIVU, 110=REM, 111=REMU
        $display("\n--- M-Extension (funct7=0000001) ---");
        inst = {7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011}; check_mdu("MUL",    MDU_MUL);
        inst = {7'b0000001, 5'd2, 5'd1, 3'b001, 5'd3, 7'b0110011}; check_mdu("MULH",   MDU_MULH);
        inst = {7'b0000001, 5'd2, 5'd1, 3'b010, 5'd3, 7'b0110011}; check_mdu("MULHSU", MDU_MULHSU);
        inst = {7'b0000001, 5'd2, 5'd1, 3'b011, 5'd3, 7'b0110011}; check_mdu("MULHU",  MDU_MULHU);
        inst = {7'b0000001, 5'd2, 5'd1, 3'b100, 5'd3, 7'b0110011}; check_mdu("DIV",    MDU_DIV);
        inst = {7'b0000001, 5'd2, 5'd1, 3'b101, 5'd3, 7'b0110011}; check_mdu("DIVU",   MDU_DIVU);
        inst = {7'b0000001, 5'd2, 5'd1, 3'b110, 5'd3, 7'b0110011}; check_mdu("REM",    MDU_REM);
        inst = {7'b0000001, 5'd2, 5'd1, 3'b111, 5'd3, 7'b0110011}; check_mdu("REMU",   MDU_REMU);

        // ---- funct7=0000001 but same opcode as ALU → must NOT decode as EXEC_ALU ----
        $display("\n--- funct7=0000001 vs funct7=0000000 disambiguation ---");
        // ADD (funct7=0) → EXEC_ALU
        inst = mk_r(7'b0000000, 5'd2, 5'd1, 3'd0, 5'd3); check_class("ADD  (f7=0→ALU)",  EXEC_ALU);
        // MUL (funct7=1) → EXEC_MDU
        inst = mk_r(7'b0000001, 5'd2, 5'd1, 3'd0, 5'd3); check_class("MUL  (f7=1→MDU)",  EXEC_MDU);
        // SUB (funct7=0100000) → EXEC_ALU
        inst = mk_r(7'b0100000, 5'd2, 5'd1, 3'd0, 5'd3); check_class("SUB  (f7=40→ALU)", EXEC_ALU);

        // ---- Field extraction (3 checks) ----
        $display("\n--- Field extraction ---");
        inst = mk_r(7'b0000000, 5'd15, 5'd10, 3'd0, 5'd20);
        #1;
        check_field5("rs1=10", rs1_addr, 5'd10);
        check_field5("rs2=15", rs2_addr, 5'd15);
        check_field5("rd=20",  rd_addr,  5'd20);

        // ---- Random: valid opcode + valid funct3 (200 checks) ----
        // Only generate KNOWN-VALID instruction encodings
        $display("\n--- Random valid encodings (200 vectors) ---");
        for (ri = 0; ri < 200; ri = ri + 1) begin
            rand_bits = $urandom;
            case ($urandom_range(0, 9))
                // R-type with valid funct7
                0: inst = mk_r(7'b0000000, rand_bits[24:20], rand_bits[19:15],
                               rand_bits[14:12], rand_bits[11:7]);
                // I-ALU: ADDI(f3=0), SLTI(f3=2), SLTIU(f3=3), XORI(f3=4), ORI(f3=6), ANDI(f3=7)
                1: begin
                    case ($urandom_range(0, 5))
                        0: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd0, rand_bits[11:7], 7'b0010011);
                        1: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd2, rand_bits[11:7], 7'b0010011);
                        2: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd3, rand_bits[11:7], 7'b0010011);
                        3: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd4, rand_bits[11:7], 7'b0010011);
                        4: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd6, rand_bits[11:7], 7'b0010011);
                        5: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd7, rand_bits[11:7], 7'b0010011);
                        default: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd0, rand_bits[11:7], 7'b0010011);
                    endcase
                end
                // LOAD: valid funct3 (0,1,2,4,5)
                2: begin
                    case ($urandom_range(0, 4))
                        0: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd0, rand_bits[11:7], 7'b0000011);
                        1: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd1, rand_bits[11:7], 7'b0000011);
                        2: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd2, rand_bits[11:7], 7'b0000011);
                        3: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd4, rand_bits[11:7], 7'b0000011);
                        4: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd5, rand_bits[11:7], 7'b0000011);
                        default: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd2, rand_bits[11:7], 7'b0000011);
                    endcase
                end
                // STORE: valid funct3 (0,1,2)
                3: begin
                    case ($urandom_range(0, 2))
                        0: inst = mk_s(rand_bits[11:0], rand_bits[24:20], rand_bits[19:15], 3'd0);
                        1: inst = mk_s(rand_bits[11:0], rand_bits[24:20], rand_bits[19:15], 3'd1);
                        2: inst = mk_s(rand_bits[11:0], rand_bits[24:20], rand_bits[19:15], 3'd2);
                        default: inst = mk_s(rand_bits[11:0], rand_bits[24:20], rand_bits[19:15], 3'd2);
                    endcase
                end
                // BRANCH: valid funct3 (0,1,4,5,6,7)
                4: begin
                    case ($urandom_range(0, 5))
                        0: inst = mk_b(rand_bits[12:0], rand_bits[24:20], rand_bits[19:15], 3'd0);
                        1: inst = mk_b(rand_bits[12:0], rand_bits[24:20], rand_bits[19:15], 3'd1);
                        2: inst = mk_b(rand_bits[12:0], rand_bits[24:20], rand_bits[19:15], 3'd4);
                        3: inst = mk_b(rand_bits[12:0], rand_bits[24:20], rand_bits[19:15], 3'd5);
                        4: inst = mk_b(rand_bits[12:0], rand_bits[24:20], rand_bits[19:15], 3'd6);
                        5: inst = mk_b(rand_bits[12:0], rand_bits[24:20], rand_bits[19:15], 3'd7);
                        default: inst = mk_b(rand_bits[12:0], rand_bits[24:20], rand_bits[19:15], 3'd0);
                    endcase
                end
                // LUI
                5: inst = {rand_bits[31:12], rand_bits[11:7], 7'b0110111};
                // AUIPC
                6: inst = {rand_bits[31:12], rand_bits[11:7], 7'b0010111};
                // JAL
                7: inst = {rand_bits[31:12], rand_bits[11:7], 7'b1101111};
                // JALR (funct3=0)
                8, 9: inst = mk_i(rand_bits[11:0], rand_bits[19:15], 3'd0, rand_bits[11:7], 7'b1100111);
                default: inst = mk_r(7'b0000000, rand_bits[24:20], rand_bits[19:15],
                                     rand_bits[14:12], rand_bits[11:7]);
            endcase
            #1;
            if (exec_class === EXEC_ILL) begin
                $display("  [FAIL] Random #%0d: inst=0x%08H decoded as ILL", ri, inst);
                fail_cnt++;
            end else
                pass_cnt++;
        end

        // ---- Summary ----
        $display("\n========================================");
        $display("  DECODER FINAL: %0d PASS, %0d FAIL (of %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("========================================");
        if (fail_cnt > 0) $display("  *** FAILURES DETECTED ***");
        else              $display("  *** ALL TESTS PASSED ***");
        #10; $finish;
    end

endmodule
