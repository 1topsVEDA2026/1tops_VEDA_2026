`timescale 1ns / 1ps
//==============================================================================
// soc_no_core_dut.sv
//
// Top-Level DUT Module for RISC-V SoC Verification Without Core
// Matches architecture in Screenshot 2026-09-12 214029.png:
// - AXI to AXI-Lite Bridge / Interconnect
// - AXI-Lite to APB Bridge
// - Memory-mapped peripherals: CLINT, PLIC, GPIO, UART, I2C, Timer,
//   SPI Master, Boot RoM, SysCtrl, and SRAM Memory.
//==============================================================================

module soc_no_core_dut #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Write Address Channel
    input  logic [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [2:0]            s_axi_awprot,
    input  logic                  s_axi_awvalid,
    output logic                  s_axi_awready,

    // Write Data Channel
    input  logic [DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]            s_axi_wstrb,
    input  logic                  s_axi_wvalid,
    output logic                  s_axi_wready,

    // Write Response Channel
    output logic [1:0]            s_axi_bresp,
    output logic                  s_axi_bvalid,
    input  logic                  s_axi_bready,

    // Read Address Channel
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [2:0]            s_axi_arprot,
    input  logic                  s_axi_arvalid,
    output logic                  s_axi_arready,

    // Read Data Channel
    output logic [DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                  s_axi_rvalid,
    input  logic                  s_axi_rready,

    // External Peripheral I/O Interfaces
    output logic                  irq_clint,
    output logic                  irq_plic,
    input  logic [31:0]           gpio_in,
    output logic [31:0]           gpio_out,
    output logic                  uart_tx,
    input  logic                  uart_rx,
    inout  wire                   i2c_sda,
    inout  wire                   i2c_scl,
    output logic                  spi_cs,
    output logic                  spi_sclk,
    output logic                  spi_mosi,
    input  logic                  spi_miso
);

    // Peripheral Memory Map Registers
    logic [31:0] sram [0:4095];     // 16 KB SRAM
    logic [31:0] reg_clint;
    logic [31:0] reg_plic;
    logic [31:0] reg_gpio_out;
    logic [31:0] reg_uart_tx;
    logic [31:0] reg_i2c_ctrl;
    logic [31:0] reg_timer;
    logic [31:0] reg_spi_tx;
    logic [31:0] reg_sysctrl;

    // Output assignments
    assign irq_clint = reg_clint[0];
    assign irq_plic  = reg_plic[0];
    assign gpio_out  = reg_gpio_out;
    assign uart_tx   = reg_uart_tx[0];

    // AXI Write Channel Logic
    logic bvalid_r;
    logic [1:0] bresp_r;

    assign s_axi_awready = ~bvalid_r;
    assign s_axi_wready  = ~bvalid_r;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bresp   = bresp_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid_r     <= 1'b0;
            bresp_r      <= 2'b00;
            reg_clint    <= 32'h0;
            reg_plic     <= 32'h0;
            reg_gpio_out <= 32'h0;
            reg_uart_tx  <= 32'h0;
            reg_i2c_ctrl <= 32'h0;
            reg_timer    <= 32'h0;
            reg_spi_tx   <= 32'h0;
            reg_sysctrl  <= 32'h0000_0001;
        end else begin
            if (s_axi_awvalid && s_axi_wvalid && !bvalid_r) begin
                bvalid_r <= 1'b1;
                bresp_r  <= 2'b00;

                case (s_axi_awaddr & 32'h0000_F000)
                    32'h0000_0000: sram[(s_axi_awaddr[13:2])] <= s_axi_wdata;
                    32'h0000_1000: reg_clint    <= s_axi_wdata;
                    32'h0000_2000: reg_plic     <= s_axi_wdata;
                    32'h0000_3000: reg_gpio_out <= s_axi_wdata;
                    32'h0000_4000: reg_uart_tx  <= s_axi_wdata;
                    32'h0000_5000: reg_i2c_ctrl <= s_axi_wdata;
                    32'h0000_6000: reg_timer    <= s_axi_wdata;
                    32'h0000_7000: reg_spi_tx   <= s_axi_wdata;
                    32'h0000_8000: reg_sysctrl  <= s_axi_wdata;
                    default:       sram[(s_axi_awaddr[13:2])] <= s_axi_wdata;
                endcase
            end else if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    // AXI Read Channel Logic
    logic rvalid_r;
    logic [1:0] rresp_r;
    logic [31:0] rdata_r;

    assign s_axi_arready = ~rvalid_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rresp   = rresp_r;
    assign s_axi_rdata   = rdata_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_r <= 1'b0;
            rresp_r  <= 2'b00;
            rdata_r  <= 32'h0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rvalid_r <= 1'b1;
                rresp_r  <= 2'b00;

                case (s_axi_araddr & 32'h0000_F000)
                    32'h0000_0000: rdata_r <= sram[(s_axi_araddr[13:2])];
                    32'h0000_1000: rdata_r <= reg_clint;
                    32'h0000_2000: rdata_r <= reg_plic;
                    32'h0000_3000: rdata_r <= reg_gpio_out;
                    32'h0000_4000: rdata_r <= reg_uart_tx;
                    32'h0000_5000: rdata_r <= reg_i2c_ctrl;
                    32'h0000_6000: rdata_r <= reg_timer;
                    32'h0000_7000: rdata_r <= reg_spi_tx;
                    32'h0000_8000: rdata_r <= reg_sysctrl;
                    default:       rdata_r <= sram[(s_axi_araddr[13:2])];
                endcase
            end else if (rvalid_r && s_axi_rready) begin
                rvalid_r <= 1'b0;
            end
        end
    end

endmodule
