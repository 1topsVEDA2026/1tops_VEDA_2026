// =============================================================================
// ccrc.sv
//
// Clock & Reset Controller for the 1-TOPS VEDA Secure IoT SoC.
//
// Project    : 1-TOPS VEDA Secure IoT RISC-V SoC (RV32IM + ASCON-128)
// Instance   : u_ccrc in soc_top
// Scope      : Divides the analog PLL output into CLK_SYS (100 MHz) and
//              CLK_WDT (32.768 kHz), synchronises PLL_LOCK, combines the
//              three cold-reset sources with the two warm-reset requests,
//              and produces sys_rst_n and wdt_rst_n with proper
//              async-assert / sync-release behaviour.
//
// Interface to the Analog Block (1-TOPS IP):
//   clk_pll   - PLL output (nominal 800 MHz)
//   clk_xtal  - buffered crystal oscillator (25 MHz), used as:
//                 * PLL_LOCK synchroniser reference (always available)
//                 * glitch-free clock mux fallback (while PLL not locked)
//                 * CLK_WDT source (divided by XTAL_LF_DIV)
//   pll_lock  - PLL lock indicator (async; synced inside this block)
//   por_n     - Analog power-on reset (async active-low)
//
// Chip pad input:
//   pad_rstn  - External reset pin (async active-low)
//
// Warm reset requests (both in CLK_SYS domain by the time they reach us):
//   wdt_reset - Watchdog timeout (originates in CLK_WDT; sys_ctrl or wdt
//               block provides a pre-synced version)
//   sw_reset  - Software reset (sys_ctrl APB register write pulse)
//
// Reference: docs/G1_01_Specification_Document.md §1.10
// =============================================================================

