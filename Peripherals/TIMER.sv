`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05.04.2026 17:08:40
// Design Name: 
// Module Name: timer_wdt_tops
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

`timescale 1ns / 1ps
// ============================================================
// TOPS SoC - Timer + Watchdog Timer
// PSG College of Technology | VEDA Project
// ============================================================
// SPEC COMPLIANCE:
// Base Address : 0x4001_3000
// End Address  : 0x4001_30FF (256 bytes)
// Interface    : AXI4-Lite 32-bit
// Register Map :
//   Offset 0x00 → LOAD    (R/W) timer reload value
//   Offset 0x04 → VALUE   (R)   live counter value
//   Offset 0x08 → CTRL    (R/W) [0]=TIMER_EN [1]=IRQ_EN
//                                [2]=WDT_EN [3]=AUTO_RELOAD
//   Offset 0x0C → WDT_KEY (W)   write 0xA5 to refresh WDT
//   Offset 0x10 → IRQ_CLR (W)   W1C clear timer IRQ flag
// Outputs:
//   irq_o     → PLIC source 7 (Timer Tick)
//   wdt_rst_o → PLIC source 8 (Watchdog Timeout) / system reset
// ============================================================

module timer_wdt_tops (
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

    // ── Interrupt and Reset Outputs ───────────────────────────
    output logic        irq_o,      // PLIC source 7 - Timer Tick
    output logic        wdt_rst_o   // PLIC source 8 - WDT Timeout
);

// ════════════════════════════════════════════════════════════
// INTERNAL REGISTERS
// ════════════════════════════════════════════════════════════

    logic [31:0] load_reg;     // LOAD   - reload value
    logic [31:0] value_reg;    // VALUE  - live counter
    logic        timer_en;     // CTRL[0] - timer enable
    logic        irq_en;       // CTRL[1] - IRQ enable
    logic        wdt_en;       // CTRL[2] - WDT enable
    logic        auto_reload;  // CTRL[3] - auto reload

// ════════════════════════════════════════════════════════════
// IRQ FLAG - single driver
// SET by timer, CLEARED by AXI write to IRQ_CLR
// ════════════════════════════════════════════════════════════

    logic        irq_flag;
    logic        timer_zero;   // pulse when counter hits 0

// ════════════════════════════════════════════════════════════
// WDT COUNTER
// ════════════════════════════════════════════════════════════

    logic [31:0] wdt_counter;
    logic        wdt_refresh;  // pulse when 0xA5 written

// ════════════════════════════════════════════════════════════
// TIMER COUNTER
// Counts down from load_reg to 0
// ════════════════════════════════════════════════════════════

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            value_reg  <= 32'h0;
            timer_zero <= 1'b0;
        end else begin
            timer_zero <= 1'b0;
            if (timer_en) begin
                if (value_reg == 32'h0) begin
                    timer_zero <= 1'b1;
                    if (auto_reload)
                        value_reg <= load_reg;
                    else
                        value_reg <= 32'h0;
                end else begin
                    value_reg <= value_reg - 32'h1;
                end
            end
        end
    end

// ════════════════════════════════════════════════════════════
// IRQ FLAG REGISTER - SINGLE DRIVER
// SET when timer hits zero and IRQ enabled
// CLEARED when CPU writes IRQ_CLR
// ════════════════════════════════════════════════════════════

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            irq_flag <= 1'b0;
        end else begin
            // Set on timer zero
            if (timer_zero && irq_en)
                irq_flag <= 1'b1;

            // Clear when CPU writes to IRQ_CLR offset 0x10
            if (s_axi_awvalid && s_axi_wvalid &&
                s_axi_awaddr[7:0] == 8'h10 &&
                s_axi_wdata[0])
                irq_flag <= 1'b0;
        end
    end

    assign irq_o = irq_flag;

// ════════════════════════════════════════════════════════════
// WATCHDOG COUNTER
// Counts up - if reaches max without refresh → reset
// ════════════════════════════════════════════════════════════

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wdt_counter <= 32'h0;
            wdt_rst_o   <= 1'b0;
        end else begin
            wdt_rst_o <= 1'b0;
            if (wdt_en) begin
                if (wdt_refresh) begin
                    wdt_counter <= 32'h0;
                end else begin
                    wdt_counter <= wdt_counter + 32'h1;
                    if (wdt_counter == 32'hFFFF_FFFF)
                        wdt_rst_o <= 1'b1;
                end
            end else begin
                wdt_counter <= 32'h0;
            end
        end
    end

// ════════════════════════════════════════════════════════════
// AXI4-LITE WRITE STATE MACHINE
// wdt_refresh owned ONLY here
// irq_flag clear handled in dedicated block above
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
            load_reg      <= 32'hFFFF_FFFF;
            timer_en      <= 1'b0;
            irq_en        <= 1'b0;
            wdt_en        <= 1'b0;
            auto_reload   <= 1'b0;
            wdt_refresh   <= 1'b0;
        end else begin
            wdt_refresh <= 1'b0;  // default - no refresh

            case (wr_state)

                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        wr_state      <= WR_RESP;

                        case (s_axi_awaddr[7:0])

                            // 0x00 - LOAD
                            8'h00:
                                load_reg <= s_axi_wdata;

                            // 0x08 - CTRL
                            // [0]=TIMER_EN [1]=IRQ_EN
                            // [2]=WDT_EN   [3]=AUTO_RELOAD
                            8'h08: begin
                                timer_en    <= s_axi_wdata[0];
                                irq_en      <= s_axi_wdata[1];
                                wdt_en      <= s_axi_wdata[2];
                                auto_reload <= s_axi_wdata[3];
                            end

                            // 0x0C - WDT_KEY
                            // Write 0xA5 to refresh watchdog
                            8'h0C: begin
                                if (s_axi_wdata[7:0] == 8'hA5)
                                    wdt_refresh <= 1'b1;
                            end

                            // 0x10 - IRQ_CLR
                            // Handled in irq_flag always_ff
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

                            // 0x00 - LOAD
                            8'h00: s_axi_rdata <= load_reg;

                            // 0x04 - VALUE (live counter)
                            8'h04: s_axi_rdata <= value_reg;

                            // 0x08 - CTRL
                            8'h08: s_axi_rdata <=
                                {28'h0, auto_reload,
                                 wdt_en, irq_en, timer_en};

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
