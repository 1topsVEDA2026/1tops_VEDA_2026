`timescale 1ns / 1ps
// ============================================================
// TOPS SoC - GPIO Controller
// PSG College of Technology | VEDA Project
// ============================================================
// SPEC COMPLIANCE:
// Base Address : 0x4001_2000
// End Address  : 0x4001_20FF (256 bytes)
// Interface    : AXI4-Lite 32-bit
// Register Map :
//   Offset 0x00 → DATA_OUT (R/W) output values GPIO[15:0]
//   Offset 0x04 → DATA_IN  (R)   current input pin levels
//   Offset 0x08 → DIR      (R/W) 1=output 0=input per pin
//   Offset 0x0C → IRQ_EN   (R/W) edge interrupt enable per pin
//   Offset 0x10 → IRQ_CLR  (W)   W1C clear GPIO interrupt flags
// Outputs:
//   gpio_out_o[15:0]  → GPIO output values
//   gpio_oe_o[15:0]   → GPIO output enable (1=output)
//   gpio_irq_o        → PLIC source 6 (GPIO Edge Detect)
// Inputs:
//   gpio_in_i[15:0]   → GPIO input values from pads
// ============================================================

module gpio_top (
    // ── Clock and Reset ──────────────────────────────────────
    input  logic        clk_i,
    input  logic        rst_ni,

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

    // ── Physical GPIO Pins ────────────────────────────────────
    input  logic [15:0] gpio_in_i,
    output logic [15:0] gpio_out_o,
    output logic [15:0] gpio_oe_o,

    // ── Interrupt Output → PLIC ───────────────────────────────
    output logic        gpio_irq_o
);

// ════════════════════════════════════════════════════════════
// INTERNAL REGISTERS
// ════════════════════════════════════════════════════════════

    logic [15:0] data_out_reg;
    logic [15:0] dir_reg;
    logic [15:0] irq_en_reg;

    // ── FIX: irq_flag_reg driven by ONE block only ────────────
    logic [15:0] irq_flag_reg;

// ════════════════════════════════════════════════════════════
// GPIO OUTPUT CONNECTIONS
// ════════════════════════════════════════════════════════════

    assign gpio_out_o = data_out_reg;
    assign gpio_oe_o  = dir_reg;

// ════════════════════════════════════════════════════════════
// INPUT SYNCHRONIZER
// Double-register to avoid metastability
// ════════════════════════════════════════════════════════════

    logic [15:0] gpio_in_sync1;
    logic [15:0] gpio_in_sync;
    logic [15:0] gpio_in_prev;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_in_sync1 <= 16'h0;
            gpio_in_sync  <= 16'h0;
            gpio_in_prev  <= 16'h0;
        end else begin
            gpio_in_sync1 <= gpio_in_i;
            gpio_in_sync  <= gpio_in_sync1;
            gpio_in_prev  <= gpio_in_sync;
        end
    end

// ════════════════════════════════════════════════════════════
// EDGE DETECTION - combinational only
// FIX: irq_set is wire, not a register
// This detects rising edge but does NOT drive irq_flag_reg
// ════════════════════════════════════════════════════════════

    logic [15:0] irq_set;

    always_comb begin
        for (int i = 0; i < 16; i++) begin
            // Rising edge on input pin with IRQ enabled
            irq_set[i] = !dir_reg[i]       &&
                          irq_en_reg[i]    &&
                          gpio_in_sync[i]  &&
                         !gpio_in_prev[i];
        end
    end

// ════════════════════════════════════════════════════════════
// IRQ FLAG REGISTER - SINGLE DRIVER
// FIX: This is the ONLY always_ff that drives irq_flag_reg
// SET by irq_set (edge detection)
// CLEARED by AXI write to IRQ_CLR offset 0x10
// ════════════════════════════════════════════════════════════

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            irq_flag_reg <= 16'h0;
        end else begin
            // Default: set new edge flags while keeping old ones
            irq_flag_reg <= irq_flag_reg | irq_set;

            // Clear flags when CPU writes to IRQ_CLR (0x10)
            // W1C: write 1 to clear that bit
            if (s_axi_awvalid && s_axi_wvalid &&
                s_axi_awaddr[7:0] == 8'h10) begin
                irq_flag_reg <= (irq_flag_reg | irq_set) &
                                 ~s_axi_wdata[15:0];
            end
        end
    end

    // OR all pending flags → single IRQ wire to PLIC
    assign gpio_irq_o = |irq_flag_reg;

// ════════════════════════════════════════════════════════════
// AXI4-LITE WRITE STATE MACHINE
// FIX: irq_flag_reg NOT driven here anymore
// Only data_out_reg, dir_reg, irq_en_reg handled here
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
            s_axi_bresp   <= 2'b00;
            data_out_reg  <= 16'h0;
            dir_reg       <= 16'h0;
            irq_en_reg    <= 16'h0;
        end else begin
            case (wr_state)

                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        wr_state      <= WR_RESP;

                        case (s_axi_awaddr[7:0])

                            // 0x00 - DATA_OUT
                            8'h00:
                                data_out_reg <= s_axi_wdata[15:0];

                            // 0x08 - DIR
                            8'h08:
                                dir_reg <= s_axi_wdata[15:0];

                            // 0x0C - IRQ_EN
                            8'h0C:
                                irq_en_reg <= s_axi_wdata[15:0];

                            // 0x10 - IRQ_CLR
                            // FIX: irq_flag_reg NOT cleared here
                            // It is cleared in the dedicated
                            // irq_flag_reg always_ff block above
                            // This case kept empty intentionally
                            8'h10: ;

                            default: ;
                        endcase
                    end
                end

                WR_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00;
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
                        s_axi_rdata   <= 32'h0;
                        s_axi_rresp   <= 2'b00;

                        case (s_axi_araddr[7:0])

                            // 0x00 - DATA_OUT
                            8'h00: s_axi_rdata <=
                                {16'h0, data_out_reg};

                            // 0x04 - DATA_IN
                            8'h04: s_axi_rdata <=
                                {16'h0, gpio_in_sync};

                            // 0x08 - DIR
                            8'h08: s_axi_rdata <=
                                {16'h0, dir_reg};

                            // 0x0C - IRQ_EN
                            8'h0C: s_axi_rdata <=
                                {16'h0, irq_en_reg};

                            default: s_axi_rdata <= 32'h0;
                        endcase
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
