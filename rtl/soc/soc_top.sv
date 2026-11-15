`timescale 1ns / 1ps
// ============================================================================
// soc_top.sv — Full System-on-Chip Top-Level Integration
//
// Connects:
//   1. RISC-V Core Top (RV32IM Pipeline with MDU & AXI4)
//   2. AXI4 Instruction Memory Slave (IMEM)
//   3. AXI4 Data Memory Slave (DMEM / Internal RAM)
//   4. AXI4-to-APB Bridge (Interconnect to Peripherals)
//   5. Peripheral Subsystem (GPIO, UART, SPI, Timer, Watchdog, PLIC, CLINT)
//
// Memory Map:
//   0x0000_0000 – 0x0000_0FFF : Instruction Memory (IMEM) — AXI4 Read-only
//   0x0000_1000 – 0x0000_1FFF : Data Memory (DMEM/RAM)    — AXI4 R/W
//   0x0000_2000 – 0x0000_FFFF : Peripheral Subsystem       — via AXI4-to-APB bridge
//
// Peripheral Sub-Map (relative to 0x0000_2000):
//   +0x0000 – +0x0FFF : UART    (Slot 0)
//   +0x1000 – +0x1FFF : SPI     (Slot 1)
//   +0x2000 – +0x2FFF : GPIO    (Slot 2)
//   +0x3000 – +0x3FFF : Timer   (Slot 3)
//   +0x4000 – +0x4FFF : Watchdog(Slot 4)
//   +0x5000 – +0x5FFF : PLIC    (Slot 5)
//   +0x6000 – +0x6FFF : CLINT   (Slot 6)
// ============================================================================

module soc_top (
    input  logic        clk,
    input  logic        rst_n,

    // ====================================================================
    // GPIO I/O
    // ====================================================================
    input  logic [31:0] gpio_in,
    output logic [31:0] gpio_out,
    output logic [31:0] gpio_oe,          // GPIO output-enable (tx_en)

    // ====================================================================
    // UART I/O
    // ====================================================================
    input  logic        uart_rx,
    output logic        uart_tx,

    // ====================================================================
    // SPI I/O
    // ====================================================================
    output logic        spi_sclk,
    output logic        spi_csn,
    output logic        spi_mosi,
    input  logic        spi_miso,

    // ====================================================================
    // Watchdog
    // ====================================================================
    output logic        wdt_reset_o,

    // ====================================================================
    // APB Bus Monitoring Interface (for UVM Passive Monitor)
    // ====================================================================
    output logic [31:0] mon_apb_paddr,
    output logic [31:0] mon_apb_pwdata,
    output logic [31:0] mon_apb_prdata,
    output logic        mon_apb_pwrite,
    output logic        mon_apb_psel,
    output logic        mon_apb_penable,
    output logic        mon_apb_pready,
    output logic        mon_apb_pslverr
);

    // ====================================================================
    // 1. Core IMEM AXI4 Wires
    // ====================================================================
    logic [31:0] imem_araddr;
    logic        imem_arvalid, imem_arready;
    logic [ 7:0] imem_arlen;
    logic [ 2:0] imem_arsize;
    logic [ 1:0] imem_arburst;
    logic [ 3:0] imem_arcache;
    logic [ 2:0] imem_arprot;
    logic        imem_arlock;
    logic [31:0] imem_rdata;
    logic        imem_rvalid, imem_rready;
    logic [ 1:0] imem_rresp;
    logic        imem_rlast;

    // ====================================================================
    // 2. Core DMEM AXI4 Wires
    // ====================================================================
    logic [31:0] dmem_awaddr;
    logic        dmem_awvalid, dmem_awready;
    logic [ 7:0] dmem_awlen;
    logic [ 2:0] dmem_awsize;
    logic [ 1:0] dmem_awburst;
    logic [ 3:0] dmem_awcache;
    logic [ 2:0] dmem_awprot;
    logic        dmem_awlock;

    logic [31:0] dmem_wdata;
    logic [ 3:0] dmem_wstrb;
    logic        dmem_wvalid, dmem_wready, dmem_wlast;

    logic        dmem_bvalid, dmem_bready;
    logic [ 1:0] dmem_bresp;

    logic [31:0] dmem_araddr;
    logic        dmem_arvalid, dmem_arready;
    logic [ 7:0] dmem_arlen;
    logic [ 2:0] dmem_arsize;
    logic [ 1:0] dmem_arburst;
    logic [ 3:0] dmem_arcache;
    logic [ 2:0] dmem_arprot;
    logic        dmem_arlock;

    logic [31:0] dmem_rdata;
    logic        dmem_rvalid, dmem_rready, dmem_rlast;
    logic [ 1:0] dmem_rresp;

    // ====================================================================
    // 3. Address Demux — RAM vs Peripheral Bridge
    // ====================================================================
    // Peripheral region: address >= 0x0000_2000
    logic is_periph_wr, is_periph_rd, is_periph_req;
    assign is_periph_wr  = (dmem_awaddr >= 32'h0000_2000);
    assign is_periph_rd  = (dmem_araddr >= 32'h0000_2000);
    // Use write address for write transactions, read address for read
    assign is_periph_req = (dmem_awvalid && is_periph_wr) ||
                           (dmem_arvalid && is_periph_rd && !dmem_awvalid);

    // RAM AXI Slave Signals
    logic        ram_awready, ram_wready, ram_bvalid;
    logic [ 1:0] ram_bresp;
    logic        ram_arready, ram_rvalid;
    logic [31:0] ram_rdata;
    logic [ 1:0] ram_rresp;
    logic        ram_rlast;

    // Bridge AXI Slave Signals
    logic        brg_awready, brg_wready, brg_bvalid;
    logic [ 1:0] brg_bresp;
    logic        brg_arready, brg_rvalid;
    logic [31:0] brg_rdata;
    logic [ 1:0] brg_rresp;
    logic        brg_rlast;

    // Response Mux: select based on which slave was addressed
    // Use a registered flag to remember which slave was targeted
    logic periph_wr_active, periph_rd_active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            periph_wr_active <= 1'b0;
            periph_rd_active <= 1'b0;
        end else begin
            // Latch on write address handshake
            if (dmem_awvalid && dmem_awready)
                periph_wr_active <= is_periph_wr;
            else if (dmem_bvalid && dmem_bready)
                periph_wr_active <= 1'b0;

            // Latch on read address handshake
            if (dmem_arvalid && dmem_arready)
                periph_rd_active <= is_periph_rd;
            else if (dmem_rvalid && dmem_rready)
                periph_rd_active <= 1'b0;
        end
    end

    // Write channel demux
    assign dmem_awready = is_periph_wr ? brg_awready : ram_awready;
    assign dmem_wready  = is_periph_wr ? brg_wready  : ram_wready;
    assign dmem_bvalid  = periph_wr_active ? brg_bvalid  : ram_bvalid;
    assign dmem_bresp   = periph_wr_active ? brg_bresp   : ram_bresp;

    // Read channel demux
    assign dmem_arready = is_periph_rd ? brg_arready : ram_arready;
    assign dmem_rvalid  = periph_rd_active ? brg_rvalid  : ram_rvalid;
    assign dmem_rdata   = periph_rd_active ? brg_rdata   : ram_rdata;
    assign dmem_rresp   = periph_rd_active ? brg_rresp   : ram_rresp;
    assign dmem_rlast   = periph_rd_active ? brg_rlast   : ram_rlast;

    // ====================================================================
    // 4. Interrupt Wires
    // ====================================================================
    logic        irq_external, irq_timer, irq_software;
    logic        wdt_irq;
    logic [3:0]  timer_irq;
    logic        gpio_irq;
    logic        uart_irq;
    logic [1:0]  plic_eip;

    // External IRQ = OR of all peripheral interrupts fed through PLIC
    assign irq_external = plic_eip[0];
    // Timer IRQ from timer peripheral
    assign irq_timer    = timer_irq[0];
    // No software interrupt source in this SoC
    assign irq_software = 1'b0;

    // ====================================================================
    // 5. Instantiate RISC-V Core Top
    // ====================================================================
    rv32_core_top u_core (
        .clk          (clk),
        .rst_n        (rst_n),

        // IMEM AXI4
        .imem_araddr  (imem_araddr),
        .imem_arvalid (imem_arvalid),
        .imem_arready (imem_arready),
        .imem_arlen   (imem_arlen),
        .imem_arsize  (imem_arsize),
        .imem_arburst (imem_arburst),
        .imem_arcache (imem_arcache),
        .imem_arprot  (imem_arprot),
        .imem_arlock  (imem_arlock),
        .imem_rdata   (imem_rdata),
        .imem_rvalid  (imem_rvalid),
        .imem_rready  (imem_rready),
        .imem_rresp   (imem_rresp),
        .imem_rlast   (imem_rlast),

        // DMEM AXI4
        .dmem_awaddr  (dmem_awaddr),
        .dmem_awvalid (dmem_awvalid),
        .dmem_awready (dmem_awready),
        .dmem_awlen   (dmem_awlen),
        .dmem_awsize  (dmem_awsize),
        .dmem_awburst (dmem_awburst),
        .dmem_awcache (dmem_awcache),
        .dmem_awprot  (dmem_awprot),
        .dmem_awlock  (dmem_awlock),
        .dmem_wdata   (dmem_wdata),
        .dmem_wstrb   (dmem_wstrb),
        .dmem_wvalid  (dmem_wvalid),
        .dmem_wlast   (dmem_wlast),
        .dmem_wready  (dmem_wready),
        .dmem_bvalid  (dmem_bvalid),
        .dmem_bresp   (dmem_bresp),
        .dmem_bready  (dmem_bready),
        .dmem_araddr  (dmem_araddr),
        .dmem_arvalid (dmem_arvalid),
        .dmem_arready (dmem_arready),
        .dmem_arlen   (dmem_arlen),
        .dmem_arsize  (dmem_arsize),
        .dmem_arburst (dmem_arburst),
        .dmem_arcache (dmem_arcache),
        .dmem_arprot  (dmem_arprot),
        .dmem_arlock  (dmem_arlock),
        .dmem_rdata   (dmem_rdata),
        .dmem_rvalid  (dmem_rvalid),
        .dmem_rready  (dmem_rready),
        .dmem_rresp   (dmem_rresp),
        .dmem_rlast   (dmem_rlast),

        // IRQs
        .irq_external (irq_external),
        .irq_timer    (irq_timer),
        .irq_software (irq_software)
    );

    // ====================================================================
    // 6. Instantiate AXI4 Instruction Memory Slave
    // ====================================================================
    axi4_imem_slave u_imem (
        .clk      (clk),
        .rst_n    (rst_n),
        .araddr   (imem_araddr),
        .arvalid  (imem_arvalid),
        .arready  (imem_arready),
        .arlen    (imem_arlen),
        .arsize   (imem_arsize),
        .arburst  (imem_arburst),
        .arcache  (imem_arcache),
        .arprot   (imem_arprot),
        .arlock   (imem_arlock),
        .rdata    (imem_rdata),
        .rvalid   (imem_rvalid),
        .rlast    (imem_rlast),
        .rresp    (imem_rresp),
        .rready   (imem_rready),
        .delay_en (1'b0)
    );

    // ====================================================================
    // 7. Instantiate AXI4 Data Memory Slave (Internal RAM)
    // ====================================================================
    axi4_dmem_slave u_dmem_ram (
        .clk      (clk),
        .rst_n    (rst_n),
        .awaddr   (dmem_awaddr),
        .awvalid  (dmem_awvalid && !is_periph_wr),
        .awready  (ram_awready),
        .awlen    (dmem_awlen),
        .awsize   (dmem_awsize),
        .awburst  (dmem_awburst),
        .awcache  (dmem_awcache),
        .awprot   (dmem_awprot),
        .awlock   (dmem_awlock),
        .wdata    (dmem_wdata),
        .wstrb    (dmem_wstrb),
        .wvalid   (dmem_wvalid && !is_periph_wr),
        .wlast    (dmem_wlast),
        .wready   (ram_wready),
        .bvalid   (ram_bvalid),
        .bresp    (ram_bresp),
        .bready   (dmem_bready),
        .araddr   (dmem_araddr),
        .arvalid  (dmem_arvalid && !is_periph_rd),
        .arready  (ram_arready),
        .arlen    (dmem_arlen),
        .arsize   (dmem_arsize),
        .arburst  (dmem_arburst),
        .arcache  (dmem_arcache),
        .arprot   (dmem_arprot),
        .arlock   (dmem_arlock),
        .rdata    (ram_rdata),
        .rvalid   (ram_rvalid),
        .rlast    (ram_rlast),
        .rresp    (ram_rresp),
        .rready   (dmem_rready),
        .delay_en (1'b0)
    );

    // ====================================================================
    // 8. Instantiate AXI4-to-APB Bridge
    // ====================================================================
    logic [31:0] apb_paddr, apb_pwdata, apb_prdata;
    logic        apb_pwrite, apb_psel, apb_penable, apb_pready, apb_pslverr;

    axi4_to_apb_bridge u_bridge (
        .clk         (clk),
        .rst_n       (rst_n),

        // AXI Slave Interface (from Core DMEM master, gated by demux)
        .axi_awaddr  (dmem_awaddr),
        .axi_awvalid (dmem_awvalid && is_periph_wr),
        .axi_awready (brg_awready),
        .axi_awsize  (dmem_awsize),

        .axi_wdata   (dmem_wdata),
        .axi_wstrb   (dmem_wstrb),
        .axi_wvalid  (dmem_wvalid && is_periph_wr),
        .axi_wready  (brg_wready),

        .axi_bvalid  (brg_bvalid),
        .axi_bresp   (brg_bresp),
        .axi_bready  (dmem_bready),

        .axi_araddr  (dmem_araddr),
        .axi_arvalid (dmem_arvalid && is_periph_rd),
        .axi_arready (brg_arready),
        .axi_arsize  (dmem_arsize),

        .axi_rdata   (brg_rdata),
        .axi_rvalid  (brg_rvalid),
        .axi_rresp   (brg_rresp),
        .axi_rlast   (brg_rlast),
        .axi_rready  (dmem_rready),

        // APB Master Interface (to Peripheral Subsystem)
        .apb_paddr   (apb_paddr),
        .apb_pwdata  (apb_pwdata),
        .apb_pwrite  (apb_pwrite),
        .apb_psel    (apb_psel),
        .apb_penable (apb_penable),
        .apb_prdata  (apb_prdata),
        .apb_pready  (apb_pready),
        .apb_pslverr (apb_pslverr)
    );

    // Bind monitoring signals for UVM passive monitor
    assign mon_apb_paddr   = apb_paddr;
    assign mon_apb_pwdata  = apb_pwdata;
    assign mon_apb_prdata  = apb_prdata;
    assign mon_apb_pwrite  = apb_pwrite;
    assign mon_apb_psel    = apb_psel;
    assign mon_apb_penable = apb_penable;
    assign mon_apb_pready  = apb_pready;
    assign mon_apb_pslverr = apb_pslverr;

    // ====================================================================
    // 9. Instantiate Peripheral Subsystem
    //    Port mapping to actual OpenTitan-style peripheral_subsystem ports
    // ====================================================================

    // PLIC interrupt sources: wire all peripheral IRQs to PLIC inputs
    // Source mapping: [0]=uart, [1]=gpio, [2]=timer0, [3]=wdt, rest=0
    localparam int PLIC_N_SRC = 30;
    logic [PLIC_N_SRC-1:0] plic_irq_sources;
    assign plic_irq_sources[0]              = uart_irq;
    assign plic_irq_sources[1]              = gpio_irq;
    assign plic_irq_sources[2]              = timer_irq[0];
    assign plic_irq_sources[3]              = wdt_irq;
    assign plic_irq_sources[PLIC_N_SRC-1:4] = '0;

    // CLINT sources: tie to peripheral IRQs for simple use
    localparam int CLINT_N_SRC = 16;
    logic [CLINT_N_SRC-1:0] clint_intr_src;
    assign clint_intr_src = '0;  // No CLINT interrupt sources wired for now

    peripheral_subsystem #(
        .ADDR_WIDTH       (32),
        .DATA_WIDTH       (32),
        .CLINT_N_SOURCE   (CLINT_N_SRC),
        .CLINT_INTCTLBITS (8),
        .PLIC_N_SOURCE    (PLIC_N_SRC),
        .PLIC_N_TARGET    (2),
        .PLIC_MAX_PRIO    (7),
        .NrGPIOs          (32),
        .SPI_BUFFER_DEPTH (10)
    ) u_periph_subsys (
        // Clock & Reset
        .clk_i          (clk),
        .rst_ni         (rst_n),

        // APB Slave Interface (from bridge)
        .psel_i         (apb_psel),
        .penable_i      (apb_penable),
        .pwrite_i       (apb_pwrite),
        .paddr_i        (apb_paddr - 32'h0000_2000),
        .pwdata_i       (apb_pwdata),
        .pstrb_i        (4'hF),             // Full word strobes (bridge doesn't generate pstrb)
        .prdata_o       (apb_prdata),
        .pready_o       (apb_pready),
        .pslverr_o      (apb_pslverr),

        // UART I/O
        .uart_sin_i     (uart_rx),
        .uart_sout_o    (uart_tx),
        .uart_rtsn_o    (/* unused */),
        .uart_ctsn_i    (1'b0),             // CTS active (tied low = clear-to-send)
        .uart_dtrn_o    (/* unused */),
        .uart_dsrn_i    (1'b0),             // DSR active
        .uart_dcdn_i    (1'b0),             // DCD active
        .uart_rin_i     (1'b1),             // RI inactive
        .uart_irq_o     (uart_irq),

        // SPI I/O
        .spi_clk_o      (spi_sclk),
        .spi_csn0_o     (spi_csn),
        .spi_csn1_o     (/* unused */),
        .spi_csn2_o     (/* unused */),
        .spi_csn3_o     (/* unused */),
        .spi_mode_o     (/* unused */),
        .spi_sdo0_o     (spi_mosi),
        .spi_sdo1_o     (/* unused */),
        .spi_sdo2_o     (/* unused */),
        .spi_sdo3_o     (/* unused */),
        .spi_sdi0_i     (spi_miso),
        .spi_sdi1_i     (1'b0),
        .spi_sdi2_i     (1'b0),
        .spi_sdi3_i     (1'b0),
        .spi_events_o   (/* unused */),

        // GPIO I/O
        .gpio_in_i      (gpio_in),
        .gpio_out_o     (gpio_out),
        .gpio_tx_en_o   (gpio_oe),
        .gpio_in_sync_o (/* unused */),
        .gpio_irq_o     (gpio_irq),
        .gpio_pin_irqs_o(/* unused */),

        // Timer IRQ
        .timer_irq_o    (timer_irq),

        // Watchdog
        .wdt_irq_o      (wdt_irq),
        .wdt_reset_o    (wdt_reset_o),

        // PLIC
        .plic_irq_sources_i (plic_irq_sources),
        .plic_le_i           ({PLIC_N_SRC{1'b1}}),  // Level-sensitive (all high)
        .plic_eip_targets_o  (plic_eip),

        // CLINT
        .clint_intr_src_i  (clint_intr_src),
        .clint_irq_valid_o (/* unused for now */),
        .clint_irq_ready_i (1'b1),
        .clint_irq_id_o    (/* unused */),
        .clint_irq_level_o (/* unused */),
        .clint_irq_shv_o   (/* unused */),
        .clint_irq_priv_o  (/* unused */)
    );

endmodule
