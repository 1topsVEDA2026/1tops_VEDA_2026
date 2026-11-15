# rtl/soc — SoC integration layer

This directory wires the core, SRAMs, bridges, peripherals and ASCON
accelerator into a single top-level `soc_top`.

## File tree

```
rtl/
├── core/                           # RV32IM core (existing)
├── memory/                         # AXI4 sim-only memory models (existing)
├── bridge/                         # AXI4 ↔ APB bridge + APB interconnect  (NEW)
│   ├── axi4_to_apb_bridge.sv       # ported from FUL_SOC_WITH_CORE/dut/bridge
│   └── apb_interconnect.sv         # 7-way APB demux
└── soc/                            # top-level integration                 (NEW)
    ├── soc_top.sv                  # top module — instantiates everything
    ├── imem_subsystem.sv           # AXI4-slave wrapper for I_SRAM_16Kb
    ├── dmem_subsystem.sv           # AXI4-slave wrapper for D_SRAM_16Kb
    ├── sys_ctrl.sv                 # reset sync + CHIP_ID + reset-cause
    └── README.md                   # this file
```

## Why these files exist

Before this commit, the GitHub repo had the leaf blocks (core, SRAM macros,
peripherals, ASCON) but **nothing that tied them together** — the actual
SoC integration lived only in the local
`1-TOPS Verification and Synthesis/TOPS/FUL_SOC_WITH_CORE/` tree. That
broke the G3 sign-off (items 3.10 SRAM integration, 3.11 interconnect,
3.12 system control, 3.13 address decode).

This directory brings the integration layer into the repo so every G3
item has a GitHub URL to point at.

## Instantiation hierarchy

```
soc_top
├── u_sysctrl          sys_ctrl              (clock + reset + CHIP_ID)
├── u_core             rv32_core_top         (the RV32IM core, rtl/core/)
├── u_imem             imem_subsystem        (AXI4 slave)
│   └── u_i_sram       i_sram_16kb           (Memory/I_SRAM_16Kb.sv)
├── u_dmem             dmem_subsystem        (AXI4 slave)
│   └── u_d_sram       d_sram_16kb           (Memory/D_SRAM_16Kb.sv)
├── u_bridge           axi4_to_apb_bridge    (AXI4 → APB)
├── u_apb_ic           apb_interconnect      (7-way APB demux)
│   ├── u_gpio         gpio                  (Peripherals/GPIO.sv)
│   ├── u_uart         uart                  (Peripherals/UART.sv)
│   ├── u_spi          spi                   (Peripherals/SPI.sv)
│   ├── u_timer        timer                 (Peripherals/TIMER.sv)
│   ├── u_wdt          watchdog              (TBD)
│   ├── u_plic         plic                  (Peripherals/PLIC)
│   └── u_clint        clint                 (Peripherals/CLINT.sv)
└── u_ascon            Ascon                 (Ascon_Hardware_Accelerator/)
```

## Address map (as implemented in `soc_top.sv`)

See `docs/G1_01_Specification_Document.md` §1.8 for the authoritative map.
The address decode in `soc_top.sv` must match it.

| Range                    | Target                 |
|--------------------------|------------------------|
| `0x0000_0000`–`0x0000_3FFF` | Instruction SRAM (16 KB) |
| `0x0000_4000`–`0x0000_7FFF` | Data SRAM (16 KB)        |
| `0x0000_8000`–`0x0000_EFFF` | APB peripherals (7 × 4 KB) |
| `0x0000_F000`–`0x0000_F07F` | ASCON-128 (AXI4-Lite)    |
| anything else              | DECERR                |

## G3 checklist evidence

| Item | Evidence (GitHub URL to paste into the checklist) |
|---|---|
| 3.10 SRAMs integrated | `rtl/soc/imem_subsystem.sv`, `rtl/soc/dmem_subsystem.sv`, `Memory/I_SRAM_16Kb.sv`, `Memory/D_SRAM_16Kb.sv` |
| 3.11 Interconnect integrated | `rtl/bridge/axi4_to_apb_bridge.sv`, `rtl/bridge/apb_interconnect.sv`, `rtl/soc/soc_top.sv` |
| 3.12 System control | `rtl/soc/sys_ctrl.sv` |
| 3.13 Address decode matches G1 map | `rtl/soc/soc_top.sv` (addr demux) + `docs/G1_01_Specification_Document.md` §1.8 |
