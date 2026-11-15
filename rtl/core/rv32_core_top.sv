`timescale 1ns / 1ps

module rv32_core_top
    import rv32_pkg::*;
#(
    parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        rst_n,

    // ====================================================================
    // Instruction Memory — AXI4 Master (read-only: AR + R channels)
    // ====================================================================
    // AR channel
    output logic [31:0] imem_araddr,
    output logic        imem_arvalid,
    input  logic        imem_arready,
    output logic [ 7:0] imem_arlen,    // = 8'd0 (single beat)
    output logic [ 2:0] imem_arsize,   // = 3'b010 (4-byte word)
    output logic [ 1:0] imem_arburst,  // = 2'b01  (INCR)
    output logic [ 3:0] imem_arcache,  // = 4'b0010 (normal non-cacheable buf)
    output logic [ 2:0] imem_arprot,   // = 3'b100  (instruction, non-secure)
    output logic        imem_arlock,   // = 1'b0
    // R channel
    input  logic [31:0] imem_rdata,
    input  logic        imem_rvalid,
    output logic        imem_rready,   // = 1'b1 (core always ready)
    input  logic [ 1:0] imem_rresp,
    input  logic        imem_rlast,

    // ====================================================================
    // Data Memory — AXI4 Master (AW + W + B + AR + R channels)
    // ====================================================================
    // AW channel
    output logic [31:0] dmem_awaddr,
    output logic        dmem_awvalid,
    input  logic        dmem_awready,
    output logic [ 7:0] dmem_awlen,    // = 8'd0
    output logic [ 2:0] dmem_awsize,   // byte-width of access
    output logic [ 1:0] dmem_awburst,  // = 2'b01
    output logic [ 3:0] dmem_awcache,  // = 4'b0000
    output logic [ 2:0] dmem_awprot,   // = 3'b000
    output logic        dmem_awlock,   // = 1'b0
    // W channel
    output logic [31:0] dmem_wdata,
    output logic [ 3:0] dmem_wstrb,    // byte enables (replaces dmem_be)
    output logic        dmem_wvalid,
    output logic        dmem_wlast,    // = 1'b1
    input  logic        dmem_wready,
    // B channel
    input  logic        dmem_bvalid,
    input  logic [ 1:0] dmem_bresp,
    output logic        dmem_bready,   // = 1'b1
    // AR channel
    output logic [31:0] dmem_araddr,
    output logic        dmem_arvalid,
    input  logic        dmem_arready,
    output logic [ 7:0] dmem_arlen,    // = 8'd0
    output logic [ 2:0] dmem_arsize,
    output logic [ 1:0] dmem_arburst,  // = 2'b01
    output logic [ 3:0] dmem_arcache,  // = 4'b0000
    output logic [ 2:0] dmem_arprot,   // = 3'b000
    output logic        dmem_arlock,   // = 1'b0
    // R channel
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_rvalid,
    output logic        dmem_rready,   // = 1'b1
    input  logic [ 1:0] dmem_rresp,
    input  logic        dmem_rlast,

    // ====================================================================
    // Interrupt Inputs (active-high)
    // ====================================================================
    input  logic        irq_external,
    input  logic        irq_timer,
    input  logic        irq_software
);

    //  INTERNAL SIGNAL DECLARATIONS
    // ---- MW stage memory control ----
    logic rd_en_MW, wr_en_MW;

    // ---- Hazard Unit outputs ----
    logic forward_a, forward_b;
    logic stall_IF;
    logic stall_MW;
    logic flush_DE;
    logic flush_MW;

    // ====================================================================
    // AXI4 Stall Signals (replace OBI wires)
    // ====================================================================
    // IMEM: stall while arvalid is high but no rvalid yet
    wire imem_stall = imem_arvalid & !imem_rvalid;

    // DMEM: managed by the DMEM FSM below
    wire dmem_stall;

    // ---- Valid signal through pipeline ----
    logic valid_DE;

    // ---- Pipeline handshake ----
    wire ready_IF = !stall_IF;
    wire ready_DE = !stall_IF;
    wire ready_MW = !stall_MW;

    // ---- CSR outputs ----
    logic [31:0] epc_pc, mtvec_out;

    // ---- MW stage writeback ----
    logic [31:0] wdata;
    logic [ 4:0] rd_addr_MW;
    logic        rf_en_MW;

    //  STAGE 1 — FETCH (IF)

    logic [31:0] pc_out_IF;
    logic [31:0] pc_next_IF;
    logic [31:0] nxt_pc;
    logic [31:0] instr_IF;

    logic        br_take_DE;
    logic        is_mret_DE;
    logic        trap_illegal;
    logic [31:0] opr_res_DE;

    wire epc_taken_IF = trap_illegal & ready_IF;

    // PC Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)           pc_out_IF <= RESET_PC;
        else if (ready_IF)    pc_out_IF <= nxt_pc;
    end

    assign pc_next_IF = pc_out_IF + 32'd4;

    // PC Mux
    always_comb begin
        if (epc_taken_IF)
            nxt_pc = mtvec_out;
        else if (is_mret_DE & valid_DE & ready_IF)
            nxt_pc = epc_pc;
        else if (br_take_DE & valid_DE & ready_IF)
            nxt_pc = {opr_res_DE[31:1], 1'b0};
        else
            nxt_pc = pc_next_IF;
    end

    // ====================================================================
    // IMEM AXI4 Master — AR + R channels
    // arvalid = 1 always (continuous fetch, like OBI req=1)
    // imem_stall deasserts as soon as rvalid arrives
    // ====================================================================
    assign imem_araddr  = pc_out_IF;
    assign imem_arvalid = 1'b1;
    assign imem_arlen   = 8'd0;
    assign imem_arsize  = 3'b010;   // 4-byte word
    assign imem_arburst = 2'b01;    // INCR
    assign imem_arcache = 4'b0010;  // normal non-cacheable bufferable
    assign imem_arprot  = 3'b100;   // instruction access
    assign imem_arlock  = 1'b0;
    assign imem_rready  = 1'b1;     // always ready to accept instruction

    assign instr_IF = imem_rdata;


    //  PIPELINE REGISTER — IF → DE

    logic [31:0] pc_out_DE, pc_next_DE, inst_DE;

    pipe_if_de u_pipe_if_de (
        .clk        (clk),
        .rst_n      (rst_n),
        .ready_DE   (ready_DE),
        .flush_DE   (flush_DE),
        .pc_out_IF  (pc_out_IF),
        .pc_next_IF (pc_next_IF),
        .instr_IF   (instr_IF),
        .valid_IF   (imem_rvalid),
        .pc_out_DE  (pc_out_DE),
        .pc_next_DE (pc_next_DE),
        .inst_DE    (inst_DE),
        .valid_DE   (valid_DE)
    );


    //  STAGE 2 — DECODE-EXECUTE (DE)

    logic [ 4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [11:0]  csr_addr;
    imm_type_t    imm_type;
    exec_class_t  exec_class;
    alu_func_t    alu_func;
    mdu_func_t    mdu_func;
    csr_cmd_t     csr_cmd;
    br_type_t     br_type;
    mem_acc_t     mem_acc_mode_DE;

    decoder u_decoder (
        .inst           (inst_DE),
        .rs1_addr       (rs1_addr),
        .rs2_addr       (rs2_addr),
        .rd_addr        (rd_addr),
        .csr_addr       (csr_addr),
        .imm_type       (imm_type),
        .exec_class     (exec_class),
        .alu_func       (alu_func),
        .mdu_func       (mdu_func),
        .csr_cmd        (csr_cmd),
        .br_type        (br_type),
        .mem_acc_mode   (mem_acc_mode_DE)
    );

    logic        is_taken;
    logic [31:0] rsdata1_DC, rsdata2_DC;

    branch_cmp u_branch_cmp (
        .rs1_data  (rsdata1_DC),
        .rs2_data  (rsdata2_DC),
        .br_type   (br_type),
        .is_branch (exec_class == EXEC_BRANCH),
        .is_taken  (is_taken)
    );

    alu_func_t aluop;
    mdu_func_t mdu_func_ctrl;
    logic      rf_en_DE, sel_a, sel_b;
    logic      rd_en_DE, wr_en_DE;
    wb_sel_t   wb_sel_DE;
    logic      csr_rd_DE, csr_wr_DE, csr_imm_sel;

    controller u_controller (
        .exec_class   (exec_class),
        .alu_func_in  (alu_func),
        .mdu_func_in  (mdu_func),
        .csr_cmd_in   (csr_cmd),
        .br_taken     (is_taken),
        .rs1_addr     (rs1_addr),
        .aluop        (aluop),
        .mdu_func_out (mdu_func_ctrl),
        .rf_en        (rf_en_DE),
        .sel_a        (sel_a),
        .sel_b        (sel_b),
        .rd_en        (rd_en_DE),
        .wr_en        (wr_en_DE),
        .wb_sel       (wb_sel_DE),
        .br_take      (br_take_DE),
        .csr_rd       (csr_rd_DE),
        .csr_wr       (csr_wr_DE),
        .csr_imm_sel  (csr_imm_sel),
        .is_mret      (is_mret_DE),
        .trap_illegal (trap_illegal)
    );

    logic [31:0] rsdata1, rsdata2;

    register_file u_regfile (
        .clk     (clk),
        .rst_n   (rst_n),
        .rs1_addr(rs1_addr),
        .rsdata1 (rsdata1),
        .rs2_addr(rs2_addr),
        .rsdata2 (rsdata2),
        .rd_addr (rd_addr_MW),
        .wdata   (wdata),
        .rf_en   (rf_en_MW)
    );

    logic [31:0] imm_ext_DE;

    imm_gen u_imm_gen (
        .inst    (inst_DE),
        .imm_type(imm_type),
        .imm_ext (imm_ext_DE)
    );

    assign rsdata1_DC = forward_a ? wdata : rsdata1;
    assign rsdata2_DC = forward_b ? wdata : rsdata2;

    logic [31:0] opr_a, opr_b;
    assign opr_a = sel_a ? rsdata1_DC : pc_out_DE;
    assign opr_b = sel_b ? imm_ext_DE : rsdata2_DC;

    logic [31:0] alu_res_DE;
    alu u_alu (
        .opr_a   (opr_a),
        .opr_b   (opr_b),
        .alu_func(aluop),
        .opr_res (alu_res_DE)
    );

    logic [31:0] mdu_res_DE;
    logic        mdu_stall, mdu_done;
    wire         state_mdu_idle = !mdu_stall && !mdu_done;

    // Named wire: also used to assert immediate stall via hazard unit
    wire mdu_start = valid_DE && (exec_class == EXEC_MDU) && state_mdu_idle;

    mdu u_mdu (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (mdu_start),
        .mdu_func (mdu_func_ctrl),
        .rs1      (rsdata1_DC),
        .rs2      (rsdata2_DC),
        .result   (mdu_res_DE),
        .done     (mdu_done),
        .stall    (mdu_stall)
    );

    assign opr_res_DE = (exec_class == EXEC_MDU) ? mdu_res_DE : alu_res_DE;

    logic [31:0] csr_rdata_DE, csr_wdata_DE, csr_src_data;

    assign csr_src_data = csr_imm_sel ? {27'd0, rs1_addr} : rsdata1_DC;

    always_comb begin
        case (csr_cmd)
            CSR_RW, CSR_RWI: csr_wdata_DE = csr_src_data;
            CSR_RS, CSR_RSI: csr_wdata_DE = csr_rdata_DE | csr_src_data;
            CSR_RC, CSR_RCI: csr_wdata_DE = csr_rdata_DE & ~csr_src_data;
            default:         csr_wdata_DE = 32'd0;
        endcase
    end

    wire csr_we_gated = csr_wr_DE & ready_IF;

    csr_regfile u_csr (
        .clk          (clk),
        .rst_n        (rst_n),
        .csr_raddr    (csr_addr),
        .csr_rdata    (csr_rdata_DE),
        .csr_waddr    (csr_addr),
        .csr_wdata    (csr_wdata_DE),
        .csr_we       (csr_we_gated),
        .epc_taken_IF (epc_taken_IF),
        .trap_pc      (pc_out_DE),
        .trap_cause   (32'd2),
        .is_mret      (is_mret_DE & valid_DE & ready_IF),
        .epc_pc       (epc_pc),
        .mtvec_out    (mtvec_out),
        .irq_external (irq_external),
        .irq_timer    (irq_timer),
        .irq_software (irq_software)
    );


    //  PIPELINE REGISTER — DE → MW

    logic [31:0] opr_res_MW;
    logic [31:0] rsdata2_MW;
    logic [31:0] pc_next_MW;
    logic [31:0] pc_out_MW;
    logic [31:0] csr_rdata_MW;
    wb_sel_t     wb_sel_MW;
    mem_acc_t    mem_acc_mode_MW;

    pipe_de_mw u_pipe_de_mw (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_MW        (flush_MW),
        .ready_MW        (ready_MW),
        .opr_res_in      (opr_res_DE),
        .rsdata2_in      (rsdata2_DC),
        .rd_addr_in      (rd_addr),
        .pc_next_in      (pc_next_DE),
        .pc_out_in       (pc_out_DE),
        .csr_rdata_in    (csr_rdata_DE),
        .rf_en_in        (rf_en_DE),
        .wb_sel_in       (wb_sel_DE),
        .rd_en_in        (rd_en_DE),
        .wr_en_in        (wr_en_DE),
        .mem_acc_mode_in (mem_acc_mode_DE),
        .opr_res_MW      (opr_res_MW),
        .rsdata2_MW      (rsdata2_MW),
        .rd_addr_MW      (rd_addr_MW),
        .pc_next_MW      (pc_next_MW),
        .pc_out_MW       (pc_out_MW),
        .csr_rdata_MW    (csr_rdata_MW),
        .rf_en_MW        (rf_en_MW),
        .wb_sel_MW       (wb_sel_MW),
        .rd_en_MW        (rd_en_MW),
        .wr_en_MW        (wr_en_MW),
        .mem_acc_mode_MW (mem_acc_mode_MW)
    );


    //  STAGE 3 — MEMORY-WRITEBACK (MW)

    // ====================================================================
    // DMEM AXI4 Master FSM
    //
    // States:
    //   DM_IDLE  — no transaction in flight
    //   DM_RD    — load:  AR channel driven; waiting for rvalid
    //   DM_WR    — store: AW+W channels driven; waiting for bvalid
    //
    // First-cycle combinational:  arvalid/awvalid/wvalid is asserted
    // combinationally in DM_IDLE+rd/wr_en so the slave sees the request
    // in the same cycle the pipeline decodes it — matching OBI latency for
    // zero-latency slave models.
    // ====================================================================
    typedef enum logic [1:0] {
        DM_IDLE = 2'b00,
        DM_RD   = 2'b01,
        DM_WR   = 2'b10
    } dm_state_t;

    dm_state_t dm_state;
    logic      dm_ar_done, dm_aw_done, dm_w_done;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dm_state  <= DM_IDLE;
            dm_ar_done <= 1'b0;
            dm_aw_done <= 1'b0;
            dm_w_done  <= 1'b0;
        end else begin
            case (dm_state)
                DM_IDLE: begin
                    if (rd_en_MW && !dmem_rvalid) begin
                        dm_state   <= DM_RD;
                        dm_ar_done <= dmem_arvalid && dmem_arready;
                    end
                    else if (wr_en_MW && !dmem_bvalid) begin
                        dm_state   <= DM_WR;
                        dm_aw_done <= dmem_awvalid && dmem_awready;
                        dm_w_done  <= dmem_wvalid  && dmem_wready;
                    end
                    // else: zero-latency slave responded this cycle → stay IDLE
                end
                DM_RD: begin
                    if (dmem_arvalid && dmem_arready) dm_ar_done <= 1'b1;
                    if (dmem_rvalid) begin
                        dm_state  <= DM_IDLE;
                        dm_ar_done <= 1'b0;
                    end
                end
                DM_WR: begin
                    if (dmem_awvalid && dmem_awready) dm_aw_done <= 1'b1;
                    if (dmem_wvalid  && dmem_wready)  dm_w_done  <= 1'b1;
                    if (dmem_bvalid) begin
                        dm_state  <= DM_IDLE;
                        dm_aw_done <= 1'b0;
                        dm_w_done  <= 1'b0;
                    end
                end
                default: dm_state <= DM_IDLE;
            endcase
        end
    end

    // ---- AXI4 DMEM stall ----
    // Stall while: (a) transaction in progress, OR (b) new request that
    // didn't complete combinationally this cycle (slave not zero-latency).
    wire dmem_rd_comb_ok = (dm_state == DM_IDLE) && rd_en_MW && dmem_rvalid;
    wire dmem_wr_comb_ok = (dm_state == DM_IDLE) && wr_en_MW && dmem_bvalid;

    assign dmem_stall =
        (dm_state == DM_RD  && !dmem_rvalid)  ||
        (dm_state == DM_WR  && !dmem_bvalid)  ||
        ((dm_state == DM_IDLE) && rd_en_MW && !dmem_rd_comb_ok) ||
        ((dm_state == DM_IDLE) && wr_en_MW && !dmem_wr_comb_ok);

    // ---- AXI4 size based on access width ----
    logic [2:0] dmem_axsize;
    always_comb begin
        case (mem_acc_mode_MW)
            MEM_BYTE, MEM_BYTE_U: dmem_axsize = 3'b000;  // 1 byte
            MEM_HALF, MEM_HALF_U: dmem_axsize = 3'b001;  // 2 bytes
            default:              dmem_axsize = 3'b010;  // 4 bytes (word)
        endcase
    end

    // ---- AXI4 AR channel (loads) ----
    // First cycle: combinational from DM_IDLE; subsequent: from DM_RD
    assign dmem_arvalid = ((dm_state == DM_IDLE) && rd_en_MW) ||
                          ((dm_state == DM_RD)   && !dm_ar_done);
    assign dmem_araddr  = opr_res_MW;
    assign dmem_arlen   = 8'd0;
    assign dmem_arsize  = dmem_axsize;
    assign dmem_arburst = 2'b01;
    assign dmem_arcache = 4'b0000;
    assign dmem_arprot  = 3'b000;
    assign dmem_arlock  = 1'b0;
    assign dmem_rready  = 1'b1;

    // ---- AXI4 AW+W channels (stores) ----
    assign dmem_awvalid = ((dm_state == DM_IDLE) && wr_en_MW) ||
                          ((dm_state == DM_WR)   && !dm_aw_done);
    assign dmem_awaddr  = opr_res_MW;
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

    // ---- Store data + byte strobes (same logic as before) ----
    always_comb begin
        case (mem_acc_mode_MW)
            MEM_BYTE, MEM_BYTE_U: begin
                dmem_wdata = {4{rsdata2_MW[7:0]}};
                dmem_wstrb = 4'b0001 << opr_res_MW[1:0];
            end
            MEM_HALF, MEM_HALF_U: begin
                dmem_wdata = {2{rsdata2_MW[15:0]}};
                dmem_wstrb = opr_res_MW[1] ? 4'b1100 : 4'b0011;
            end
            MEM_WORD: begin
                dmem_wdata = rsdata2_MW;
                dmem_wstrb = 4'b1111;
            end
            default: begin
                dmem_wdata = rsdata2_MW;
                dmem_wstrb = 4'b0000;
            end
        endcase
    end

    // ---- Load data extraction (same as before, uses dmem_rdata) ----
    logic [31:0] rdata_ext;
    logic [ 7:0] ld_byte;
    logic [15:0] ld_half;

    always_comb begin
        case (opr_res_MW[1:0])
            2'b00: ld_byte = dmem_rdata[ 7: 0];
            2'b01: ld_byte = dmem_rdata[15: 8];
            2'b10: ld_byte = dmem_rdata[23:16];
            2'b11: ld_byte = dmem_rdata[31:24];
        endcase
    end

    assign ld_half = opr_res_MW[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];

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

    // Writeback Mux
    always_comb begin
        case (wb_sel_MW)
            WB_PC4: wdata = pc_next_MW;
            WB_ALU: wdata = opr_res_MW;
            WB_MEM: wdata = rdata_ext;
            WB_CSR: wdata = csr_rdata_MW;
        endcase
    end


    //  HAZARD UNIT

    hazard_unit u_hazard (
        .rs1_addr_DE (rs1_addr),
        .rs2_addr_DE (rs2_addr),
        .rd_addr_MW  (rd_addr_MW),
        .rf_en_MW    (rf_en_MW),
        .rd_en_MW    (rd_en_MW),
        .br_take_DE  (br_take_DE & valid_DE),
        .is_mret_DE  (is_mret_DE & valid_DE),
        .epc_taken_IF(epc_taken_IF),
        .imem_stall  (imem_stall),
        .dmem_stall  (dmem_stall),
        .mdu_stall   (mdu_stall || mdu_start),
        .forward_a   (forward_a),
        .forward_b   (forward_b),
        .stall_IF    (stall_IF),
        .stall_MW    (stall_MW),
        .flush_DE    (flush_DE),
        .flush_MW    (flush_MW)
    );

    //  SVA — AXI4 Protocol & Pipeline Assertions
    // synthesis translate_off

    // AXI4: ARVALID must not deassert without ARREADY handshake
    property p_imem_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (imem_arvalid && !imem_arready) |=> imem_arvalid;
    endproperty
    assert property (p_imem_arvalid_stable)
        else $error("SVA: imem_arvalid dropped before arready handshake");

    // AXI4: DMEM ARVALID must not deassert without ARREADY
    property p_dmem_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (dmem_arvalid && !dmem_arready) |=> dmem_arvalid;
    endproperty
    assert property (p_dmem_arvalid_stable)
        else $error("SVA: dmem_arvalid dropped before arready handshake");

    // AXI4: DMEM AWVALID must not deassert without AWREADY
    property p_dmem_awvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (dmem_awvalid && !dmem_awready) |=> dmem_awvalid;
    endproperty
    assert property (p_dmem_awvalid_stable)
        else $error("SVA: dmem_awvalid dropped before awready handshake");

    // AXI4: DMEM WVALID must not deassert without WREADY
    property p_dmem_wvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (dmem_wvalid && !dmem_wready) |=> dmem_wvalid;
    endproperty
    assert property (p_dmem_wvalid_stable)
        else $error("SVA: dmem_wvalid dropped before wready handshake");

    // AXI4: No error responses during normal operation
    property p_no_rresp_err;
        @(posedge clk) disable iff (!rst_n)
        imem_rvalid |-> (imem_rresp == 2'b00);
    endproperty
    assert property (p_no_rresp_err)
        else $error("SVA: imem RRESP error response received");

    property p_no_bresp_err;
        @(posedge clk) disable iff (!rst_n)
        dmem_bvalid |-> (dmem_bresp == 2'b00);
    endproperty
    assert property (p_no_bresp_err)
        else $error("SVA: dmem BRESP error response received");

    // Pipeline: stall_IF and flush_DE cannot both be active
    property p_stall_flush_mutex;
        @(posedge clk) disable iff (!rst_n)
        !(stall_IF && flush_DE);
    endproperty
    assert property (p_stall_flush_mutex)
        else $error("SVA: stall_IF and flush_DE both active");

    // Pipeline: x0 must always read 0
    property p_x0_zero;
        @(posedge clk) disable iff (!rst_n)
        u_regfile.regs[0] == 32'd0;
    endproperty
    assert property (p_x0_zero)
        else $error("SVA: x0 is not zero");

    // Pipeline: PC must be 4-byte aligned
    property p_pc_aligned;
        @(posedge clk) disable iff (!rst_n)
        pc_out_IF[1:0] == 2'b00;
    endproperty
    assert property (p_pc_aligned)
        else $error("SVA: PC not 4-byte aligned");

    // synthesis translate_on

endmodule
