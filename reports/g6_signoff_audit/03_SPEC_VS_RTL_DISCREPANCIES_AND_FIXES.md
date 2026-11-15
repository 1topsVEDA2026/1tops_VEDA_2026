# Critical Spec vs RTL Discrepancies & Code Fixes

This document compiles the concrete architectural discrepancies discovered across the documentation, RTL, and testbenches, providing exact SystemVerilog code patches to resolve them.

---

## 1. Discrepancy Matrix: Memory Sizes & Address Maps

| Parameter / Memory Region | Doc Paragraphs 30–32 | Doc Table 10 | Signoff Checklist (G1.6) | RTL / TB Implementation | Target Signoff Fix |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Boot ROM Size** | 4 KB | 2 KB (`0x0000_0000 - 0x0000_07FF`) | 4 KB | 4 KB in `axi4_imem_slave.sv`; 256 B in `soc_no_core_dut.sv` | **Fix at 4 KB** (`0x0000_0000 – 0x0000_0FFF`) |
| **Instruction SRAM** | 16 KB | 32 KB (`0x0001_0000 - 0x0001_7FFF`) | 16 KB | 16 KB in `I_SRAM_16Kb.sv`; 4 KB in `axi4_imem_slave.sv` | **Fix at 16 KB** (`0x0001_0000 – 0x0001_3FFF`) |
| **Data SRAM** | 16 KB | 32 KB (`0x0002_0000 - 0x0002_7FFF`) | 16 KB | 16 KB in `D_SRAM_16Kb.sv`; 4 KB in `axi4_dmem_slave.sv` | **Fix at 16 KB** (`0x0002_0000 – 0x0002_3FFF`) |
| **CLINT Base Address** | `0x0200_0000` | `0x0200_0000` (64 KB) | Standard RISC-V | APB Slot 6 (`0x6000`); `0x1000` in no-core DUT | Keep APB offset `0x6000`, decode at `0x0200_0000` |
| **PLIC Base Address** | `0x0C00_0000` | `0x0C00_0000` (16 KB) | Standard RISC-V | APB Slot 5 (`0x5000`); `0x2000` in no-core DUT | Keep APB offset `0x5000`, decode at `0x0C00_0000` |
| **ASCON Accelerator** | AXI-mapped | `0x4000_0000` (96 B) | Peripheral | Present in `1tops_VEDA_2026-main` | Map to `0x4000_0000 – 0x4000_00FF` |

---

## 2. Code Patch 1: Fixing Latch Inference in `csr_regfile.sv`

### Location: `csr_regfile.sv:104-108`
### Root Cause
SpyGlass and VCS Lint flagged that `mip[11]`, `mip[7]`, and `mip[3]` were assigned in an `always_ff` block while the remaining 29 bits of `mip` were unassigned, creating holding latches / floating logic.

### Original Faulty Code
```verilog
// In csr_regfile.sv:
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ...
        mip <= 32'd0;
    end else begin
        mip[11] <= irq_external;   // MEIP
        mip[7]  <= irq_timer;      // MTIP
        mip[3]  <= irq_software;   // MSIP
        ...
```

### Corrected Code (Clean of Latch & Fully Compliant)
```verilog
// Assign all unused mip bits cleanly to 0:
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mstatus  <= 32'd0;
        mie      <= 32'd0;
        mtvec    <= 32'd0;
        mscratch <= 32'd0;
        mepc     <= 32'd0;
        mcause   <= 32'd0;
        mtval    <= 32'd0;
        mip      <= 32'd0;
    end else begin
        // Fully specify all 32 bits of mip (zeroing unimplemented/reserved bits)
        mip <= {20'b0, irq_external, 3'b0, irq_timer, 3'b0, irq_software, 3'b0};

        if (epc_taken_IF) begin
        ...
```

---

## 3. Code Patch 2: Core Interrupt Trap Dispatch & Vectoring

### Location: `csr_regfile.sv` and `rv32_core_top.sv`
### Root Cause
The CPU core only redirected on illegal instructions (`trap_illegal`) and had no hardware connection to take traps on external, timer, or software interrupts.

