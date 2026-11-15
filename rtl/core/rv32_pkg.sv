`timescale 1ns / 1ps

package rv32_pkg;

    // ----------------------------------------------------------------
    // Immediate format types
    // ----------------------------------------------------------------
    typedef enum logic [2:0] {
        IMM_NONE, IMM_I, IMM_S, IMM_B, IMM_U, IMM_J
    } imm_type_t;

    // ----------------------------------------------------------------
    // Execution class — drives the controller's main case statement
    // ----------------------------------------------------------------
    typedef enum logic [3:0] {
        EXEC_ALU,        // R-type ALU
        EXEC_ALU_IMM,    // I-type ALU
        EXEC_LOAD,       // Load
        EXEC_STORE,      // Store
        EXEC_BRANCH,     // Conditional branch
        EXEC_JAL,        // Jump and link
        EXEC_JALR,       // Jump and link register
        EXEC_LUI,        // Load upper immediate
        EXEC_AUIPC,      // Add upper immediate to PC
        EXEC_SYS,        // System (CSR / MRET)
        EXEC_MDU,        // M-extension: Multiply / Divide
        EXEC_ILL         // Illegal instruction
    } exec_class_t;

    // ----------------------------------------------------------------
    // MDU function select (matches RISC-V M-ext funct3 encoding)
    // ----------------------------------------------------------------
    typedef enum logic [2:0] {
        MDU_MUL    = 3'd0,   // Lower 32 bits  signed×signed
        MDU_MULH   = 3'd1,   // Upper 32 bits  signed×signed
        MDU_MULHSU = 3'd2,   // Upper 32 bits  signed×unsigned
        MDU_MULHU  = 3'd3,   // Upper 32 bits  unsigned×unsigned
        MDU_DIV    = 3'd4,   // Signed quotient
        MDU_DIVU   = 3'd5,   // Unsigned quotient
        MDU_REM    = 3'd6,   // Signed remainder
        MDU_REMU   = 3'd7    // Unsigned remainder
    } mdu_func_t;

    // ----------------------------------------------------------------
    // CSR command type
    // ----------------------------------------------------------------
    typedef enum logic [3:0] {
        CSR_NONE,
        CSR_RW, CSR_RS, CSR_RC,
        CSR_RWI, CSR_RSI, CSR_RCI,
        CSR_MRET
    } csr_cmd_t;

    // ----------------------------------------------------------------
    // ALU function select
    // ----------------------------------------------------------------
    typedef enum logic [4:0] {
        ALU_ADD    = 5'd0,
        ALU_SUB    = 5'd1,
        ALU_SLL    = 5'd2,
        ALU_SLT    = 5'd3,
        ALU_SLTU   = 5'd4,
        ALU_XOR    = 5'd5,
        ALU_SRL    = 5'd6,
        ALU_SRA    = 5'd7,
        ALU_OR     = 5'd8,
        ALU_AND    = 5'd9,
	ALU_PASS_B = 5'd10
    } alu_func_t;

    // ----------------------------------------------------------------
    // Writeback source select
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {
        WB_PC4 = 2'b00,
        WB_ALU = 2'b01,
        WB_MEM = 2'b10,
        WB_CSR = 2'b11
    } wb_sel_t;

    // ----------------------------------------------------------------
    // Branch type (matches RISC-V funct3 encoding)
    // ----------------------------------------------------------------
    typedef enum logic [2:0] {
        BR_BEQ  = 3'b000,
        BR_BNE  = 3'b001,
        BR_BLT  = 3'b100,
        BR_BGE  = 3'b101,
        BR_BLTU = 3'b110,
        BR_BGEU = 3'b111
    } br_type_t;

    // ----------------------------------------------------------------
    // Memory access type (matches RISC-V funct3 encoding)
    // ----------------------------------------------------------------
    typedef enum logic [2:0] {
        MEM_BYTE   = 3'b000,
        MEM_HALF   = 3'b001,
        MEM_WORD   = 3'b010,
        MEM_BYTE_U = 3'b100,
        MEM_HALF_U = 3'b101
    } mem_acc_t;

endpackage
