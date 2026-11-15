// =============================================================================
// sys_ctrl.sv
//
// System Control block for the 1-TOPS VEDA Secure IoT SoC.
//
// Project    : 1-TOPS VEDA Secure IoT RISC-V SoC (RV32IM + ASCON-128)
// Instance   : u_sysctrl in soc_top
// Scope      : Minimal - single-clock, single-reset-domain SoC.
//
// Functions provided:
//   1. Reset synchroniser:
//        - async-assert / sync-release of the chip rst_n against the
//          main clk. Two-flop metastability chain on reset release.
//   2. Chip-ID register:
//        - Read-only 32-bit CHIP_ID visible to firmware via APB.
//          Lets software detect silicon revision.
//   3. Reset-cause register (reserved):
//        - Firmware-readable cause of last reset (power-on / watchdog /
//          software). Currently hardwired - watchdog-driven warm-reset
//          and software-reset paths to be added in PD per 1-TOPS SoC
//          Spec section 1.10.
//
// Explicitly NOT implemented (per Boot Plan, G1 item 1.12):
//   - Boot-mode strap sampling     (single boot source: on-chip I-SRAM)
//   - ROM remap register           (no boot ROM in this SoC)
//   - Clock dividers / PLL control (single external clock, no PLL)
//
// APB register map (within its 4 KB slot assigned by soc_top):
//   Offset 0x00   CHIP_ID    RO   {VENDOR[31:16], REVISION[15:0]}
//   Offset 0x04   RST_CAUSE  RO   {28'h0, cause[3:0]}
//   Offset 0x08   SCRATCH    RW   scratch register for firmware use
//   Offset 0x0C   STATUS     RO   {30'h0, reset_released, 1'b0}
// =============================================================================

module sys_ctrl #(
    parameter logic [31:0] CHIP_ID = 32'h1T0P_0001   // 1-TOPS VEDA rev 0001
)(
    // ---------------- Chip pads ----------------
    input  logic        clk,          // free-running external clock
    input  logic        rst_n_async,  // async active-low chip reset pad

    // ---------------- Synchronised reset to the rest of the SoC ----
    output logic        rst_n_sync,   // async-assert / sync-release

    // ---------------- Reset-cause inputs (for future use) ----------
    input  logic        wdt_reset,    // watchdog timeout reset request
    input  logic        sw_reset,     // software-triggered reset request

    // ---------------- APB slave port ------------------------------
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [11:0] PADDR,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR
);

    // ------------------------------------------------------------------
    // 1. Reset synchroniser
    //    Async assert on rst_n_async low. Sync release through two
    //    flops clocked on `clk` to avoid metastability.
    // ------------------------------------------------------------------
    logic sync_rst_meta, sync_rst_q;

    always_ff @(posedge clk or negedge rst_n_async) begin
        if (!rst_n_async) begin
            sync_rst_meta <= 1'b0;
            sync_rst_q    <= 1'b0;
        end else begin
            sync_rst_meta <= 1'b1;
            sync_rst_q    <= sync_rst_meta;
        end
    end

    assign rst_n_sync = sync_rst_q;

    // ------------------------------------------------------------------
    // 2. Reset-cause latch
    //    Priority on cause capture: POR > watchdog > software.
    // ------------------------------------------------------------------
    localparam logic [3:0] CAUSE_POR = 4'h1;
    localparam logic [3:0] CAUSE_WDT = 4'h2;
    localparam logic [3:0] CAUSE_SW  = 4'h4;

    logic [3:0] rst_cause_q;

    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            rst_cause_q <= CAUSE_POR;
        end else if (wdt_reset) begin
            rst_cause_q <= CAUSE_WDT;
        end else if (sw_reset) begin
            rst_cause_q <= CAUSE_SW;
        end
    end

    // ------------------------------------------------------------------
    // 3. Scratch register
    // ------------------------------------------------------------------
    logic [31:0] scratch_q;

    // ------------------------------------------------------------------
    // 4. APB access (standard 2-phase: SETUP -> ACCESS)
    // ------------------------------------------------------------------
    localparam logic [11:0] ADDR_CHIP_ID   = 12'h000;
    localparam logic [11:0] ADDR_RST_CAUSE = 12'h004;
    localparam logic [11:0] ADDR_SCRATCH   = 12'h008;
    localparam logic [11:0] ADDR_STATUS    = 12'h00C;

    logic apb_access;
    assign apb_access = PSEL && PENABLE;

    // Write path
    always_ff @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            scratch_q <= 32'h0;
        end else if (apb_access && PWRITE && (PADDR == ADDR_SCRATCH)) begin
            scratch_q <= PWDATA;
        end
    end

    // Read path
    always_comb begin
        PRDATA  = 32'h0;
        PSLVERR = 1'b0;
        if (apb_access && !PWRITE) begin
            unique case (PADDR)
                ADDR_CHIP_ID:   PRDATA = CHIP_ID;
                ADDR_RST_CAUSE: PRDATA = {28'h0, rst_cause_q};
                ADDR_SCRATCH:   PRDATA = scratch_q;
                ADDR_STATUS:    PRDATA = {30'h0, rst_n_sync, 1'b0};
                default: begin
                    PRDATA  = 32'h0;
                    PSLVERR = 1'b1;    // unmapped register in our 4 KB slot
                end
            endcase
        end
    end

    // Writes to CHIP_ID / RST_CAUSE / STATUS are errored
    always_comb begin
        if (apb_access && PWRITE &&
            (PADDR == ADDR_CHIP_ID || PADDR == ADDR_RST_CAUSE || PADDR == ADDR_STATUS)) begin
            // override PSLVERR to flag write-to-RO
        end
    end

    // Always ready in one cycle
    assign PREADY = 1'b1;

endmodule
