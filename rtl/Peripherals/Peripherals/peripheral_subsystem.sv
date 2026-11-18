// =============================================================================
// TOPS Peripheral Subsystem
// =============================================================================
// Integrates all 7 APB peripherals with an APB address decoder.
// This module represents the entire peripheral subsystem that connects
// to the AXI-to-APB bridge in the full SoC.
//
// Address Map (relative to subsystem base):
//   0x0000 - 0x0FFF : UART       (Slot 0)
//   0x1000 - 0x1FFF : SPI        (Slot 1)
//   0x2000 - 0x2FFF : GPIO       (Slot 2)
//   0x3000 - 0x3FFF : Timer      (Slot 3)
//   0x4000 - 0x4FFF : Watchdog   (Slot 4)
//   0x5000 - 0x5FFF : PLIC       (Slot 5)
//   0x6000 - 0x6FFF : CLINT      (Slot 6)
//
// For full SoC integration, connect the APB master port to the
// AXI-to-APB bridge output. The SoC base address (e.g., 0x1000_0000)
// is decoded by the AXI interconnect before reaching this subsystem.

module peripheral_subsystem #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    // CLINT parameters
    parameter int CLINT_N_SOURCE   = 16,
    parameter int CLINT_INTCTLBITS = 8,
    // PLIC parameters
    parameter int PLIC_N_SOURCE = 30,
    parameter int PLIC_N_TARGET = 2,
    parameter int PLIC_MAX_PRIO = 7,
    // GPIO
    parameter int NrGPIOs = 32,
    // SPI
    parameter int SPI_BUFFER_DEPTH = 10
)(
    input  logic clk_i,
    input  logic rst_ni,

    // =========================================================================
    // APB Slave Interface (from AXI-to-APB bridge or VIP)
    // =========================================================================
    input  logic                    psel_i,
    input  logic                    penable_i,
    input  logic                    pwrite_i,
    input  logic [ADDR_WIDTH-1:0]  paddr_i,
    input  logic [DATA_WIDTH-1:0]  pwdata_i,
    input  logic [DATA_WIDTH/8-1:0] pstrb_i,
    output logic [DATA_WIDTH-1:0]  prdata_o,
    output logic                    pready_o,
    output logic                    pslverr_o,

    // =========================================================================
    // UART I/O
    // =========================================================================
    input  logic                    uart_sin_i,
    output logic                    uart_sout_o,
    output logic                    uart_rtsn_o,
    input  logic                    uart_ctsn_i,
    output logic                    uart_dtrn_o,
    input  logic                    uart_dsrn_i,
    input  logic                    uart_dcdn_i,
    input  logic                    uart_rin_i,
    output logic                    uart_irq_o,

    // =========================================================================
    // SPI I/O
    // =========================================================================
    output logic                    spi_clk_o,
    output logic                    spi_csn0_o,
    output logic                    spi_csn1_o,
    output logic                    spi_csn2_o,
    output logic                    spi_csn3_o,
    output logic [1:0]              spi_mode_o,
    output logic                    spi_sdo0_o,
    output logic                    spi_sdo1_o,
    output logic                    spi_sdo2_o,
    output logic                    spi_sdo3_o,
    input  logic                    spi_sdi0_i,
    input  logic                    spi_sdi1_i,
    input  logic                    spi_sdi2_i,
    input  logic                    spi_sdi3_i,
    output logic [1:0]              spi_events_o,

    // =========================================================================
    // GPIO I/O
    // =========================================================================
    input  logic [NrGPIOs-1:0]      gpio_in_i,
    output logic [NrGPIOs-1:0]      gpio_out_o,
    output logic [NrGPIOs-1:0]      gpio_tx_en_o,
    output logic [NrGPIOs-1:0]      gpio_in_sync_o,
    output logic                    gpio_irq_o,
    output logic [NrGPIOs-1:0]      gpio_pin_irqs_o,

    // =========================================================================
    // Timer IRQ
    // =========================================================================
    output logic [3:0]              timer_irq_o,

    // =========================================================================
    // Watchdog outputs
    // =========================================================================
    output logic                    wdt_irq_o,
    output logic                    wdt_reset_o,

    // =========================================================================
    // PLIC I/O
    // =========================================================================
    input  logic [PLIC_N_SOURCE-1:0] plic_irq_sources_i,
    input  logic [PLIC_N_SOURCE-1:0] plic_le_i,
    output logic [PLIC_N_TARGET-1:0] plic_eip_targets_o,

    // =========================================================================
    // CLINT I/O
    // =========================================================================
    input  logic [CLINT_N_SOURCE-1:0] clint_intr_src_i,
    output logic                      clint_irq_valid_o,
    input  logic                      clint_irq_ready_i,
    output logic [$clog2(CLINT_N_SOURCE)-1:0] clint_irq_id_o,
    output logic [7:0]                clint_irq_level_o,
    output logic                      clint_irq_shv_o,
    output logic [1:0]                clint_irq_priv_o
);

    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam NUM_SLAVES = 7;

    // Peripheral slot indices
    localparam SLOT_UART     = 0;
    localparam SLOT_SPI      = 1;
    localparam SLOT_GPIO     = 2;
    localparam SLOT_TIMER    = 3;
    localparam SLOT_WATCHDOG = 4;
    localparam SLOT_PLIC     = 5;
    localparam SLOT_CLINT    = 6;

    // =========================================================================
    // APB Interconnect Signals
    // =========================================================================
    logic [NUM_SLAVES-1:0]                  s_psel;
    logic                                   s_penable;
    logic                                   s_pwrite;
    logic [ADDR_WIDTH-1:0]                  s_paddr;
    logic [DATA_WIDTH-1:0]                  s_pwdata;
    logic [DATA_WIDTH/8-1:0]                s_pstrb;
    logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]  s_prdata;
    logic [NUM_SLAVES-1:0]                  s_pready;
    logic [NUM_SLAVES-1:0]                  s_pslverr;

    // =========================================================================
    // APB Interconnect
    // =========================================================================
    apb_interconnect #(
        .NUM_SLAVES     ( NUM_SLAVES ),
        .ADDR_WIDTH     ( ADDR_WIDTH ),
        .DATA_WIDTH     ( DATA_WIDTH ),
        .SLOT_ADDR_BITS ( 12         )
    ) u_apb_interconnect (
        .psel_i     ( psel_i    ),
        .penable_i  ( penable_i ),
        .pwrite_i   ( pwrite_i  ),
        .paddr_i    ( paddr_i   ),
        .pwdata_i   ( pwdata_i  ),
        .pstrb_i    ( pstrb_i   ),
        .prdata_o   ( prdata_o  ),
        .pready_o   ( pready_o  ),
        .pslverr_o  ( pslverr_o ),
        .psel_o     ( s_psel    ),
        .penable_o  ( s_penable ),
        .pwrite_o   ( s_pwrite  ),
        .paddr_o    ( s_paddr   ),
        .pwdata_o   ( s_pwdata  ),
        .pstrb_o    ( s_pstrb   ),
        .prdata_i   ( s_prdata  ),
        .pready_i   ( s_pready  ),
        .pslverr_i  ( s_pslverr )
    );

    // =========================================================================
    // Slot 0: UART
    // =========================================================================
    logic uart_out1n, uart_out2n;

    apb_uart u_uart (
        .CLK     ( clk_i                        ),
        .RSTN    ( rst_ni                       ),
        .PSEL    ( s_psel[SLOT_UART]            ),
        .PENABLE ( s_penable                    ),
        .PWRITE  ( s_pwrite                     ),
        .PADDR   ( s_paddr[2:0]                 ),
        .PWDATA  ( s_pwdata                     ),
        .PRDATA  ( s_prdata[SLOT_UART]          ),
        .PREADY  ( s_pready[SLOT_UART]          ),
        .PSLVERR ( s_pslverr[SLOT_UART]         ),
        .INT     ( uart_irq_o                   ),
        .OUT1N   ( uart_out1n                   ),
        .OUT2N   ( uart_out2n                   ),
        .RTSN    ( uart_rtsn_o                  ),
        .DTRN    ( uart_dtrn_o                  ),
        .CTSN    ( uart_ctsn_i                  ),
        .DSRN    ( uart_dsrn_i                  ),
        .DCDN    ( uart_dcdn_i                  ),
        .RIN     ( uart_rin_i                   ),
        .SIN     ( uart_sin_i                   ),
        .SOUT    ( uart_sout_o                  )
    );

    // =========================================================================
    // Slot 1: SPI Master
    // =========================================================================
    apb_spi_master #(
        .BUFFER_DEPTH   ( SPI_BUFFER_DEPTH ),
        .APB_ADDR_WIDTH ( 12               )
    ) u_spi (
        .HCLK     ( clk_i                  ),
        .HRESETn  ( rst_ni                 ),
        .PADDR    ( s_paddr[11:0]           ),
        .PWDATA   ( s_pwdata               ),
        .PWRITE   ( s_pwrite               ),
        .PSEL     ( s_psel[SLOT_SPI]       ),
        .PENABLE  ( s_penable              ),
        .PRDATA   ( s_prdata[SLOT_SPI]     ),
        .PREADY   ( s_pready[SLOT_SPI]     ),
        .PSLVERR  ( s_pslverr[SLOT_SPI]   ),
        .events_o ( spi_events_o           ),
        .spi_clk  ( spi_clk_o             ),
        .spi_csn0 ( spi_csn0_o            ),
        .spi_csn1 ( spi_csn1_o            ),
        .spi_csn2 ( spi_csn2_o            ),
        .spi_csn3 ( spi_csn3_o            ),
        .spi_mode ( spi_mode_o            ),
        .spi_sdo0 ( spi_sdo0_o            ),
        .spi_sdo1 ( spi_sdo1_o            ),
        .spi_sdo2 ( spi_sdo2_o            ),
        .spi_sdo3 ( spi_sdo3_o            ),
        .spi_sdi0 ( spi_sdi0_i            ),
        .spi_sdi1 ( spi_sdi1_i            ),
        .spi_sdi2 ( spi_sdi2_i            ),
        .spi_sdi3 ( spi_sdi3_i            )
    );

    // =========================================================================
    // Slot 2: GPIO
    // =========================================================================
    // GPIO uses struct-based APB — create local struct types and wire them

    typedef struct packed {
        logic [DATA_WIDTH/8-1:0] pstrb;
        logic [DATA_WIDTH-1:0]   pwdata;
        logic                    pwrite;
        logic                    penable;
        logic                    psel;
        logic [2:0]              pprot;
        logic [ADDR_WIDTH-1:0]   paddr;
    } gpio_apb_req_t;

    typedef struct packed {
        logic                    pslverr;
        logic                    pready;
        logic [DATA_WIDTH-1:0]   prdata;
    } gpio_apb_rsp_t;

    gpio_apb_req_t gpio_req;
    gpio_apb_rsp_t gpio_rsp;

    assign gpio_req.paddr   = {20'd0, s_paddr[11:0]};
    assign gpio_req.pprot   = 3'b000;
    assign gpio_req.psel    = s_psel[SLOT_GPIO];
    assign gpio_req.penable = s_penable;
    assign gpio_req.pwrite  = s_pwrite;
    assign gpio_req.pwdata  = s_pwdata;
    assign gpio_req.pstrb   = s_pstrb;

    assign s_prdata[SLOT_GPIO]  = gpio_rsp.prdata;
    assign s_pready[SLOT_GPIO]  = gpio_rsp.pready;
    assign s_pslverr[SLOT_GPIO] = gpio_rsp.pslverr;

    gpio_apb_wrap #(
        .ADDR_WIDTH ( ADDR_WIDTH     ),
        .DATA_WIDTH ( DATA_WIDTH     ),
        .apb_req_t  ( gpio_apb_req_t ),
        .apb_rsp_t  ( gpio_apb_rsp_t )
    ) u_gpio (
        .clk_i                  ( clk_i            ),
        .rst_ni                 ( rst_ni           ),
        .gpio_in                ( gpio_in_i        ),
        .gpio_out               ( gpio_out_o       ),
        .gpio_tx_en_o           ( gpio_tx_en_o     ),
        .gpio_in_sync_o         ( gpio_in_sync_o   ),
        .global_interrupt_o     ( gpio_irq_o       ),
        .pin_level_interrupts_o ( gpio_pin_irqs_o  ),
        .apb_req_i              ( gpio_req         ),
        .apb_rsp_o              ( gpio_rsp         )
    );

    // =========================================================================
    // Slot 3: Timer
    // =========================================================================
    apb_timer #(
        .APB_ADDR_WIDTH ( 12 ),
        .TIMER_CNT      ( 2  )
    ) u_timer (
        .HCLK    ( clk_i                    ),
        .HRESETn ( rst_ni                   ),
        .PADDR   ( s_paddr[11:0]             ),
        .PWDATA  ( s_pwdata                 ),
        .PWRITE  ( s_pwrite                 ),
        .PSEL    ( s_psel[SLOT_TIMER]       ),
        .PENABLE ( s_penable                ),
        .PRDATA  ( s_prdata[SLOT_TIMER]     ),
        .PREADY  ( s_pready[SLOT_TIMER]     ),
        .PSLVERR ( s_pslverr[SLOT_TIMER]   ),
        .irq_o   ( timer_irq_o              )
    );

    // =========================================================================
    // Slot 4: Watchdog Timer
    // =========================================================================
    apb_watchdog #(
        .APB_ADDR_WIDTH ( 12 )
    ) u_watchdog (
        .HCLK       ( clk_i                      ),
        .HRESETn    ( rst_ni                     ),
        .PADDR      ( s_paddr[11:0]               ),
        .PWDATA     ( s_pwdata                   ),
        .PWRITE     ( s_pwrite                   ),
        .PSEL       ( s_psel[SLOT_WATCHDOG]      ),
        .PENABLE    ( s_penable                  ),
        .PRDATA     ( s_prdata[SLOT_WATCHDOG]    ),
        .PREADY     ( s_pready[SLOT_WATCHDOG]    ),
        .PSLVERR    ( s_pslverr[SLOT_WATCHDOG]   ),
        .wdt_irq_o  ( wdt_irq_o                  ),
        .wdt_reset_o( wdt_reset_o                )
    );

    // =========================================================================
    // Slot 5: PLIC
    // =========================================================================
    // PLIC uses reg_req_t/reg_rsp_t — adapt from APB

    typedef struct packed {
        logic                        valid;
        logic [ADDR_WIDTH-1:0]       addr;
        logic                        write;
        logic [DATA_WIDTH/8-1:0]     wstrb;
        logic [DATA_WIDTH-1:0]       wdata;
    } plic_reg_req_t;

    typedef struct packed {
        logic                        ready;
        logic [DATA_WIDTH-1:0]       rdata;
        logic                        error;
    } plic_reg_rsp_t;

    plic_reg_req_t plic_req;
    plic_reg_rsp_t plic_rsp;

    logic plic_access;
    assign plic_access = s_psel[SLOT_PLIC] && s_penable;

    logic [31:0] plic_addr_mapped;
    always_comb begin
        case (s_paddr[11:0])
            12'h100: plic_addr_mapped = 32'h0C00_2000; // Enable Target 0
            12'h180: plic_addr_mapped = 32'h0C00_2080; // Enable Target 1
            12'h200: plic_addr_mapped = 32'h0C20_0000; // Threshold Target 0
            12'h204: plic_addr_mapped = 32'h0C20_0004; // Claim/Complete Target 0
            12'h300: plic_addr_mapped = 32'h0C21_0000; // Threshold Target 1
            12'h304: plic_addr_mapped = 32'h0C21_0004; // Claim/Complete Target 1
            12'h080: plic_addr_mapped = 32'h0C00_1000; // Pending
            default: begin
                if (s_paddr[11:0] <= 12'h078)
                    plic_addr_mapped = 32'h0C00_0000 + s_paddr[11:0]; // Priority 0..30
                else
                    plic_addr_mapped = s_paddr;
            end
        endcase
    end

    assign plic_req.valid = plic_access;
    assign plic_req.addr  = plic_addr_mapped;
    assign plic_req.write = s_pwrite;
    assign plic_req.wstrb = s_pstrb;
    assign plic_req.wdata = s_pwdata;

    assign s_prdata[SLOT_PLIC]  = plic_rsp.rdata;
    assign s_pready[SLOT_PLIC]  = plic_rsp.ready;
    assign s_pslverr[SLOT_PLIC] = plic_rsp.error;

    plic_top #(
        .N_SOURCE   ( PLIC_N_SOURCE  ),
        .N_TARGET   ( PLIC_N_TARGET  ),
        .MAX_PRIO   ( PLIC_MAX_PRIO  ),
        .reg_req_t  ( plic_reg_req_t ),
        .reg_rsp_t  ( plic_reg_rsp_t )
    ) u_plic (
        .clk_i          ( clk_i              ),
        .rst_ni         ( rst_ni             ),
        .req_i          ( plic_req           ),
        .resp_o         ( plic_rsp           ),
        .le_i           ( plic_le_i          ),
        .irq_sources_i  ( plic_irq_sources_i ),
        .eip_targets_o  ( plic_eip_targets_o )
    );

    // =========================================================================
    // Slot 6: CLINT (CLIC)
    // =========================================================================
    logic clint_irq_kill_req, clint_irq_kill_ack;
    assign clint_irq_kill_ack = clint_irq_kill_req;

    clic_apb #(
        .N_SOURCE   ( CLINT_N_SOURCE   ),
        .INTCTLBITS ( CLINT_INTCTLBITS ),
        .SSCLIC     ( 0                ),
        .USCLIC     ( 0                ),
        .VSCLIC     ( 0                ),
        .N_VSCTXTS  ( 0                ),
        .VSPRIO     ( 0                ),
        .VSPRIO_W   ( 1                )
    ) u_clint (
        .clk_i          ( clk_i                      ),
        .rst_ni         ( rst_ni                     ),
        .penable_i      ( s_penable                  ),
        .pwrite_i       ( s_pwrite                   ),
        .paddr_i        ( s_paddr                    ),
        .psel_i         ( s_psel[SLOT_CLINT]         ),
        .pwdata_i       ( s_pwdata                   ),
        .prdata_o       ( s_prdata[SLOT_CLINT]       ),
        .pready_o       ( s_pready[SLOT_CLINT]       ),
        .pslverr_o      ( s_pslverr[SLOT_CLINT]     ),
        .intr_src_i     ( clint_intr_src_i           ),
        .irq_valid_o    ( clint_irq_valid_o          ),
        .irq_ready_i    ( clint_irq_ready_i          ),
        .irq_id_o       ( clint_irq_id_o             ),
        .irq_level_o    ( clint_irq_level_o          ),
        .irq_shv_o      ( clint_irq_shv_o            ),
        .irq_priv_o     ( clint_irq_priv_o           ),
        .irq_vsid_o     (                            ),
        .irq_v_o        (                            ),
        .irq_kill_req_o ( clint_irq_kill_req         ),
        .irq_kill_ack_i ( clint_irq_kill_ack         )
    );

endmodule : peripheral_subsystem
