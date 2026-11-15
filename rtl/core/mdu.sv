`timescale 1ns / 1ps

// ============================================================================
// mdu.sv — Multiply / Divide Unit (RV32IM M-Extension)
//          [BOOTH VARIANT — explicit Radix-4 Booth multiplier]
//
// Architecture (tapeout-ready, tool-portable):
//   Multiplier : 3-stage pipelined with explicit Radix-4 Booth multiplier.
//                Uses booth_multiplier_radix4 module (pure combinational RTL)
//                instead of relying on synthesis tool DesignWare inference.
//                Portable across DC, Genus, Vivado, Yosys, and all simulators.
//   Divider    : 33-cycle restoring iterative FSM (1 bit/cycle).
//                Hand-written subtractor — no / or % operators in RTL.
//
// Reset convention : async active-low (negedge rst_n) — matches core.
//
// Interface:
//   start    : 1-cycle pulse to begin (gated by valid_DE in rv32_core_top)
//   mdu_func : operation select (mdu_func_t from rv32_pkg)
//   rs1/rs2  : 32-bit operands (DE-stage forwarded values)
//   result   : 32-bit output, valid when done=1
//   done     : pulses high exactly 1 cycle when result is ready
//   stall    : high while MDU is computing — fed to hazard_unit
//
// MUL latency  : 3 cycles after start pulse
// DIV latency  : 33 cycles after start pulse (1 init + 32 iterations)
//
// RISC-V M-extension special cases (spec §M, Vol I):
//   DIV/DIVU  by zero → quotient  = -1 / 0xFFFFFFFF
//   REM/REMU  by zero → remainder = rs1
//   DIV  INT32_MIN / -1 → INT32_MIN (no overflow trap)
//   REM  INT32_MIN / -1 → 0
// ============================================================================

module mdu
    import rv32_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Control
    input  logic        start,      // 1-cycle pulse: begin operation
    input  mdu_func_t   mdu_func,   // Operation select

    // Operands
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,

    // Result interface
    output logic [31:0] result,
    output logic        done,       // 1-cycle pulse when result is valid
    output logic        stall       // Held high while busy
);

    // ================================================================
    // FSM State Encoding
    // ================================================================
    typedef enum logic [1:0] {
        IDLE     = 2'b00,
        MUL_BUSY = 2'b01,
        DIV_BUSY = 2'b10,
        DONE_ST  = 2'b11
    } mdu_state_t;

    mdu_state_t state;

    // ================================================================
    // Operands latched on start (stable across multi-cycle operation)
    // ================================================================
    mdu_func_t func_lat;   // latched mdu_func

    // ================================================================
    // ---- MULTIPLIER: 3-stage pipeline --------------------------------
    //
    // Bit-width rationale (why 33×33 → 66, not 32×32 → 64):
    //   RV32M has four MUL variants with different signedness:
    //     MUL    : signed   × signed   → lower 32 of 64-bit product
    //     MULH   : signed   × signed   → upper 32 of 64-bit product
    //     MULHSU : signed   × unsigned → upper 32 of 64-bit product
    //     MULHU  : unsigned × unsigned → upper 32 of 64-bit product
    //
    //   A single $signed() multiply handles ALL four if we extend to
    //   33 bits first:
    //     signed operand  → {rs[31], rs}   (sign-extend: MSB = sign bit)
    //     unsigned operand → {1'b0,  rs}   (zero-extend: MSB = 0)
    //   Then $signed(33'b) * $signed(33'b) always produces the correct
    //   64-bit mathematical product in bits [63:0] of the 66-bit result.
    //   Bits [65:64] are sign-extension overflow and are unused.
    //
    //   Without 33-bit extension, $signed(32'hFFFFFFFF) * $signed(32'hFFFFFFFF)
    //   gives (-1)*(-1)=+1, which is WRONG for MULHU where 0xFFFFFFFF is
    //   +4294967295. The extra MSB disambiguates sign vs. magnitude.
    //
    // Stage 1: Sign/zero-extend operands to 33 bits, register
    // Stage 2: 66-bit registered product (synthesis infers Booth/Wallace)
    // Stage 3: Select upper[63:32] or lower[31:0] half, latch result
    // ================================================================

    // Stage 1
    logic [32:0] mul_a_s1;     // 33-bit operand A (bit32 = sign or 0)
    logic [32:0] mul_b_s1;
    logic [1:0]  mul_sel_s1;   // 00=MUL,01=MULH,10=MULHSU,11=MULHU
    logic        mul_vld_s1;

    // Stage 2
    logic [65:0] mul_prod_s2;  // 66-bit product (33×33)
    logic [1:0]  mul_sel_s2;
    logic        mul_vld_s2;

    // Stage 3 (result latch — feeds into result mux)
    logic [31:0] mul_res_s3;
    logic        mul_vld_s3;

    // ---- Stage 1 ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_a_s1  <= 33'd0;
            mul_b_s1  <= 33'd0;
            mul_sel_s1 <= 2'b00;
            mul_vld_s1 <= 1'b0;
        end else begin
            // Qualify: only enter pipeline on a fresh MUL-group start
            mul_vld_s1 <= (start && (state == IDLE) &&
                           (mdu_func inside {MDU_MUL, MDU_MULH,
                                             MDU_MULHSU, MDU_MULHU}));

            case (mdu_func)
                MDU_MUL, MDU_MULH: begin
                    // Both signed: bit32 = sign bit
                    mul_a_s1 <= {rs1[31], rs1};
                    mul_b_s1 <= {rs2[31], rs2};
                    mul_sel_s1 <= (mdu_func == MDU_MULH) ? 2'b01 : 2'b00;
                end
                MDU_MULHSU: begin
                    // rs1 signed, rs2 unsigned
                    mul_a_s1 <= {rs1[31], rs1};
                    mul_b_s1 <= {1'b0,    rs2};
                    mul_sel_s1 <= 2'b10;
                end
                MDU_MULHU: begin
                    // Both unsigned: bit32 = 0
                    mul_a_s1 <= {1'b0, rs1};
                    mul_b_s1 <= {1'b0, rs2};
                    mul_sel_s1 <= 2'b11;
                end
                default: begin
                    mul_a_s1 <= 33'd0;
                    mul_b_s1 <= 33'd0;
                    mul_sel_s1 <= 2'b00;
                end
            endcase
        end
    end

    // ---- Stage 2: product (explicit Booth multiplier — NO tool inference) ----
    // The Booth multiplier is purely combinational. Its output is registered
    // here in stage 2, maintaining the same 3-stage pipeline latency.
    logic [65:0] booth_product_comb;  // combinational output from Booth unit

    booth_multiplier_radix4 #(
        .WIDTH(33)
    ) u_booth_mul (
        .a       (mul_a_s1),
        .b       (mul_b_s1),
        .product (booth_product_comb)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_prod_s2 <= 66'd0;
            mul_sel_s2  <= 2'b00;
            mul_vld_s2  <= 1'b0;
        end else begin
            mul_prod_s2 <= booth_product_comb;  // register Booth result
            mul_sel_s2  <= mul_sel_s1;
            mul_vld_s2  <= mul_vld_s1;
        end
    end

    // ---- Stage 3: half select ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_res_s3 <= 32'd0;
            mul_vld_s3 <= 1'b0;
        end else begin
            mul_vld_s3 <= mul_vld_s2;
            // mul_sel_s2 != 2'b00 → upper half (MULH/MULHSU/MULHU)
            mul_res_s3 <= (mul_sel_s2 != 2'b00) ? mul_prod_s2[63:32]
                                                  : mul_prod_s2[31:0];
        end
    end

    // ================================================================
    // ---- DIVIDER: 33-cycle restoring iterative FSM ------------------
    //
    // One bit of quotient resolved per clock:
    //   partial_rem = { remainder[30:0], dividend[bit] }  (shift left)
    //   trial       = partial_rem - divisor
    //   if trial[32]=0 (non-negative): quotient bit=1, keep trial
    //   else (negative)             : quotient bit=0, restore partial_rem
    //
    // Signed operations: convert to unsigned, apply sign at the end.
    // Special cases detected before iteration begins (div_special flag).
    // ================================================================

    // Divider operand registers (absolute values during iteration)
    logic [31:0] dividend_r;
    logic [31:0] divisor_r;

    // Iteration state
    logic [5:0]  div_cnt;       // 0 → 32 (33 cycles total)
    logic [31:0] quotient_r;
    logic [32:0] remainder_r;   // 33-bit: bit 32 is trial sign

    // Sign tracking
    logic        neg_quotient;  // quotient result should be negated
    logic        neg_remainder; // remainder result should be negated

    // Special-case bypass
    logic        div_special;
    logic [31:0] div_special_q;
    logic [31:0] div_special_r;

    // Final result register (MUL and DIV share this)
    logic [31:0] result_reg;

    // ================================================================
    // Divider combinational datapath
    // Kept outside always_ff — some synthesis tools (DC, Genus, Yosys)
    // reject automatic variable declarations inside sequential blocks.
    // ================================================================
    logic [32:0] div_partial;    // shifted partial remainder
    logic [32:0] div_trial;      // trial subtraction result
    logic [31:0] q_corrected;    // sign-corrected quotient
    logic [31:0] r_corrected;    // sign-corrected remainder

    always_comb begin
        // Iteration: shift in next dividend bit, trial-subtract divisor
        div_partial = {remainder_r[31:0], dividend_r[31 - div_cnt[4:0]]};
        div_trial   = div_partial - {1'b0, divisor_r};

        // Sign correction (used when iteration completes at div_cnt==32)
        q_corrected = neg_quotient  ? (~quotient_r       + 32'd1) : quotient_r;
        r_corrected = neg_remainder ? (~remainder_r[31:0] + 32'd1) : remainder_r[31:0];
    end

    // ================================================================
    // Main FSM
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            func_lat      <= MDU_MUL;
            dividend_r    <= 32'd0;
            divisor_r     <= 32'd0;
            div_cnt       <= 6'd0;
            quotient_r    <= 32'd0;
            remainder_r   <= 33'd0;
            neg_quotient  <= 1'b0;
            neg_remainder <= 1'b0;
            div_special   <= 1'b0;
            div_special_q <= 32'd0;
            div_special_r <= 32'd0;
            result_reg    <= 32'd0;
        end else begin
            case (state)

                // ---- IDLE ----------------------------------------
                IDLE: begin
                    if (start) begin
                        func_lat <= mdu_func;
                        case (mdu_func)
                            // MUL group — pipeline handles it
                            MDU_MUL, MDU_MULH, MDU_MULHSU, MDU_MULHU:
                                state <= MUL_BUSY;

                            // DIV/REM group — iterative FSM
                            default: begin
                                state   <= DIV_BUSY;
                                div_cnt <= 6'd0;

                                // ---- Special case: divide by zero ----
                                if (rs2 == 32'd0) begin
                                    div_special   <= 1'b1;
                                    // Per spec: quotient=-1 (all ones), remainder=dividend
                                    div_special_q <= 32'hFFFF_FFFF;
                                    div_special_r <= rs1;
                                end
                                // ---- Special case: signed overflow ----
                                else if ((mdu_func == MDU_DIV || mdu_func == MDU_REM) &&
                                         (rs1 == 32'h8000_0000) &&
                                         (rs2 == 32'hFFFF_FFFF)) begin
                                    div_special   <= 1'b1;
                                    div_special_q <= 32'h8000_0000; // INT32_MIN
                                    div_special_r <= 32'd0;
                                end
                                // ---- Normal operation ----
                                else begin
                                    div_special <= 1'b0;

                                    if (mdu_func == MDU_DIV) begin
                                        neg_quotient  <= rs1[31] ^ rs2[31];
                                        neg_remainder <= rs1[31];
                                        dividend_r <= rs1[31] ? (~rs1 + 1'b1) : rs1;
                                        divisor_r  <= rs2[31] ? (~rs2 + 1'b1) : rs2;
                                    end else if (mdu_func == MDU_REM) begin
                                        neg_quotient  <= rs1[31] ^ rs2[31];
                                        neg_remainder <= rs1[31];
                                        dividend_r <= rs1[31] ? (~rs1 + 1'b1) : rs1;
                                        divisor_r  <= rs2[31] ? (~rs2 + 1'b1) : rs2;
                                    end else begin
                                        // DIVU / REMU — fully unsigned
                                        neg_quotient  <= 1'b0;
                                        neg_remainder <= 1'b0;
                                        dividend_r    <= rs1;
                                        divisor_r     <= rs2;
                                    end

                                    quotient_r  <= 32'd0;
                                    remainder_r <= 33'd0;
                                end
                            end
                        endcase
                    end
                end

                // ---- MUL_BUSY: wait for 3-stage pipeline to produce result ----
                MUL_BUSY: begin
                    if (mul_vld_s3) begin
                        result_reg <= mul_res_s3;
                        state      <= DONE_ST;
                    end
                end

                // ---- DIV_BUSY: one iteration per cycle ----
                DIV_BUSY: begin
                    if (div_special) begin
                        // Bypass: output special value immediately
                        result_reg <= (func_lat == MDU_REM || func_lat == MDU_REMU)
                                      ? div_special_r : div_special_q;
                        state      <= DONE_ST;
                    end else if (div_cnt == 6'd32) begin
                        // All 32 bits resolved — apply sign correction
                        case (func_lat)
                            MDU_DIV:  result_reg <= q_corrected;
                            MDU_DIVU: result_reg <= quotient_r;
                            MDU_REM:  result_reg <= r_corrected;
                            MDU_REMU: result_reg <= remainder_r[31:0];
                            default:  result_reg <= quotient_r;
                        endcase
                        state <= DONE_ST;
                    end else begin
                        // Restoring step: shift-and-subtract
                        if (!div_trial[32]) begin
                            // trial >= 0: accept subtraction, quotient bit = 1
                            remainder_r <= div_trial;
                            quotient_r  <= {quotient_r[30:0], 1'b1};
                        end else begin
                            // trial < 0: restore partial, quotient bit = 0
                            remainder_r <= div_partial;
                            quotient_r  <= {quotient_r[30:0], 1'b0};
                        end
                        div_cnt <= div_cnt + 6'd1;
                    end
                end

                // ---- DONE_ST: result valid for this 1 cycle, then back to IDLE ----
                DONE_ST: begin
                    state <= IDLE;
                end

            endcase
        end
    end

    // ================================================================
    // Output assignments
    // ================================================================
    assign stall  = (state == MUL_BUSY) || (state == DIV_BUSY);
    assign done   = (state == DONE_ST);
    assign result = result_reg;

endmodule