### Code Patch for `csr_regfile.sv`
Add ports to `csr_regfile`:
```verilog
    // Add to module port list:
    output logic        irq_trap_req,
    output logic [31:0] irq_trap_cause
```
Add logic to compute pending enabled interrupts:
```verilog
    wire meip_active = mip[11] & mie[11];
    wire mtip_active = mip[7]  & mie[7];
    wire msip_active = mip[3]  & mie[3];

    // Interrupts globally enabled when mstatus.MIE (bit 3) is 1
    wire global_irq_en = mstatus[3];

    assign irq_trap_req = global_irq_en & (meip_active | mtip_active | msip_active);

    // Standard RISC-V interrupt cause codes (bit 31 = 1)
    always_comb begin
        if (meip_active)
            irq_trap_cause = 32'h8000_000B; // Machine External Interrupt
        else if (msip_active)
            irq_trap_cause = 32'h8000_0003; // Machine Software Interrupt
        else if (mtip_active)
            irq_trap_cause = 32'h8000_0007; // Machine Timer Interrupt
        else
            irq_trap_cause = 32'h0000_0000;
    end
```

### Code Patch for `rv32_core_top.sv`
Update trap arbitration:
```verilog
    // Wires from CSR
    logic        irq_trap_req;
    logic [31:0] irq_trap_cause;

    // Combined Trap Trigger: Illegal Instruction (Exception) OR Interrupt
    wire trap_active = (trap_illegal | irq_trap_req) & ready_IF;
    wire [31:0] trap_cause_mux = trap_illegal ? 32'd2 : irq_trap_cause;

    // Vectored vs Direct mtvec Next-PC Calculation
    logic [31:0] trap_target_pc;
    always_comb begin
        if (mtvec_out[1:0] == 2'b01 && trap_cause_mux[31]) begin
            // Vectored mode for interrupts: BASE + 4 * cause_index
            trap_target_pc = {mtvec_out[31:2], 2'b00} + (trap_cause_mux[3:0] << 2);
        end else begin
            // Direct mode: BASE
            trap_target_pc = {mtvec_out[31:2], 2'b00};
        end
    end

    // Update Next-PC Mux:
    always_comb begin
        if (trap_active)
            nxt_pc = trap_target_pc;
        else if (is_mret_DE & valid_DE)
            nxt_pc = epc_pc;
        else if (branch_taken)
            nxt_pc = branch_target;
        else
            nxt_pc = pc_out_IF + 32'd4;
    end
```

---

## 4. Code Patch 3: Unmapped Address Error Handling (`DECERR` & `PSLVERR`)

### Location: `apb_interconnect.sv`
In `apb_interconnect.sv`, any transaction with `slave_sel >= 7` or unmapped address must assert `pslverr_o`:
```verilog
    always_comb begin
        if (psel_i && (slave_sel >= NUM_SLAVES)) begin
            // Unmapped address access
            prdata_o  = 32'hDEAD_BEEF;
            pready_o  = 1'b1;
            pslverr_o = 1'b1; // Signal APB transfer error
        end else begin
            prdata_o  = prdata_i[slave_sel];
            pready_o  = pready_i[slave_sel];
            pslverr_o = pslverr_i[slave_sel];
        end
    end
```

### Location: `dut/bridge/axi4_to_apb_bridge.sv`
Ensure APB `pslverr` maps directly to AXI error responses:
```verilog
    assign axi_bresp = apb_pslverr ? 2'b10 : 2'b00; // 2'b10 = SLVERR
    assign axi_rresp = apb_pslverr ? 2'b10 : 2'b00;
```
For unmapped AXI memory regions outside peripherals and SRAM:
```verilog
    assign dmem_bresp = is_unmapped ? 2'b11 : ...; // 2'b11 = DECERR
```

---

## 5. Code Patch 4: Adding Reset Synchronizer to Top Level

### Implementation: `rst_sync.sv`
```verilog
`timescale 1ns / 1ps

module rst_sync (
    input  logic clk,
    input  logic ext_rst_n,
    output logic sync_rst_n
);
    (* async_reg = "true" *) logic rst_meta, rst_sync_q;

    always_ff @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_meta   <= 1'b0;
            rst_sync_q <= 1'b0;
        end else begin
            rst_meta   <= 1'b1;
            rst_sync_q <= rst_meta;
        end
    end

    assign sync_rst_n = rst_sync_q;
endmodule
```
Instantiate `rst_sync` in `soc_top.sv` so that all internal synchronous logic is driven by `sync_rst_n`.