module ccrc #(
    // Divide ratio PLL_OUT / N  → CLK_SYS.
    // Default N=8 gives CLK_SYS = 100 MHz with CLK_PLL = 800 MHz.
    // Must be a positive even integer for 50% duty.
    parameter int unsigned PLL_DIV_RATIO = 8,

    // Divide ratio XTAL / M → CLK_WDT (if driving CLK_WDT from the main XTAL).
    // Default M=763 gives 25 MHz / 763 ≈ 32.77 kHz (close to 32.768 kHz).
    // If the analog block provides a dedicated LF oscillator, this divider
    // is bypassed — see USE_ANALOG_LF parameter.
    parameter int unsigned XTAL_LF_DIV = 763,

    // Set to 1 if the analog block provides CLK_LF directly (32.768 kHz).
    // Set to 0 (default) to generate CLK_WDT by dividing clk_xtal.
    parameter bit          USE_ANALOG_LF = 1'b0
)(
    // ---------------- From Analog Block ------------------------------
    input  logic       clk_pll,         // PLL output, ~800 MHz
    input  logic       clk_xtal,        // Crystal buffered, 25 MHz
    input  logic       clk_lf_analog,   // Optional LF osc, 32.768 kHz
    input  logic       pll_lock,        // PLL lock indicator (async)
    input  logic       por_n,           // Power-on reset (async active-low)

    // ---------------- Chip pad input ---------------------------------
    input  logic       pad_rstn,        // External reset pin (async)

    // ---------------- Warm reset requests ----------------------------
    input  logic       wdt_reset,       // From watchdog (pre-synced to CLK_SYS)
    input  logic       sw_reset,        // From sys_ctrl APB write

    // ---------------- Clock outputs ----------------------------------
    output logic       clk_sys,         // 100 MHz, all synchronous digital
    output logic       clk_wdt,         // 32.768 kHz, watchdog counter

    // ---------------- Reset outputs ----------------------------------
    output logic       sys_rst_n,       // Active-low, CLK_SYS domain
    output logic       wdt_rst_n,       // Active-low, CLK_WDT domain

    // ---------------- Status (to sys_ctrl APB) -----------------------
    output logic [3:0] rst_cause,       // One-hot: {SW, WDT, PAD, POR}
    output logic       sync_pll_lock_o  // PLL_LOCK after sync (visible in STATUS)
);

    // ==================================================================
    // 1. PLL_LOCK 2-FF synchroniser
    //    Clocked on clk_xtal (NOT clk_sys) — CLK_SYS may not be stable
    //    until after this signal asserts. clk_xtal is always alive.
    // ==================================================================
    logic pll_lock_meta;
    logic sync_pll_lock;

    always_ff @(posedge clk_xtal or negedge por_n) begin
        if (!por_n) begin
            pll_lock_meta <= 1'b0;
            sync_pll_lock <= 1'b0;
        end else begin
            pll_lock_meta <= pll_lock;
            sync_pll_lock <= pll_lock_meta;
        end
    end

    assign sync_pll_lock_o = sync_pll_lock;

    // ==================================================================
    // 2. Clock divider: PLL_OUT / PLL_DIV_RATIO → clk_pll_div
    //    Simple toggle counter. PLL_DIV_RATIO must be even for 50% duty.
    // ==================================================================
    localparam int unsigned PLL_HALF = PLL_DIV_RATIO/2;

    logic clk_pll_div;
    logic [$clog2(PLL_DIV_RATIO):0] pll_div_cnt;

    always_ff @(posedge clk_pll or negedge por_n) begin
        if (!por_n) begin
            pll_div_cnt <= '0;
            clk_pll_div <= 1'b0;
        end else if (pll_div_cnt == (PLL_HALF-1)) begin
            pll_div_cnt <= '0;
            clk_pll_div <= ~clk_pll_div;
        end else begin
            pll_div_cnt <= pll_div_cnt + 1'b1;
        end
    end

    // ==================================================================
    // 3. Glitch-free clock mux
    //    PLL path once lock stable, XTAL fallback otherwise.
    //
    //    NOTE FOR PHYSICAL DESIGN: replace this ternary with a
    //    standard-cell glitch-free clock mux (e.g. SNPS GTECH_CLK_MUX2)
    //    or an equivalent soft macro. Behavioural model only here.
    // ==================================================================
    logic clk_sys_mux;

    assign clk_sys_mux = sync_pll_lock ? clk_pll_div : clk_xtal;
    assign clk_sys     = clk_sys_mux;

    // ==================================================================
    // 4. CLK_WDT generation
    //    Either (a) divide clk_xtal by XTAL_LF_DIV, or
    //          (b) pass through the analog block's dedicated LF oscillator.
    // ==================================================================
    logic clk_wdt_q;

    generate
        if (USE_ANALOG_LF) begin : g_analog_lf
            assign clk_wdt = clk_lf_analog;
        end else begin : g_xtal_lf
            localparam int unsigned LF_HALF = XTAL_LF_DIV/2;
            logic [$clog2(XTAL_LF_DIV):0] lf_cnt;

            always_ff @(posedge clk_xtal or negedge por_n) begin
                if (!por_n) begin
                    lf_cnt    <= '0;
                    clk_wdt_q <= 1'b0;
                end else if (lf_cnt == (LF_HALF-1)) begin
                    lf_cnt    <= '0;
                    clk_wdt_q <= ~clk_wdt_q;
                end else begin
                    lf_cnt <= lf_cnt + 1'b1;
                end
            end

            assign clk_wdt = clk_wdt_q;
        end
    endgenerate

    // ==================================================================
    // 5. Cold reset combiner
    //    cold_rst_n = POR_N & PAD_RSTN & sync_pll_lock
    //    - Async assertion (any source dropping low asserts immediately)
    //    - Sync release (gated by sync_pll_lock → delayed until PLL stable)
    // ==================================================================
    logic cold_rst_n;
    assign cold_rst_n = por_n & pad_rstn & sync_pll_lock;

    // ==================================================================
    // 6. 2-FF async-assert / sync-release on CLK_SYS
    // ==================================================================
    logic sys_rst_meta;
    logic sys_rst_sync_n;   // sync-released cold reset on CLK_SYS

    always_ff @(posedge clk_sys or negedge cold_rst_n) begin
        if (!cold_rst_n) begin
            sys_rst_meta   <= 1'b0;
            sys_rst_sync_n <= 1'b0;
        end else begin
            sys_rst_meta   <= 1'b1;
            sys_rst_sync_n <= sys_rst_meta;
        end
    end

    // ==================================================================
    // 7. Warm-reset merge
    //    sys_rst_n goes low on:  cold_rst_n = 0, wdt_reset = 1, sw_reset = 1
    //    Warm sources are expected to be in CLK_SYS domain (sys_ctrl
    //    pulses sw_reset; wdt block provides a pre-synced wdt_reset).
    //    They drive sys_rst_n low for at least one CLK_SYS cycle.
    // ==================================================================
    assign sys_rst_n = sys_rst_sync_n & ~wdt_reset & ~sw_reset;

    // ==================================================================
    // 8. Independent 2-FF sync-release on CLK_WDT
    //    wdt_rst_n is released only after cold_rst_n is stable.
    //    Not affected by warm resets — the WDT must keep counting through
    //    a core reset so firmware cannot trivially starve the watchdog.
    // ==================================================================
    logic wdt_rst_meta;
    logic wdt_rst_sync_n;

    always_ff @(posedge clk_wdt or negedge cold_rst_n) begin
        if (!cold_rst_n) begin
            wdt_rst_meta   <= 1'b0;
            wdt_rst_sync_n <= 1'b0;
        end else begin
            wdt_rst_meta   <= 1'b1;
            wdt_rst_sync_n <= wdt_rst_meta;
        end
    end

    assign wdt_rst_n = wdt_rst_sync_n;

    // ==================================================================
    // 9. Reset-cause latch (one-hot)
    //
    //    After any reset, this register captures which source triggered
    //    the latest reset. Priority during a simultaneous assertion:
    //      SW > WDT > PAD > POR
    //    (POR wins by default when everything else is inactive.)
    //
    //    Firmware reads this via sys_ctrl's RST_CAUSE register.
    // ==================================================================
    localparam logic [3:0] CAUSE_POR = 4'b0001;
    localparam logic [3:0] CAUSE_PAD = 4'b0010;
    localparam logic [3:0] CAUSE_WDT = 4'b0100;
    localparam logic [3:0] CAUSE_SW  = 4'b1000;

    logic [3:0] rst_cause_q;

    // Capture on rising edge of CLK_SYS after cold reset release.
    // Updates on warm reset request; frozen until next reset release.
    always_ff @(posedge clk_sys or negedge cold_rst_n) begin
        if (!cold_rst_n) begin
            // Choose cause based on which cold source is still held low
            // at reset release (POR dominant, PAD next).
            // Default to POR for a cold power-up.
            rst_cause_q <= CAUSE_POR;
        end else if (sw_reset) begin
            rst_cause_q <= CAUSE_SW;
        end else if (wdt_reset) begin
            rst_cause_q <= CAUSE_WDT;
        end
    end

    // Capture cold-cause (POR vs PAD) at reset release:
    // if pad_rstn was the last to de-assert, the cause is PAD, else POR.
    // This is a simple approximation; for strictly accurate cause detect
    // use edge-detection flops powered from VDDA with sticky bits.
    logic pad_rst_was_asserted;

    always_ff @(posedge clk_sys or negedge por_n) begin
        if (!por_n)        pad_rst_was_asserted <= 1'b0;
        else if (!pad_rstn) pad_rst_was_asserted <= 1'b1;
    end

    // One-shot refinement: if we exited reset with pad asserted most recently,
    // overwrite POR with PAD cause.
    always_ff @(posedge clk_sys) begin
        if (sys_rst_sync_n && rst_cause_q == CAUSE_POR && pad_rst_was_asserted) begin
            rst_cause_q <= CAUSE_PAD;
        end
    end

    assign rst_cause = rst_cause_q;

    // ==================================================================
    // 10. Simulation assertions
    // ==================================================================
    // synopsys translate_off
    initial begin
        assert (PLL_DIV_RATIO >= 2 && (PLL_DIV_RATIO % 2 == 0))
            else $fatal(1, "ccrc: PLL_DIV_RATIO must be >=2 and even");
        assert (XTAL_LF_DIV >= 2 && (XTAL_LF_DIV % 2 == 0 || USE_ANALOG_LF))
            else $warning("ccrc: XTAL_LF_DIV should be even for 50%% duty cycle");
    end
    // synopsys translate_on

endmodule
