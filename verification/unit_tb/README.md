# Unit Testbench Suite (Phase-1 Verification)

This directory contains standalone, self-checking unit-level testbenches for individual execution and sub-block verification of the RV32IM processor core modules.

## Module Testbenches

| Unit / Block | Testbench File | Target Module | Scope of Verification |
|:---|:---|:---|:---|
| **Program Counter (PC) Unit** | `tb_pc.sv` | `rtl/core/pc_unit.sv` | Parameterized reset vector (`RESET_PC = 0x0000_0000` / `0x8000_0000`), sequential increment (`PC+4`), pipeline freeze on stalls, halfword/word alignment enforcement, and strict redirect priority hierarchy (`Trap > MRET > Branch/Jump > Sequential`). |
| **Multiply / Divide Unit (MDU)** | `tb_mdu.sv` | `rtl/core/mdu.sv` | All 8 RV32M operations (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`), Booth Radix-4 3-cycle multiplication, restoring 33-cycle iterative division, divide-by-zero corner cases, signed overflow (`INT_MIN / -1`), and stall/backpressure handshake sequences. |
| **Memory Interface Unit (MIU)** | `tb_miu.sv` | `rtl/core/miu.sv` | All transfer sizes (`Byte`, `Halfword`, `Word`) across all byte offset combinations (`0, 1, 2, 3`), signed and unsigned load extensions (`LB`, `LBU`, `LH`, `LHU`, `LW`), store data lane alignment, byte enable generation (`wstrb`), and single outstanding transaction pipeline stall timing (`dmem_stall`). |
| **ALU** | `tb_alu.sv` | `rtl/core/alu.sv` | Arithmetic (`ADD`, `SUB`), logical (`AND`, `OR`, `XOR`), and shift operations (`SLL`, `SRL`, `SRA`) across data corner cases (`0x8000_0000`, `0x7FFF_FFFF`, `0`, `0xFFFF_FFFF`) and variable shift amounts (`0, 1, 31, >31`). |
| **Branch Comparator** | `tb_branch_cmp.sv` | `rtl/core/branch_cmp.sv` | Branch comparison evaluations (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) verifying taken and not-taken conditions for signed and unsigned comparisons (`rs1 < rs2`, `rs1 == rs2`, `rs1 > rs2`). |
| **Instruction Decoder** | `tb_decoder.sv` | `rtl/core/decoder.sv` | Full decode space validation for RV32I integer and RV32M extension opcodes, instruction field extraction (`rs1`, `rs2`, `rd`, `csr`), funct3/funct7 decoding, and illegal instruction exception signaling. |
| **Hazard & Forwarding Unit** | `tb_hazard_unit.sv` | `rtl/core/hazard_unit.sv` | Forwarding path validation (ALU-to-use, load-to-use, store data), load-use pipeline interlock stalls, branch/trap pipeline flushes, and multi-cycle execution stalls. |
| **Register File** | `tb_register_file.sv` | `rtl/core/register_file.sv` | Read and write operations across all 32 architectural registers (`x0` to `x31`), verifying hardwired-zero behavior for `x0` and same-cycle write-read bypass correctness. |
| **Immediate Generator** | `tb_imm_gen.sv` | `rtl/core/imm_gen.sv` | Sign-extension and formatting for all RISC-V instruction immediate formats: I-type, S-type, B-type, U-type, and J-type. |

---

## Running the Unit Testbenches

The testbenches are written in standard SystemVerilog and can be simulated with QuestaSim, VCS, or Vivado XSim:

```bash
# Example simulation using VCS:
vcs -sverilog -full64 +incdir+../../rtl/core ../../rtl/core/rv32_pkg.sv ../../rtl/core/alu.sv tb_alu.sv -R
vcs -sverilog -full64 +incdir+../../rtl/core ../../rtl/core/pc_unit.sv tb_pc.sv -R
vcs -sverilog -full64 +incdir+../../rtl/core ../../rtl/core/rv32_pkg.sv ../../rtl/core/booth_multiplier_radix4.sv ../../rtl/core/mdu.sv tb_mdu.sv -R
vcs -sverilog -full64 +incdir+../../rtl/core ../../rtl/core/rv32_pkg.sv ../../rtl/core/miu.sv tb_miu.sv -R

# Example simulation using QuestaSim:
vlog +incdir+../../rtl/core ../../rtl/core/rv32_pkg.sv ../../rtl/core/alu.sv tb_alu.sv
vsim -c tb_alu -do "run -all; quit -f"
```
