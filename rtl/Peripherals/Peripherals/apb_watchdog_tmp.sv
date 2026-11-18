// Copyright 2025 TOPS RISC-V SoC Project
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// APB Watchdog Timer - Top Level
// Reference: EF_WDT32 (Efabless, Apache-2.0) and PULP apb_timer style
// Features:
//   - 32-bit down-counter with configurable timeout value
//   - 8-bit prescaler for clock division
//   - Window watchdog mode (early service detection)
//   - Timeout interrupt output
//   - System reset output on second timeout (if not serviced)
//   - APB slave interface (matching PULP SoC peripheral style)

module apb_watchdog #(
    parameter APB_ADDR_WIDTH = 12  // APB slaves are 4KB by default
)(
    input  logic                      HCLK,
    input  logic                      HRESETn,

    // APB Slave Interface
    input  logic [APB_ADDR_WIDTH-1:0] PADDR,
    input  logic               [31:0] PWDATA,
    input  logic                      PWRITE,
    input  logic                      PSEL,
    input  logic                      PENABLE,
    output logic               [31:0] PRDATA,
    output logic                      PREADY,
    output logic                      PSLVERR,

    // Watchdog outputs
    output logic                      wdt_irq_o,     // Timeout interrupt
    output logic                      wdt_reset_o    // System reset (2nd timeout)
);

    // =========================================================================
    // Register Map (byte addresses, 32-bit aligned)
    // =========================================================================
    // 0x00 : WDT_CR   - Control Register
    //        [0]    : EN       - Watchdog enable
    //        [1]    : RSTEN    - Reset enable (assert wdt_reset_o on 2nd timeout)
    //        [2]    : IRQEN    - Interrupt enable
    //        [3]    : WINEN    - Window mode enable
    //        [7:4]  : PSC      - Prescaler (2^PSC division)
    // 0x04 : WDT_SR   - Status Register (read-only, write-1-to-clear)
    //        [0]    : TIMEOUT  - Timeout flag
    //        [1]    : EWIF     - Early wakeup interrupt flag (window mode)
    // 0x08 : WDT_LOAD - Load/Timeout Value Register (sets counter reload value)
    // 0x0C : WDT_CNT  - Counter Value Register (read-only, current count)
    // 0x10 : WDT_WIN  - Window Value Register (window upper bound)
    // 0x14 : WDT_KEY  - Key Register (write 0x5A5A_5A5A to service/reload WDT)

    localparam ADDR_WDT_CR   = 6'h00;
    localparam ADDR_WDT_SR   = 6'h01;
    localparam ADDR_WDT_LOAD = 6'h02;
    localparam ADDR_WDT_CNT  = 6'h03;
    localparam ADDR_WDT_WIN  = 6'h04;
    localparam ADDR_WDT_KEY  = 6'h05;

    localparam WDT_KEY_VALUE = 32'h5A5A_5A5A;

    // =========================================================================
    // Registers
    // =========================================================================
    logic [7:0]  reg_cr;        // Control register
    logic [1:0]  reg_sr;        // Status register
    logic [31:0] reg_load;      // Load value
    logic [31:0] reg_cnt;       // Counter value
    logic [31:0] reg_win;       // Window value

    // Derived control signals
    logic        wdt_en;
    logic        rst_en;
    logic        irq_en;
    logic        win_en;
    logic [3:0]  prescaler_val;

    assign wdt_en        = reg_cr[0];
    assign rst_en        = reg_cr[1];
    assign irq_en        = reg_cr[2];
    assign win_en        = reg_cr[3];
    assign prescaler_val = reg_cr[7:4];

    // =========================================================================
    // Prescaler
    // =========================================================================
    logic [15:0] psc_counter;
    logic        psc_tick;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            psc_counter <= '0;
        end else if (wdt_en) begin
            if (psc_counter >= ((16'h1 << prescaler_val) - 1)) begin
                psc_counter <= '0;
            end else begin
                psc_counter <= psc_counter + 1;
            end
        end else begin
            psc_counter <= '0;
        end
    end

    assign psc_tick = wdt_en && (psc_counter >= ((16'h1 << prescaler_val) - 1));

    // =========================================================================
    // Watchdog Counter (down-counter)
    // =========================================================================
    logic        timeout_event;
    logic        service_request;
    logic        service_valid;
    logic        second_timeout;  // Flag for reset generation

    // Service is valid when KEY register is written with correct value
    // In window mode, service is only valid when counter < window value
    assign service_valid = service_request &&
                           (!win_en || (reg_cnt <= reg_win));

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            reg_cnt        <= 32'hFFFF_FFFF;
            timeout_event  <= 1'b0;
            second_timeout <= 1'b0;
        end else begin
            timeout_event <= 1'b0;

            if (service_valid) begin
                // Reload counter on valid service
                reg_cnt        <= reg_load;
                second_timeout <= 1'b0;
            end else if (wdt_en && psc_tick) begin
                if (reg_cnt == 32'h0) begin
                    // Timeout!
                    timeout_event <= 1'b1;
                    reg_cnt       <= reg_load;  // Auto-reload
                    if (reg_sr[0]) begin
                        // Already had a timeout without service -> 2nd timeout
                        second_timeout <= 1'b1;
                    end
                end else begin
                    reg_cnt <= reg_cnt - 1;
                end
            end
        end
    end

    // =========================================================================
    // Status Register
    // =========================================================================
    logic sr_clear_timeout;
    logic sr_clear_ewif;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            reg_sr <= 2'b00;
        end else begin
            // Set on timeout
            if (timeout_event)
                reg_sr[0] <= 1'b1;

            // Set early wakeup flag (window mode: service when cnt > win)
            if (service_request && win_en && (reg_cnt > reg_win))
                reg_sr[1] <= 1'b1;

            // Clear on write-1-to-clear
            if (sr_clear_timeout)
                reg_sr[0] <= 1'b0;
            if (sr_clear_ewif)
                reg_sr[1] <= 1'b0;
        end
    end

    // =========================================================================
    // Output Generation
    // =========================================================================
    assign wdt_irq_o   = irq_en && reg_sr[0];
    assign wdt_reset_o = rst_en && second_timeout;

    // =========================================================================
    // APB Interface
    // =========================================================================
    logic [5:0] addr_word;
    assign addr_word = PADDR[7:2];  // Word-aligned address decode

    assign PREADY  = 1'b1;    // Always ready (no wait states)
    assign PSLVERR = 1'b0;    // No errors

    // Write logic
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            reg_cr          <= 8'h00;
            reg_load        <= 32'hFFFF_FFFF;
            reg_win         <= 32'hFFFF_FFFF;
            service_request <= 1'b0;
            sr_clear_timeout <= 1'b0;
            sr_clear_ewif    <= 1'b0;
        end else begin
            service_request  <= 1'b0;
            sr_clear_timeout <= 1'b0;
            sr_clear_ewif    <= 1'b0;

            if (PSEL && PENABLE && PWRITE) begin
                case (addr_word)
                    ADDR_WDT_CR:   reg_cr   <= PWDATA[7:0];
                    ADDR_WDT_SR: begin
                        // Write-1-to-clear
                        if (PWDATA[0]) sr_clear_timeout <= 1'b1;
                        if (PWDATA[1]) sr_clear_ewif    <= 1'b1;
                    end
                    ADDR_WDT_LOAD: reg_load <= PWDATA;
                    ADDR_WDT_WIN:  reg_win  <= PWDATA;
                    ADDR_WDT_KEY: begin
                        if (PWDATA == WDT_KEY_VALUE)
                            service_request <= 1'b1;
                    end
                    default: ; // Ignore writes to read-only/reserved
                endcase
            end
        end
    end

    // Read logic
    always_comb begin
        PRDATA = 32'h0;
        if (PSEL && !PWRITE) begin
            case (addr_word)
                ADDR_WDT_CR:   PRDATA = {24'h0, reg_cr};
                ADDR_WDT_SR:   PRDATA = {30'h0, reg_sr};
                ADDR_WDT_LOAD: PRDATA = reg_load;
                ADDR_WDT_CNT:  PRDATA = reg_cnt;
                ADDR_WDT_WIN:  PRDATA = reg_win;
                ADDR_WDT_KEY:  PRDATA = 32'h0;  // KEY is write-only
                default:       PRDATA = 32'h0;
            endcase
        end
    end

endmodule
