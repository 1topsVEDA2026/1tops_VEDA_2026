# ============================================================================
# test_mext_basic.S — M-Extension Basic Operations (Spike vs RTL Comparison)
#
# Tests all 8 RV32M instructions with simple positive values and
# signed operands. Results are observable via register writes.
# ============================================================================
    .include "common.inc"
    .section .text.init
    .globl _start

_start:
    # ===== Setup operands =====
    addi  x1,  x0,  7          # x1  = 7
    addi  x2,  x0,  3          # x2  = 3
    addi  x3,  x0,  -4         # x3  = -4  (0xFFFFFFFC)
    nop
    nop

    # ===== MUL: lower 32 bits of rs1 × rs2 =====
    mul   x4,  x1,  x2         # x4  = 7*3 = 21
    nop
    nop
    nop
    nop

    mul   x5,  x1,  x3         # x5  = 7*(-4) = -28 = 0xFFFFFFE4
    nop
    nop
    nop
    nop

    # ===== MULH: upper 32 bits, signed × signed =====
    mulh  x6,  x1,  x2         # x6  = upper(7*3) = 0
    nop
    nop
    nop
    nop

    mulh  x7,  x1,  x3         # x7  = upper(7*(-4)) = -1 = 0xFFFFFFFF
    nop
    nop
    nop
    nop

    # ===== MULHSU: upper 32 bits, signed × unsigned =====
    mulhsu x8,  x3,  x1        # x8  = upper(signed(-4) × unsigned(7)) = -1
    nop
    nop
    nop
    nop

    # ===== MULHU: upper 32 bits, unsigned × unsigned =====
    mulhu x9,  x1,  x2         # x9  = upper(unsigned(7) × unsigned(3)) = 0
    nop
    nop
    nop
    nop

    # ===== DIV: signed quotient =====
    div   x10, x1,  x2         # x10 = 7 / 3 = 2
    nop
    nop
    nop
    nop

    div   x11, x3,  x1         # x11 = (-4) / 7 = 0 (truncated toward zero)
    nop
    nop
    nop
    nop

    # ===== DIVU: unsigned quotient =====
    divu  x12, x1,  x2         # x12 = 7 / 3 = 2 (unsigned)
    nop
    nop
    nop
    nop

    # ===== REM: signed remainder =====
    rem   x13, x1,  x2         # x13 = 7 % 3 = 1
    nop
    nop
    nop
    nop

    rem   x14, x3,  x1         # x14 = (-4) % 7 = -4
    nop
    nop
    nop
    nop

    # ===== REMU: unsigned remainder =====
    remu  x15, x1,  x2         # x15 = 7 % 3 = 1 (unsigned)
    nop
    nop
    nop
    nop

    DONE

    DATA_SECTION
    TOHOST_SECTION
