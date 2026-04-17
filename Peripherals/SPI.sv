`timescale 1ns / 1ps

module spi_top (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    output logic        spi_sclk_o,
    output logic        spi_mosi_o,
    input  logic        spi_miso_i,
    output logic        spi_cs_n_o,

    output logic        spi_irq_o
);

    // Registers
    logic [7:0] tx_data_reg, rx_data_reg;
    logic cpol_reg, cpha_reg, cs_en_reg, irq_en_reg;
    logic [7:0] clk_div_reg;
    logic irq_flag, irq_set;
    logic tx_load;

    logic spi_busy, rx_valid, tx_empty;

    // AXI unused bits handling (lint clean)
    (* keep = "true" *) wire unused;
    assign unused = |s_axi_awaddr[31:8] |
                    |s_axi_araddr[31:8] |
                    |s_axi_wdata[31:8]  |
                    |s_axi_wstrb;

    // Clock Divider
    logic [7:0] spi_clk_counter;
    logic spi_clk_tick, spi_clk_int;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            spi_clk_counter <= 0;
            spi_clk_tick    <= 0;
            spi_clk_int     <= 0;
        end else begin
            spi_clk_tick <= 0;
            if (spi_clk_counter == clk_div_reg) begin
                spi_clk_counter <= 0;
                spi_clk_int     <= ~spi_clk_int;
                spi_clk_tick    <= 1;
            end else begin
                spi_clk_counter <= spi_clk_counter + 1;
            end
        end
    end

    // SPI FSM
    typedef enum logic [1:0] {IDLE, TRANSFER, DONE} state_t;
    state_t state;

    logic [7:0] tx_shift_reg, rx_shift_reg;
    logic [2:0] bit_count;
    logic spi_clk_prev;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            spi_sclk_o <= 0;
            spi_mosi_o <= 0;
            spi_cs_n_o <= 1;
            spi_busy <= 0;
            rx_valid <= 0;
            tx_empty <= 1;
            bit_count <= 0;
            irq_set <= 0;
            spi_clk_prev <= 0;
        end else begin
            spi_clk_prev <= spi_clk_int;
            irq_set <= 0;

            case (state)
                IDLE: begin
                    spi_sclk_o <= cpol_reg;
                    spi_cs_n_o <= ~cs_en_reg;
                    spi_busy   <= 0;
                    tx_empty   <= 1;

                    if (tx_load) begin
                        tx_shift_reg <= tx_data_reg;
                        bit_count <= 0;
                        spi_cs_n_o <= 0;
                        spi_busy <= 1;
                        tx_empty <= 0;
                        rx_valid <= 0;
                        state <= TRANSFER;
                    end
                end

                TRANSFER: begin
                    if (spi_clk_tick && !spi_clk_prev && spi_clk_int) begin
                        if (!cpha_reg)
                            rx_shift_reg <= {rx_shift_reg[6:0], spi_miso_i};
                        else begin
                            spi_mosi_o <= tx_shift_reg[7];
                            tx_shift_reg <= {tx_shift_reg[6:0],1'b0};
                        end
                        spi_sclk_o <= ~cpol_reg;
                    end

                    if (spi_clk_tick && spi_clk_prev && !spi_clk_int) begin
                        if (!cpha_reg) begin
                            spi_mosi_o <= tx_shift_reg[7];
                            tx_shift_reg <= {tx_shift_reg[6:0],1'b0};
                        end else
                            rx_shift_reg <= {rx_shift_reg[6:0], spi_miso_i};

                        spi_sclk_o <= cpol_reg;
                        bit_count <= bit_count + 1;

                        if (bit_count == 3'd7)
                            state <= DONE;
                    end
                end

                DONE: begin
                    rx_data_reg <= rx_shift_reg;
                    rx_valid <= 1;
                    spi_busy <= 0;
                    tx_empty <= 1;
                    spi_cs_n_o <= 1;
                    spi_sclk_o <= cpol_reg;

                    if (irq_en_reg)
                        irq_set <= 1;

                    state <= IDLE;
                end
            endcase
        end
    end

    // IRQ REGISTER
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            irq_flag <= 0;
        else begin
            if (irq_set)
                irq_flag <= 1;
            else if (s_axi_awvalid && s_axi_wvalid &&
                     s_axi_awaddr[7:0] == 8'h14 &&
                     s_axi_wdata[0])
                irq_flag <= 0;
        end
    end

    assign spi_irq_o = irq_flag;

    // AXI WRITE
    typedef enum logic [1:0] {WR_IDLE, WR_RESP} wr_t;
    wr_t wr_state;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_state <= WR_IDLE;
            s_axi_awready <= 0;
            s_axi_wready  <= 0;
            s_axi_bvalid  <= 0;
            s_axi_bresp   <= 2'b00;
            tx_load <= 0;
        end else begin
            tx_load <= 0;

            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready <= 1;
                    s_axi_wready  <= 1;

                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 0;
                        s_axi_wready  <= 0;
                        wr_state <= WR_RESP;

                        case (s_axi_awaddr[7:0])
                            8'h00: begin
                                tx_data_reg <= s_axi_wdata[7:0];
                                tx_load <= 1;
                            end

                            8'h0C: begin
                                cpol_reg <= s_axi_wdata[0];
                                cpha_reg <= s_axi_wdata[1];
                                clk_div_reg <= s_axi_wdata[9:2];
                                cs_en_reg <= s_axi_wdata[10];
                            end

                            8'h10:
                                irq_en_reg <= s_axi_wdata[0];
                        endcase
                    end
                end

                WR_RESP: begin
                    s_axi_bvalid <= 1;
                    s_axi_bresp  <= 2'b00;

                    if (s_axi_bready) begin
                        s_axi_bvalid <= 0;
                        wr_state <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // AXI READ
    typedef enum logic [1:0] {RD_IDLE, RD_DATA} rd_t;
    rd_t rd_state;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_state <= RD_IDLE;
            s_axi_arready <= 0;
            s_axi_rvalid <= 0;
            s_axi_rresp <= 2'b00;
            s_axi_rdata <= 0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready <= 1;
                    s_axi_rresp   <= 2'b00;

                    if (s_axi_arvalid) begin
                        s_axi_arready <= 0;
                        rd_state <= RD_DATA;

                        case (s_axi_araddr[7:0])
                            8'h04: s_axi_rdata <= {24'h0, rx_data_reg};
                            8'h08: s_axi_rdata <= {29'h0, tx_empty, rx_valid, spi_busy};
                            8'h0C: s_axi_rdata <= {21'h0, cs_en_reg, clk_div_reg, cpha_reg, cpol_reg};
                            8'h10: s_axi_rdata <= {31'h0, irq_en_reg};
                            default: s_axi_rdata <= 0;
                        endcase
                    end
                end

                RD_DATA: begin
                    s_axi_rvalid <= 1;
                    s_axi_rresp  <= 2'b00;

                    if (s_axi_rready) begin
                        s_axi_rvalid <= 0;
                        rd_state <= RD_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
