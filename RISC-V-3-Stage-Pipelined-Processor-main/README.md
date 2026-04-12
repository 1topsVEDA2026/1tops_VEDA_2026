# 3-Stage Pipelined Processor with CSR Interrupt Handling and Hazard Control

## Introduction

The implemented design is a 3-stage pipelined processor based on the RISC-V architecture. The processor includes support for Control and Status Register (CSR) operations, interrupt handling, and hazard control to ensure proper pipeline operation.

## Design Diagram
[Design Digaram of the Processor](https://drive.google.com/file/d/1-Jaxc-ljJdYGSnKBGZLWKSZPSmyyhVD9/view?usp=sharing)

## Architecture Overview

### Stages

1. **Fetch (IF):** The instruction is fetched from memory using the program counter.
2. **Decode and Execute (ID/EX):** The instruction is decoded, and the corresponding operations are executed. This stage includes Control Unit, ALU, Register File, and CSR handling.
3. **Memory and Writeback (EX/MEM & MEM/WB):** Memory operations are performed, and results are written back to the register file. This stage includes Data Memory, CSR Register File, and Hazard Control.

### Modules

1. **ALU (Arithmetic Logic Unit):** Performs various arithmetic and logic operations based on the ALU control signals provided by the Control Unit.

2. **Control Unit:** Decodes instructions and generates control signals for the entire processor, including ALU operations, register file operations, memory operations, and branch control.

3. **Branch Condition (br_cond):** Determines whether a branch instruction should be taken based on the specified condition.

4. **Controller:** Manages the overall control flow, generating control signals for different components based on the opcode and function fields of the instructions.

5. **CSR Register File:** Handles CSR operations, providing read and write access to various CSR registers.

6. **Data Memory (data_mem):** Simulates the data memory for load and store operations.

7. **Hazard Controller:** Detects hazards such as data hazards and control hazards, controlling the pipeline stall and flush conditions accordingly.

8. **Immediate Generator (imm_gen):** Extracts immediate values from instructions for various types of instructions.

9. **Instruction Decoder (inst_dec):** Extracts fields from the instruction, including opcode, funct3, funct7, and register addresses.

10. **Instruction Memory (inst_mem):** Represents the instruction memory, providing the next instruction to the pipeline.

11. **MUX (mux_2x1, mux_3x1):** Multiplexers used for selecting inputs based on control signals.

12. **PC (pc):** Represents the program counter and manages the fetching of instructions.

13. **First Register (first_reg):** Manages the registers for the first stage of the pipeline, handling stall, flush, and CSR-related operations.

14. **Second Register (second_reg):** Manages the registers for the second stage of the pipeline, handling stall, flush, and CSR-related operations.

15. **Hazard Unit:** Detects hazards and controls forwarding and stalling in the pipeline.

## Pipeline Operation

1. **Fetch (IF):** The program counter is incremented to fetch the next instruction from memory. The instruction is passed to the next stage.

2. **Decode and Execute (ID/EX):** The instruction is decoded, and the necessary control signals are generated. The ALU performs the specified operation, and CSR operations are handled. Hazard detection is also performed at this stage.

3. **Memory and Writeback (EX/MEM & MEM/WB):** Memory operations, such as load and store, are performed. The results are then written back to the register file. CSR operations are completed, and the pipeline control signals are adjusted based on hazard detection.

## Hazard Handling

The processor employs hazard control to handle potential data hazards and control hazards. The Hazard Controller detects hazards and manages the pipeline by stalling or flushing stages accordingly. Forwarding mechanisms are utilized to resolve data hazards by forwarding data directly from the ALU result or memory stage.

## CSR and Interrupt Handling

The CSR Register File manages control and status register operations, providing read and write access to specific CSR registers. The processor also handles interrupts using CSR registers related to interrupt processing.

## Conclusion

The implemented 3-stage pipelined processor with CSR interrupt handling and hazard control demonstrates a basic yet functional RISC-V processor architecture. The design incorporates various components and modules to handle different aspects of instruction execution, including arithmetic operations, control flow, CSR operations, and hazard detection. The pipeline structure enables improved throughput and performance.

# Guidelines
This repository contains code for 32-bit processor using RISC-V Instruction Set Architecture (ISA).

#### RTL can be compiled and simulated by just running ```compile.bat``` file which i've created in the same folder
Compilation and Simulation process is explained below:

## Compilation

RTL can be compiled with the command: 

``` 
vlog names_of_all_system_verilog_files
```

or simply:

``` 
vlog *.sv 
```

Compilation creates a ``` work ``` folder in your current working directory in which all the files generated after compilation are stored.
 
## Simulation

The compiled RTL can be simulated with command:

``` 
vsim -c name_of_toplevel_module -do "run -all"
```

Simulation creates a ``` .vcd ``` file. This files contains all the simulation behaviour of design.

## Viewing the VCD Waveform File

To view the waveform of the design run the command:

```
gtkwave dumpfile_name.vcd
```
Here dumpfile_name will be ```processor.vcd```

This opens a waveform window. Pull the required signals in the waveform and verify the behaviour of the design.


