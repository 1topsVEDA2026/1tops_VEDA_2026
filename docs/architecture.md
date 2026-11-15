# RV32IM Processor Microarchitecture Specification

## 1. Architectural Overview

The processor implements the **RV32IM** user ISA specification with machine-mode privileged CSR support and an AXI4 memory interface.

- **ISA**: RV32IM (Base 32-bit Integer + Multiply/Divide Extensions)
- **Privilege Level**: Machine Mode (M-Mode) with Trap & Exception Handling
- **Pipeline Architecture**: 3-Stage In-Order Pipeline (`IF` → `DE` → `MW`)
- **Bus Interfaces**: Dual Independent AXI4 Channels (Instruction Memory Master & Data Memory Master)
- **Arithmetic & Logic Unit**: Full 32-bit ALU for RV32I arithmetic, logical, and shift operations
- **Multiplication & Division Unit (MDU)**:
  - **Multiplier**: Radix-4 Booth Multiplier (multi-cycle signed/unsigned)
  - **Divider**: Restoring Division Engine (multi-cycle signed/unsigned)
- **Hazard Handling**: Dynamic data forwarding, load-use stall insertion, control-hazard pipeline flushing, and memory stall freezing
- **Control and Status Registers (CSRs)**: `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `mhartid`, `mvendorid`, `marchid`, `mimpid`

---

## 2. Pipeline Stage Breakdown

```
        ┌─────────────┐       ┌──────────────┐       ┌──────────────┐
        │  IF Stage   │  ───> │   DE Stage   │  ───> │   MW Stage   │
        │ Fetch & PC  │       │ Decode & Exe │       │ Mem & Reg WB │
        └─────────────┘       └──────────────┘       └──────────────┘
               │                      │                      │
               ▼                      ▼                      ▼
         AXI4 IMEM Bus         MDU / ALU / CSR         AXI4 DMEM Bus
```

### Stage 1: Instruction Fetch (IF)
- **Program Counter Unit**: Tracks the current PC. Features configurable `RESET_PC` (defaults to `0x0000_0000` for stand-alone RTL mode, configurable to `0x8000_0000` for Spike ISS co-simulation).
- **Next-PC Multiplexer**: Selects next PC based on:
  1. Trap/Interrupt redirect vector (`mtvec` address)
  2. Exception return vector (`mepc` address on `mret`)
  3. Branch/Jump target (`opr_res_DE` on taken branch, `jal`, or `jalr`)
  4. Sequential PC (`pc_out_IF + 4`)
- **AXI4 IMEM Master**: Read-only AXI4 master interface (`AR` and `R` channels). Continuous speculative instruction fetch with zero-latency streaming.
- **Pipeline Register (`pipe_if_de`)**: Latches fetched instruction and PC when `ready_DE` is high; flushes on control redirects (`flush_DE`).

### Stage 2: Decode & Execute (DE)
- **Decoder**: Decodes RV32IM opcodes, funct3, funct7, registers, immediate types, execution class, and memory access widths.
- **Register File (`register_file.sv`)**: 32 x 32-bit general-purpose registers (x0 hardwired to 0). Synchronous write, asynchronous read with internal bypass.
- **Immediate Generator (`imm_gen.sv`)**: Extracts and sign-extends I-type, S-type, B-type, U-type, and J-type immediates.
- **ALU (`alu.sv`)**: Single-cycle execution for `ADD`, `SUB`, `SLT`, `SLTU`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`, `LUI`, and `AUIPC`.
- **MDU (`mdu.sv`)**: Multi-cycle hardware multiplier and divider.
  - Multiplier uses **Booth Radix-4 encoding**, reducing partial products by half.
  - Divider uses a **restoring division algorithm** handling all corner cases (`DIV/REM` by zero, `INT_MIN / -1` signed overflow).
  - Asserts `mdu_stall` to freeze the pipeline during calculation.
- **Branch Comparator (`branch_cmp.sv`)**: Evaluates `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` directly in the DE stage for early branch resolution.
- **CSR Unit (`csr_regfile.sv`)**: Manages Machine-mode CSR accesses (`CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI`) and trap vectors.

### Stage 3: Memory & Writeback (MW)
- **AXI4 DMEM Master**: Full read/write AXI4 master interface (`AW`, `W`, `B`, `AR`, `R`).
  - Supports byte (`SB`, `LB`, `LBU`), half-word (`SH`, `LH`, `LHU`), and word (`SW`, `LW`) accesses with proper byte strobes (`wstrb`).
  - Implements an internal FSM (`DM_IDLE`, `DM_RD`, `DM_WR`) supporting zero-latency and multi-cycle slaves.
  - Properly latches AR, AW, and W handshakes occurring in `DM_IDLE` to guarantee AXI4 protocol compliance.
- **Writeback Mux**: Selects destination write data (`wdata`) from ALU result, memory load data, MDU result, CSR read data, or PC+4 (for link instructions).
- **Register File Writeback**: Asserts `rf_en_MW` and drives `rd_addr_MW` and `wdata`.

---

## 3. Hazard Handling & Pipeline Interlocks

```
  Hazard Condition        Action Taken
  ──────────────────────  ──────────────────────────────────────────────────
  RAW (ALU to ALU)        Forward result from MW stage back to DE stage inputs
  Load-Use Dependency     Stall IF & DE for 1 cycle; insert bubble into MW stage
  MDU Busy (Mult / Div)   Assert mdu_stall; freeze IF, DE, and MW stages
  Memory Wait (AXI4 wait) Assert dmem_stall; freeze MW stage outputs
  Branch / Jump Taken     Flush IF->DE pipeline register (1-cycle branch penalty)
  Trap / MRET Redirect    Flush IF->DE register and reload PC from mtvec / mepc
```

---

## 4. AXI4 Bus Interface Specification

The core provides two independent 32-bit AXI4 master ports:

### Instruction Memory Interface (IMEM)
| Channel | Signal | Direction | Description |
|---|---|---|---|
| AR | `imem_araddr[31:0]` | Output | Instruction fetch address |
| AR | `imem_arvalid` | Output | Address valid |
| AR | `imem_arready` | Input | Slave ready |
| AR | `imem_arsize[2:0]` | Output | `3'b010` (4 bytes) |
| AR | `imem_arburst[1:0]` | Output | `2'b01` (INCR) |
| R | `imem_rdata[31:0]` | Input | Instruction word |
| R | `imem_rvalid` | Input | Read data valid |
| R | `imem_rready` | Output | Core always ready (`1'b1`) |

### Data Memory Interface (DMEM)
| Channel | Signal | Direction | Description |
|---|---|---|---|
| AW | `dmem_awaddr[31:0]` | Output | Store write address |
| AW | `dmem_awvalid` | Output | Write address valid |
| AW | `dmem_awready` | Input | Slave address ready |
| W | `dmem_wdata[31:0]` | Output | Store data |
| W | `dmem_wstrb[3:0]` | Output | Byte enable strobes |
| W | `dmem_wvalid` | Output | Write data valid |
| W | `dmem_wready` | Input | Slave data ready |
| B | `dmem_bvalid` | Input | Write response valid |
| B | `dmem_bready` | Output | Master ready for write response |
| AR | `dmem_araddr[31:0]` | Output | Load read address |
| AR | `dmem_arvalid` | Output | Read address valid |
| AR | `dmem_arready` | Input | Slave read address ready |
| R | `dmem_rdata[31:0]` | Input | Read data |
| R | `dmem_rvalid` | Input | Read data valid |
| R | `dmem_rready` | Output | Master ready for read data |
