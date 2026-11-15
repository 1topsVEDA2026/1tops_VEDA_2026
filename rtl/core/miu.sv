`timescale 1ns / 1ps
// ============================================================================
// miu.sv — Memory Interface Unit (MIU) with AXI4 Bus Master
//
// Core Component of 3-Stage RV32IM Processor (MW Stage)
//
// 
//   - Byte enables generation (dmem_wstrb) for byte, halfword, and word stores
//   - Store data lane alignment and replication across 32-bit bus
//   - Load data extraction and sign/zero extension (LB, LBU, LH, LHU, LW)
//   - Strictly one outstanding transaction enforced via FSM (DM_IDLE, DM_RD, DM_WR)
//   - Pipeline stall generation (dmem_stall) during in-flight memory transactions
// ============================================================================

module miu
    import rv32_pkg::*;
(
    input  logic                   clk,
    input  logic                   rst_n,

    // Core Pipeline Interface (MW Stage)
    input  logic                   rd_en_MW,          // Load enable
    input  logic                   wr_en_MW,          // Store enable
    input  mem_acc_mode_t          mem_acc_mode_MW,   // Byte / Half / Word / Signed / Unsigned
    input  logic [31:0]            addr_MW,           // Target memory address (opr_res_MW)
    input  logic [31:0]            wdata_MW,          // Store write data (rsdata2_MW)
    output logic [31:0]            rdata_ext,         // Formatted load data (sign/zero extended)
    output logic                   dmem_stall,        // Freeze pipeline during memory stall

    // AXI4 DMEM Master Interface — AW Channel (Store Address)
    output logic [31:0]            dmem_awaddr,
    output logic                   dmem_awvalid,
    input  logic                   dmem_awready,
    output logic [ 7:0]            dmem_awlen,
    output logic [ 2:0]            dmem_awsize,
    output logic [ 1:0]            dmem_awburst,
    output logic [ 3:0]            dmem_awcache,
    output logic [ 2:0]            dmem_awprot,
    output logic                   dmem_awlock,

    // AXI4 DMEM Master Interface — W Channel (Store Data)
    output logic [31:0]            dmem_wdata,
    output logic [ 3:0]            dmem_wstrb,
    output logic                   dmem_wvalid,
    input  logic                   dmem_wready,
    output logic                   dmem_wlast,

    // AXI4 DMEM Master Interface — B Channel (Store Response)
    input  logic                   dmem_bvalid,
    output logic                   dmem_bready,
    input  logic [ 1:0]            dmem_bresp,

    // AXI4 DMEM Master Interface — AR Channel (Load Address)
    output logic [31:0]            dmem_araddr,
    output logic                   dmem_arvalid,
    input  logic                   dmem_arready,
    output logic [ 7:0]            dmem_arlen,
    output logic [ 2:0]            dmem_arsize,
    output logic [ 1:0]            dmem_arburst,
    output logic [ 3:0]            dmem_arcache,
    output logic [ 2:0]            dmem_arprot,
    output logic                   dmem_arlock,

    // AXI4 DMEM Master Interface — R Channel (Load Data)
    input  logic [31:0]            dmem_rdata,
    input  logic                   dmem_rvalid,
    output logic                   dmem_rready,
    input  logic [ 1:0]            dmem_rresp,
    input  logic                   dmem_rlast
);

    // ========================================================================
    // 1. One Outstanding Transaction FSM
    // ========================================================================
    typedef enum logic [1:0] {
        DM_IDLE = 2'b00,
        DM_RD   = 2'b01,
        DM_WR   = 2'b10
    } dm_state_t;

    dm_state_t dm_state;
    logic      dm_ar_done, dm_aw_done, dm_w_done;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dm_state   <= DM_IDLE;
            dm_ar_done <= 1'b0;
            dm_aw_done <= 1'b0;
            dm_w_done  <= 1'b0;
        end else begin
            case (dm_state)
                DM_IDLE: begin
                    if (rd_en_MW && !dmem_rvalid) begin
                        dm_state   <= DM_RD;
                        dm_ar_done <= dmem_arvalid && dmem_arready;
                    end else if (wr_en_MW && !dmem_bvalid) begin
                        dm_state   <= DM_WR;
                        dm_aw_done <= dmem_awvalid && dmem_awready;
                        dm_w_done  <= dmem_wvalid  && dmem_wready;
                    end
                    // else: zero-latency slave responded in current cycle -> stay IDLE
                end

                DM_RD: begin
                    if (dmem_arvalid && dmem_arready) dm_ar_done <= 1'b1;
                    if (dmem_rvalid) begin
                        dm_state   <= DM_IDLE;
                        dm_ar_done <= 1'b0;
                    end
                end

                DM_WR: begin
                    if (dmem_awvalid && dmem_awready) dm_aw_done <= 1'b1;
                    if (dmem_wvalid  && dmem_wready)  dm_w_done  <= 1'b1;
                    if (dmem_bvalid) begin
                        dm_state   <= DM_IDLE;
                        dm_aw_done <= 1'b0;
                        dm_w_done  <= 1'b0;
                    end
                end

                default: dm_state <= DM_IDLE;
            endcase
        end
    end

    // ========================================================================
    // 2. Pipeline Stall Generator
    // ========================================================================
    wire dmem_rd_comb_ok = (dm_state == DM_IDLE) && rd_en_MW && dmem_rvalid;
    wire dmem_wr_comb_ok = (dm_state == DM_IDLE) && wr_en_MW && dmem_bvalid;

    assign dmem_stall =
        (dm_state == DM_RD  && !dmem_rvalid)  ||
        (dm_state == DM_WR  && !dmem_bvalid)  ||
        ((dm_state == DM_IDLE) && rd_en_MW && !dmem_rd_comb_ok) ||
        ((dm_state == DM_IDLE) && wr_en_MW && !dmem_wr_comb_ok);

    // ========================================================================
    // 3. AXI4 Bus Transfer Size
    // ========================================================================
    logic [2:0] dmem_axsize;
    always_comb begin
        case (mem_acc_mode_MW)
            MEM_BYTE, MEM_BYTE_U: dmem_axsize = 3'b000;  // 1 byte
            MEM_HALF, MEM_HALF_U: dmem_axsize = 3'b001;  // 2 bytes
            default:              dmem_axsize = 3'b010;  // 4 bytes (word)
        endcase
    end

    // ========================================================================
    // 4. AXI4 Read Address Channel (AR)
    // ========================================================================
    assign dmem_arvalid = ((dm_state == DM_IDLE) && rd_en_MW) ||
                          ((dm_state == DM_RD)   && !dm_ar_done);
    assign dmem_araddr  = addr_MW;
    assign dmem_arlen   = 8'd0;
    assign dmem_arsize  = dmem_axsize;
    assign dmem_arburst = 2'b01;
    assign dmem_arcache = 4'b0000;
    assign dmem_arprot  = 3'b000;
    assign dmem_arlock  = 1'b0;
    assign dmem_rready  = 1'b1;

    // ========================================================================
    // 5. AXI4 Write Channels (AW & W)
    // ========================================================================
    assign dmem_awvalid = ((dm_state == DM_IDLE) && wr_en_MW) ||
                          ((dm_state == DM_WR)   && !dm_aw_done);
    assign dmem_awaddr  = addr_MW;
    assign dmem_awlen   = 8'd0;
    assign dmem_awsize  = dmem_axsize;
    assign dmem_awburst = 2'b01;
    assign dmem_awcache = 4'b0000;
    assign dmem_awprot  = 3'b000;
    assign dmem_awlock  = 1'b0;

    assign dmem_wvalid  = ((dm_state == DM_IDLE) && wr_en_MW) ||
                          ((dm_state == DM_WR)   && !dm_w_done);
    assign dmem_wlast   = 1'b1;
    assign dmem_bready  = 1'b1;

    // ========================================================================
    // 6. Store Data Alignment & Byte Enable Generation
    // ========================================================================
    always_comb begin
        case (mem_acc_mode_MW)
            MEM_BYTE, MEM_BYTE_U: begin
                dmem_wdata = {4{wdata_MW[7:0]}};
                dmem_wstrb = 4'b0001 << addr_MW[1:0];
            end
            MEM_HALF, MEM_HALF_U: begin
                dmem_wdata = {2{wdata_MW[15:0]}};
                dmem_wstrb = addr_MW[1] ? 4'b1100 : 4'b0011;
            end
            MEM_WORD: begin
                dmem_wdata = wdata_MW;
                dmem_wstrb = 4'b1111;
            end
            default: begin
                dmem_wdata = wdata_MW;
                dmem_wstrb = 4'b0000;
            end
        endcase
    end

    // ========================================================================
    // 7. Load Data Lane Extraction & Sign / Zero Extension
    // ========================================================================
    logic [ 7:0] ld_byte;
    logic [15:0] ld_half;

    always_comb begin
        case (addr_MW[1:0])
            2'b00: ld_byte = dmem_rdata[ 7: 0];
            2'b01: ld_byte = dmem_rdata[15: 8];
            2'b10: ld_byte = dmem_rdata[23:16];
            2'b11: ld_byte = dmem_rdata[31:24];
        endcase
    end

    assign ld_half = addr_MW[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];

    always_comb begin
        case (mem_acc_mode_MW)
            MEM_BYTE:   rdata_ext = {{24{ld_byte[7]}}, ld_byte};
            MEM_BYTE_U: rdata_ext = {24'd0, ld_byte};
            MEM_HALF:   rdata_ext = {{16{ld_half[15]}}, ld_half};
            MEM_HALF_U: rdata_ext = {16'd0, ld_half};
            MEM_WORD:   rdata_ext = dmem_rdata;
            default:    rdata_ext = dmem_rdata;
        endcase
    end

endmodule
