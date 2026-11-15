# 1-TOPS VEDA — Boot Plan

**G1 item 1.12 — Boot plan defined**
**Team:** VEDA · PSG College of Technology
**Project:** 1-TOPS Secure IoT RISC-V SoC (RV32IM + ASCON-128)
**Revision:** 1.0 · 2026-11-15

---

## 1. Boot architecture

**Decision:** **Single boot source — on-chip Instruction SRAM at address `0x0000_0000`. No boot-mode strap, no external SPI-flash boot, no boot ROM.**

| Attribute | Value |
|---|---|
| Boot PC (RESET_PC) | `0x0000_0000` (hardwired, parameter in `rv32_core_top.sv`) |
| Primary boot source | On-chip Instruction SRAM (`I_SRAM_16Kb`), 16 KB |
| Secondary boot source | None |
| Boot-mode strap pin | **None** |
| Boot ROM | **None** (no separate 4 KB ROM) |
| SPI-flash boot | **Not supported** in this revision |
| XIP (eXecute In Place) | **Not supported** |
| Firmware load mechanism | Pre-loaded at silicon bring-up via JTAG (post-tape-out) or via `$readmemh` in simulation |

---

## 2. Why no boot ROM and no SPI boot

The 1-TOPS Guidelines recommend an optional 4 KB boot ROM and SPI-flash boot. VEDA has consciously deviated for the following reasons:

1. **Area.** A separate 4 KB ROM macro adds ≈ 1,500 µm² at ASAP7 and requires a ROM-code build flow.
2. **Simplicity.** Single boot source removes the need for a strap pin, a remap register, a two-phase boot sequence, and SPI-flash timing verification.
3. **Target application.** 1-TOPS is a secure IoT SoC — firmware size is small (Dhrystone fits well under 4 KB; ASCON firmware + drivers fits comfortably in 16 KB I-SRAM).
4. **Verification scope.** The G6 Phase 5 schedule does not include SPI-flash-boot verification (items 6.10, 6.11 marked N/A).
5. **Programmability.** For bring-up, JTAG will load firmware into I-SRAM over the debug interface. No need for a programmable flash model in the SoC.

> **Coach waiver required.** This deviates from the 1-TOPS Guidelines (`Copy of Guidelines for RISC V SoC.pdf`, "Booting via SPI Flash" marked Yes/mandatory under Recommended Peripherals). The deviation is explicitly noted here and in checklist items G3.9, G6.10, G6.11.

---

## 3. Boot sequence (silicon)

```
   t = 0        rst_n = 0 (async assert)
                │
                ▼
   t = 1..n    rst_n held low — all flops reset:
                  • pc_out_IF = RESET_PC = 0x0000_0000
                  • mstatus = 0, mie = 0, mip = 0
                  • mtvec = 0, mepc = 0, mcause = 0
                  • x1..x31 = undefined (register file is RAM, not reset)
                  • I-SRAM contents = pre-loaded via JTAG prior to reset
                │
                ▼
   t = n+1     rst_n synchronous release on rising clk edge
                │
                ▼
   t = n+2     IF stage issues AXI4 AR @ imem_araddr = 0x0000_0000
                │
                ▼
   t = n+3     I-SRAM slave returns first instruction
                │
                ▼
   t = n+4     DE stage starts decoding first instruction
                │
                ▼
   Normal pipelined execution thereafter.
```

**No wait-states.** I-SRAM is zero-latency, so the core begins executing from `0x0000_0000` within 2–3 cycles of reset release.

---

## 4. Firmware image layout

Firmware is a RISC-V ELF compiled with `riscv32-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32`, linked against `link_rtl.ld` (base `0x0000_0000`).

| Section | Location | Purpose |
|---|---|---|
| `.text` | `0x0000_0000` – … | Boot code + runtime + application. First instruction = reset vector handler. |
| `.rodata` | After `.text` | Constant data |
| `.data` | After `.rodata` | Initialised globals (copied to D-SRAM at startup by crt0) |
| `.bss` | In D-SRAM | Zeroed globals (zeroed by crt0) |
| Stack | Top of D-SRAM, grows down | Set up by crt0 (`sp = 0x0000_7FFC` with 16 KB D-SRAM at `0x4000`) |

**crt0.S** (startup assembler, from `verification/benchmark/src/crt.S`) performs:

1. Set `sp` to top-of-D-SRAM.
2. Zero `.bss` region.
3. Copy `.data` from ROM image in `.text` to D-SRAM.
4. Set `mtvec` to the C-level trap handler (`_trap_entry`).
5. `jal main` → user firmware.
6. On return from `main`, infinite loop `j .` (or ECALL for sim-exit).

---

## 5. Bring-up (post-silicon) firmware-load flow

Since there is no mask-ROM bootloader and no flash, firmware must be loaded over JTAG at every power-up.

1. Power-up board; hold `rst_n` low.
2. Connect JTAG debug probe to on-chip debug module (**JTAG DM is a G7/G8 add-on — pins TBD, see Spec §1.11**).
3. Halt core at reset vector.
4. Debugger writes firmware image into I-SRAM `0x0000_0000` – `0x0000_3FFF` over JTAG abstract-access bus.
5. Debugger writes `dpc = 0x0000_0000`.
6. Debugger issues `dret` to resume; core begins executing firmware.

> **Open action:** Freeze the RISC-V Debug Module v0.13 integration (JTAG pins, DM address, abstract-command set) as part of Spec §1.11 before G9. Without JTAG the chip can only run what the fab programs into the macro — which the ASAP7 flow does not support — so **JTAG is mandatory for a working chip**.

---

## 6. Simulation boot (today)

For simulation, firmware is loaded directly into the I-SRAM model with `$readmemh` at `$readmemh("rtl_prog_word.hex", u_imem.mem);` at time 0 in the testbench. The RTL then releases reset and begins execution — identical behaviour to silicon from the core's point of view.

Verification evidence:
- `verification/core_sanity/rv32_core_sanity_tb.sv` — Suite 1 Reset Sequence (2 tests PASS)
- `TOPS_FINAL/benchmark/dhrystone_spike.log` — Dhrystone boot and run (500 iters, 1.281 DMIPS/MHz)
- `FUL_SOC_WITH_CORE/logs/soc_boot_sanity_test.log` — MUL 10×20 = 200 → GPIO, PASS

---

