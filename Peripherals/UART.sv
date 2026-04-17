`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02.04.2026 15:30:15
// Design Name: 
// Module Name: uart_tops
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
// TOPS SoC - UART Controller
// PSG College of Technology | VEDA Project
// ============================================================
// SPEC COMPLIANCE:
// Base Address : 0x4001_0000
// End Address  : 0x4001_00FF (256 bytes)
// Interface    : AXI4-Lite 32-bit
// Register Map :
//   Offset 0x00 → TXDATA  (W)   write byte to transmit
//   Offset 0x04 → RXDATA  (R)   read received byte
//   Offset 0x08 → STATUS  (R)   [0]=TX_EMPTY [1]=RX_FULL [2]=TX_BUSY
//   Offset 0x0C → CTRL    (R/W) [15:0]=baud_div [16]=parity_en [17]=enable
//   Offset 0x10 → IRQ_EN  (R/W) [0]=RX_irq_en [1]=TX_irq_en
//   Offset 0x14 → IRQ_CLR (W)   W1C clear RX/TX IRQ flags
// Outputs:
//   uart_tx_o → physical TX pin
//   rx_irq_o  → PLIC source 3 (UART RX Full)
//   tx_irq_o  → PLIC source 4 (UART TX Empty)
// Inputs:
//   uart_rx_i → physical RX pin
// ============================================================

module uart_top (
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

    // ── Physical UART Pins ────────────────────────────────────
    output logic        uart_tx_o,
    input  logic        uart_rx_i,

    // ── Interrupt Outputs → PLIC ──────────────────────────────
    output logic        rx_irq_o,
    output logic        tx_irq_o
);

// ════════════════════════════════════════════════════════════
// INTERNAL REGISTERS
// ════════════════════════════════════════════════════════════

    logic [7:0]  tx_data_reg;
    logic [7:0]  rx_data_reg;
    logic [15:0] baud_div_reg;
    logic        parity_en_reg;
    logic        uart_en_reg;
    logic        rx_irq_en_reg;
    logic        tx_irq_en_reg;

    // ── FIX: Each flag driven by only ONE always_ff block ────
    // rx_irq_flag driven ONLY by AXI write FSM
    // tx_irq_flag driven ONLY by TX state machine + AXI write FSM clear
    logic        rx_irq_flag;
    logic        tx_irq_flag;

// ════════════════════════════════════════════════════════════
// STATUS SIGNALS
// ════════════════════════════════════════════════════════════

    logic        tx_busy;
    logic        tx_empty;
    logic        rx_full;

// ════════════════════════════════════════════════════════════
// BAUD RATE GENERATOR
// 100MHz / 868 = ~115200 baud (default)
// ════════════════════════════════════════════════════════════

    logic [15:0] baud_counter;
    logic        baud_tick;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            baud_counter <= 16'h0;
            baud_tick    <= 1'b0;
        end else begin
            baud_tick <= 1'b0;
            if (baud_counter == baud_div_reg) begin
                baud_counter <= 16'h0;
                baud_tick    <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 16'h1;
            end
        end
    end

// ════════════════════════════════════════════════════════════
// TX LOAD - single driver signal
// Driven ONLY by AXI write FSM
// ════════════════════════════════════════════════════════════

    logic tx_load;

// ════════════════════════════════════════════════════════════
// TX STATE MACHINE
// FIX: tx_load is READ here but NOT driven here
// FIX: tx_irq_flag set here, cleared in AXI write FSM
// ════════════════════════════════════════════════════════════

    typedef enum logic [1:0] {
        TX_IDLE  = 2'b00,
        TX_START = 2'b01,
        TX_DATA  = 2'b10,
        TX_STOP  = 2'b11
    } tx_state_t;

    tx_state_t   tx_state;
    logic [7:0]  tx_shift_reg;
    logic [2:0]  tx_bit_count;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tx_state     <= TX_IDLE;
            uart_tx_o    <= 1'b1;
            tx_shift_reg <= 8'h0;
            tx_bit_count <= 3'h0;
            tx_busy      <= 1'b0;
            tx_empty     <= 1'b1;
            tx_irq_flag  <= 1'b0;
            // ── FIX: tx_load NOT reset here - owned by AXI FSM
        end else begin
            // ── FIX: tx_irq_flag clear handled by AXI FSM
            // TX FSM only SETS tx_irq_flag, never clears it here
            case (tx_state)

                TX_IDLE: begin
                    uart_tx_o <= 1'b1;
                    tx_busy   <= 1'b0;
                    tx_empty  <= 1'b1;
                    if (tx_load) begin
                        // Load shift register when AXI FSM pulses tx_load
                        tx_shift_reg <= tx_data_reg;
                        tx_state     <= TX_START;
                        tx_busy      <= 1'b1;
                        tx_empty     <= 1'b0;
                        tx_irq_flag  <= 1'b0;
                    end
                end

                TX_START: begin
                    if (baud_tick) begin
                        uart_tx_o    <= 1'b0;   // start bit LOW
                        tx_bit_count <= 3'h0;
                        tx_state     <= TX_DATA;
                    end
                end

                TX_DATA: begin
                    if (baud_tick) begin
                        uart_tx_o    <= tx_shift_reg[0]; // LSB first
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        tx_bit_count <= tx_bit_count + 3'h1;
                        if (tx_bit_count == 3'h7)
                            tx_state <= TX_STOP;
                    end
                end

                TX_STOP: begin
                    if (baud_tick) begin
                        uart_tx_o <= 1'b1;   // stop bit HIGH
                        tx_state  <= TX_IDLE;
                        tx_busy   <= 1'b0;
                        tx_empty  <= 1'b1;
                        if (tx_irq_en_reg)
                            tx_irq_flag <= 1'b1; // set IRQ
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

// ════════════════════════════════════════════════════════════
// RX STATE MACHINE
// FIX: rx_irq_flag driven ONLY here - reset in AXI write FSM
// ════════════════════════════════════════════════════════════

    typedef enum logic [1:0] {
        RX_IDLE  = 2'b00,
        RX_START = 2'b01,
        RX_DATA  = 2'b10,
        RX_STOP  = 2'b11
    } rx_state_t;

    rx_state_t   rx_state;
    logic [7:0]  rx_shift_reg;
    logic [2:0]  rx_bit_count;
    logic [15:0] rx_baud_counter;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_state        <= RX_IDLE;
            rx_shift_reg    <= 8'h0;
            rx_bit_count    <= 3'h0;
            rx_data_reg     <= 8'h0;
            rx_full         <= 1'b0;
            rx_irq_flag     <= 1'b0;
            rx_baud_counter <= 16'h0;
            // ── FIX: rx_irq_flag initialized here ONLY
        end else begin
            case (rx_state)

                RX_IDLE: begin
                    if (!uart_rx_i && uart_en_reg) begin
                        // Start bit detected - sample at midpoint
                        rx_baud_counter <= {1'b0, baud_div_reg[15:1]};
                        rx_state        <= RX_START;
                        rx_full         <= 1'b0;
                    end
                end

                RX_START: begin
                    if (rx_baud_counter == 16'h0) begin
                        rx_baud_counter <= baud_div_reg;
                        rx_bit_count    <= 3'h0;
                        rx_state        <= RX_DATA;
                    end else begin
                        rx_baud_counter <= rx_baud_counter - 16'h1;
                    end
                end

                RX_DATA: begin
                    if (rx_baud_counter == 16'h0) begin
                        rx_shift_reg    <= {uart_rx_i, rx_shift_reg[7:1]};
                        rx_baud_counter <= baud_div_reg;
                        rx_bit_count    <= rx_bit_count + 3'h1;
                        if (rx_bit_count == 3'h7)
                            rx_state <= RX_STOP;
                    end else begin
                        rx_baud_counter <= rx_baud_counter - 16'h1;
                    end
                end

                RX_STOP: begin
                    if (rx_baud_counter == 16'h0) begin
                        if (uart_rx_i) begin
                            rx_data_reg <= rx_shift_reg;
                            rx_full     <= 1'b1;
                            if (rx_irq_en_reg)
                                rx_irq_flag <= 1'b1; // set IRQ
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_baud_counter <= rx_baud_counter - 16'h1;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

// ════════════════════════════════════════════════════════════
// INTERRUPT OUTPUTS
// ════════════════════════════════════════════════════════════

    assign rx_irq_o = rx_irq_flag;
    assign tx_irq_o = tx_irq_flag;

// ════════════════════════════════════════════════════════════
// AXI4-LITE WRITE STATE MACHINE
// FIX: tx_load driven ONLY here
// FIX: rx_irq_flag cleared ONLY here
// FIX: tx_irq_flag cleared ONLY here
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
            tx_data_reg   <= 8'h0;
            baud_div_reg  <= 16'd867;  // 115200 at 100MHz
            parity_en_reg <= 1'b0;
            uart_en_reg   <= 1'b0;
            rx_irq_en_reg <= 1'b0;
            tx_irq_en_reg <= 1'b0;
            // ── FIX: tx_load owned and reset here ONLY
            tx_load       <= 1'b0;
        end else begin
            // ── FIX: default tx_load to 0 every cycle
            // It is a 1-cycle pulse set below when TXDATA written
            tx_load <= 1'b0;

            case (wr_state)

                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        wr_state      <= WR_RESP;

                        case (s_axi_awaddr[7:0])

                            // 0x00 - TXDATA
                            8'h00: begin
                                tx_data_reg <= s_axi_wdata[7:0];
                                tx_load     <= 1'b1; // 1-cycle pulse
                            end

                            // 0x0C - CTRL
                            8'h0C: begin
                                baud_div_reg  <= s_axi_wdata[15:0];
                                parity_en_reg <= s_axi_wdata[16];
                                uart_en_reg   <= s_axi_wdata[17];
                            end

                            // 0x10 - IRQ_EN
                            8'h10: begin
                                rx_irq_en_reg <= s_axi_wdata[0];
                                tx_irq_en_reg <= s_axi_wdata[1];
                            end

                            // 0x14 - IRQ_CLR Write-1-to-Clear
                            // FIX: rx_irq_flag and tx_irq_flag
                            // cleared ONLY here
                            8'h14: begin
                                if (s_axi_wdata[0])
                                    rx_irq_flag <= 1'b0;
                                if (s_axi_wdata[1])
                                    tx_irq_flag <= 1'b0;
                            end

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

                            // 0x04 - RXDATA
                            8'h04: s_axi_rdata <=
                                {24'h0, rx_data_reg};

                            // 0x08 - STATUS
                            // [0]=TX_EMPTY [1]=RX_FULL [2]=TX_BUSY
                            8'h08: s_axi_rdata <=
                                {29'h0, tx_busy, rx_full, tx_empty};

                            // 0x0C - CTRL
                            8'h0C: s_axi_rdata <=
                                {14'h0, uart_en_reg,
                                 parity_en_reg, baud_div_reg};

                            // 0x10 - IRQ_EN
                            8'h10: s_axi_rdata <=
                                {30'h0, tx_irq_en_reg, rx_irq_en_reg};

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
