`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 31.03.2026 11:16:39
// Design Name: 
// Module Name: clint_tops
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// ============================================================
// TOPS SoC - CLINT (Core Local Interrupt Timer)
// PSG College of Technology | VEDA Project
// ============================================================
// SPEC COMPLIANCE:
// Base Address : 0x0200_0000
// End Address  : 0x0200_FFFF (64 KB)
// Interface    : AXI4-Lite 32-bit
// Register Map :
//   Offset 0x0000 → MSIP        (R/W) bit[0] = software IRQ
//   Offset 0x4000 → MTIMECMP_LO (R/W) lower 32 bits
//   Offset 0x4004 → MTIMECMP_HI (R/W) upper 32 bits
//   Offset 0xBFF8 → MTIME_LO    (R)   lower 32 bits
//   Offset 0xBFFC → MTIME_HI    (R)   upper 32 bits
// Outputs:
//   msip_o → directly to RV32IM machine software IRQ pin
//   mtip_o → directly to RV32IM machine timer IRQ pin
// ============================================================

module clint_top (
    // ── Clock and Reset ──────────────────────────────────────
    input  logic        clk_i,    // 100 MHz system clock
    input  logic        rst_ni,   // Active-low async reset

    // ── AXI4-Lite Slave - Write Address Channel ───────────────
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // ── AXI4-Lite Slave - Write Data Channel ─────────────────
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // ── AXI4-Lite Slave - Write Response Channel ─────────────
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // ── AXI4-Lite Slave - Read Address Channel ────────────────
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // ── AXI4-Lite Slave - Read Data Channel ──────────────────
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // ── Interrupt Outputs to RV32IM Core ─────────────────────
    output logic        msip_o,   // Machine Software Interrupt
    output logic        mtip_o    // Machine Timer Interrupt
);

// ════════════════════════════════════════════════════════════
// INTERNAL REGISTERS
// ════════════════════════════════════════════════════════════

    // MSIP register - offset 0x0000
    // bit[0] = 1 triggers software interrupt to CPU
    logic        msip_reg;

    // MTIMECMP register - offset 0x4000/0x4004
    // Timer IRQ fires when mtime >= mtimecmp
    // Initialized to MAX so no spurious IRQ at boot
    logic [63:0] mtimecmp_reg;

    // MTIME register - offset 0xBFF8/0xBFFC
    // Free-running counter - increments every clock cycle
    // At 100 MHz: 1 tick = 10 ns
    logic [63:0] mtime_reg;

// ════════════════════════════════════════════════════════════
// FREE RUNNING COUNTER
// Increments every single clock cycle at 100 MHz
// Firmware reads this to get current system time
// ════════════════════════════════════════════════════════════

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            mtime_reg <= 64'h0;
        else
            mtime_reg <= mtime_reg + 64'h1;
    end

// ════════════════════════════════════════════════════════════
// INTERRUPT OUTPUT LOGIC
// ════════════════════════════════════════════════════════════

    // Software interrupt - direct from MSIP register
    assign msip_o = msip_reg;

    // Timer interrupt - fires when mtime >= mtimecmp
    assign mtip_o = (mtime_reg >= mtimecmp_reg) ? 1'b1 : 1'b0;

// ════════════════════════════════════════════════════════════
// AXI4-LITE WRITE STATE MACHINE
// Handles CPU writing to MSIP and MTIMECMP registers
// ════════════════════════════════════════════════════════════

    typedef enum logic [1:0] {
        WR_IDLE = 2'b00,
        WR_RESP = 2'b01
    } wr_state_t;

    wr_state_t wr_state;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;  // OKAY response
            // Safe reset values
            msip_reg      <= 1'b0;
            mtimecmp_reg  <= 64'hFFFF_FFFF_FFFF_FFFF;
        end else begin
            case (wr_state)

                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;

                    // Wait for CPU to send both address AND data
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        wr_state      <= WR_RESP;

                        // ── Register Write Decode ─────────────
                        // Use bits [15:0] for offset within 64KB

                        // MSIP - offset 0x0000
                        if (s_axi_awaddr[15:0] == 16'h0000)
                            msip_reg <= s_axi_wdata[0];

                        // MTIMECMP_LO - offset 0x4000
                        if (s_axi_awaddr[15:0] == 16'h4000)
                            mtimecmp_reg[31:0]  <= s_axi_wdata;

                        // MTIMECMP_HI - offset 0x4004
                        if (s_axi_awaddr[15:0] == 16'h4004)
                            mtimecmp_reg[63:32] <= s_axi_wdata;

                        // MTIME is READ ONLY - writes ignored
                    end
                end

                WR_RESP: begin
                    // Send write response to CPU
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;  // OKAY
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

// ════════════════════════════════════════════════════════════
// AXI4-LITE READ STATE MACHINE
// Handles CPU reading MSIP, MTIMECMP, MTIME registers
// ════════════════════════════════════════════════════════════

    typedef enum logic [1:0] {
        RD_IDLE = 2'b00,
        RD_DATA = 2'b01
    } rd_state_t;

    rd_state_t rd_state;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'h0;
            s_axi_rresp   <= 2'b00;
        end else begin
            case (rd_state)

                RD_IDLE: begin
                    s_axi_arready <= 1'b1;

                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b0;
                        rd_state      <= RD_DATA;
                        s_axi_rdata   <= 32'h0;   // default
                        s_axi_rresp   <= 2'b00;   // OKAY

                        // ── Register Read Decode ──────────────

                        // MSIP - offset 0x0000
                        if (s_axi_araddr[15:0] == 16'h0000)
                            s_axi_rdata <= {31'h0, msip_reg};

                        // MTIMECMP_LO - offset 0x4000
                        if (s_axi_araddr[15:0] == 16'h4000)
                            s_axi_rdata <= mtimecmp_reg[31:0];

                        // MTIMECMP_HI - offset 0x4004
                        if (s_axi_araddr[15:0] == 16'h4004)
                            s_axi_rdata <= mtimecmp_reg[63:32];

                        // MTIME_LO - offset 0xBFF8 (READ ONLY)
                        if (s_axi_araddr[15:0] == 16'hBFF8)
                            s_axi_rdata <= mtime_reg[31:0];

                        // MTIME_HI - offset 0xBFFC (READ ONLY)
                        if (s_axi_araddr[15:0] == 16'hBFFC)
                            s_axi_rdata <= mtime_reg[63:32];
                    end
                end

                RD_DATA: begin
                    s_axi_rvalid <= 1'b1;
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
