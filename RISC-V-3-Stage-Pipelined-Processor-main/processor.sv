module processor 
(
    input logic clk,
    input logic rst
); 
    // wires
    logic        rf_en;
    logic        sel_b;
    logic [31:0] pc_out;
    logic [31:0] new_pc;
    logic [31:0] inst;
    logic [ 4:0] rd;
    logic [ 4:0] rs1;
    logic [ 4:0] rs2;
    logic [ 6:0] opcode;
    logic [ 2:0] funct3;
    logic [ 6:0] funct7;
    logic [31:0] rdata1;
    logic [31:0] rdata2;
    logic [31:0] opr_a;
    logic [31:0] opr_b;
    logic [31:0] opr_res;
    logic [11:0] imm;
    logic [31:0] imm_val;
    logic [31:0] wdata;
    logic [3 :0] aluop;
    logic [31:0] rdata;
    logic        rd_en;
    logic        wr_en;
    logic [ 1:0] wb_sel;
    logic        br_taken;
    logic [ 2:0] br_type;
    logic [ 2:0] mem_acc_mode;
     // Wires from First_Register
    logic        Stall;
    logic        Flush;
    logic        csr_Flush;
    logic        is_mret;
    logic [31:0] Addr;
    logic [31:0] Inst;
    logic        is_mretF;
    logic [31:0] AddrF;
    logic [31:0] InstF;

    // Wires from Second_Register
    logic        Stall_MW;
    logic [31:0] waddr;
    logic [31:0] ALUResult;
    logic        SrcBE;
    logic        SrcAE;
    logic [31:0] ImmExtD;
    logic [31:0] waddr_MW;
    logic [31:0] Addr_MW;
    logic [31:0] ALUResult_MW;
    logic [31:0] rdata2_MW;
    logic        SrcA_MW;
    logic [31:0] ImmExt_MW;

    // HazardUnit Wires
    logic reg_wrMW;
    logic valid;
    logic [1:0] wb_selMW;
    logic [4:0] raddr1;
    logic [4:0] raddr2;
    logic [31:0] For_A;
    logic [31:0] For_B;

    // HazardController Wires
    logic [31:0] csr_reg_rd;
    logic [31:0] csr_reg_wr;
    logic [31:0] csr_reg_rdMW;
    logic [31:0] csr_reg_wrMW;
    logic is_mretMW;
    logic [2:0] InstF_MW_funct3;
    logic [6:0] InstF_MW_opcode;

    // PC MUX
    mux_2x1 mux_2x1_pc
    (
        .in_0        ( pc_out + 32'd4 ),
        .in_1        ( opr_res        ),
        .select_line ( br_taken       ),
        .out         ( new_pc         )
    );

    // program counter
    pc pc_i
    (
        .clk   ( clk            ),
        .rst   ( rst            ),
        .pc_in ( new_pc         ),
        .pc_out( pc_out         )
    );

    // instruction memory
    inst_mem inst_mem_i
    (
        .addr  ( pc_out         ),
        .data  ( inst           )
    );

    // instruction decoder
    inst_dec inst_dec_i
    (
        .inst  ( inst           ),
        .rs1   ( rs1            ),
        .rs2   ( rs2            ),
        .rd    ( rd             ),
        .opcode( opcode         ),
        .funct3( funct3         ),
        .funct7( funct7         )
    );

    // register file
    reg_file reg_file_i
    (
        .clk   ( clk            ),
        .rf_en ( rf_en          ),
        .rd    ( rd             ),
        .rs1   ( rs1            ),
        .rs2   ( rs2            ),
        .rdata1( rdata1         ),
        .rdata2( rdata2         ),
        .wdata ( wdata          )
    );

    // immediate generator
    imm_gen imm_gen_i
    (
        .inst   ( inst          ),
        .imm_val( imm_val       )
    );

    // ALU opr_a MUX

    mux_2x1 mux_2x1_alu_opr_a
    (
        .in_0           ( pc_out  ),
        .in_1           ( rdata1  ),
        .select_line    ( sel_a   ),
        .out            ( opr_a   )
    );

    // ALU opr_b MUX
    mux_2x1 mux_2x1_alu_opr_b
    (
        .in_0           ( rdata2  ),
        .in_1           ( imm_val ),
        .select_line    ( sel_b   ),
        .out            ( opr_b   )
    );


    // alu
    alu alu_i
    (
        .aluop   ( aluop          ),
        .opr_a   ( opr_a          ),
        .opr_b   ( opr_b          ),
        .opr_res ( opr_res        )
    );


    data_mem data_mem_i
    (
        .clk            ( clk          ),
        .rd_en          ( rd_en        ),
        .wr_en          ( wr_en        ),
        .addr           ( opr_res      ),
        .mem_acc_mode   ( mem_acc_mode ),
        .rdata2         ( rdata2       ),
        .rdata          ( rdata        )
    );


    // Writeback MUX
    mux_3x1 wb_mux
    (
        .in_0           ( pc_out + 32'd4 ),
        .in_1           ( opr_res        ),
        .in_2           ( rdata          ),
        .select_line    ( wb_sel         ),
        .out            ( wdata          )
    );


    // controller
    controller controller_i
    (
        .opcode         ( opcode         ),
        .funct3         ( funct3         ),
        .funct7         ( funct7         ),
        .br_taken       ( br_taken       ),
        .aluop          ( aluop          ),
        .rf_en          ( rf_en          ),
        .sel_a          ( sel_a          ),
        .sel_b          ( sel_b          ),
        .rd_en          ( rd_en          ),
        .wr_en          ( wr_en          ),
        .wb_sel         ( wb_sel         ),
        .mem_acc_mode   ( mem_acc_mode   ),
        .br_type        ( br_type        ),
        .br_take        ( br_taken       )
    );

    first_reg firs_register (
        .clk(clk),
        .rst(rst),
        .Stall(Stall),
        .Flush(Flush),
        .csr_Flush(csr_Flush),
        .is_mret(is_mret),
        .Addr(Addr),
        .Inst(Inst),
        .is_mretF(is_mretF),
        .AddrF(AddrF),
        .InstF(InstF));

    second_reg second_register(
        .clk(clk),
        .rst(rst),
        .Stall_MW(Stall_MW),
        .waddr(waddr),
        .AddrF(AddrF),
        .ALUResult(ALUResult),
        .SrcBE(SrcBE),
        .SrcAE(SrcAE),
        .ImmExtD(ImmExtD),
        .waddr_MW(waddr_MW),
        .Addr_MW(Addr_MW),
        .ALUResult_MW(ALUResult_MW),
        .rdata2_MW(rdata2_MW),
        .SrcA_MW(SrcA_MW),
        .ImmExt_MW(ImmExt_MW)
        );

    HazardUnit hazardunit (
        .reg_wrMW(reg_wrMW),
        .br_taken(br_taken),
        .valid(valid),
        .wb_selMW(wb_sel),
        .raddr1(raddr1),
        .raddr2(raddr2),
        .waddr_MW(waddr_MW),
        .For_A(For_A),
        .For_B(For_B),
        .Stall(Stall),
        .Stall_MW(Stall_MW),
        .Flush(Flush));

    HazardController hazardcontroller(
        .clk(clk),
        .rst(rst),
        .reg_wr(reg_wr),
        .Stall_MW(Stall_MW),
        .csr_reg_rd(csr_reg_rd),
        .csr_reg_wr(csr_reg_wr),
        .is_mretF(is_mretF),
        .wb_sel(wb_sel),
        .InstF(InstF),
        .reg_wrMW(reg_wrMW),
        .csr_reg_rdMW(csr_reg_rdMW),
        .csr_reg_wrMW(csr_reg_wrMW),
        .is_mretMW(is_mretMW),
        .wb_selMW(wb_selMW),
        .InstF_MW_funct3(InstF_MW_funct3),
        .InstF_MW_opcode(InstF_MW_opcode));



    
endmodule