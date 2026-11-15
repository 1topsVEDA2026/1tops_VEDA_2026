# ============================================================================
# test_mext_corner.S — M-Extension Corner Cases (Spike vs RTL Comparison)
#
# RISC-V spec-mandated edge cases:
#   - Division by zero (DIV/DIVU/REM/REMU)
#   - Signed overflow: INT32_MIN / -1
#   - Large unsigned multiplications
# ============================================================================
    .include "common.inc"
    .section .text.init
    .globl _start

_start:
    # ===== Setup corner-case operands =====
    lui   x1,  0x80000          # x1  = INT32_MIN = 0x80000000
    addi  x2,  x0,  -1         # x2  = -1 = 0xFFFFFFFF
    addi  x3,  x0,  0          # x3  = 0
    nop
    nop

    # ===== DIV by zero: result = -1 (all ones) per RISC-V spec =====
    div   x4,  x1,  x3         # x4  = INT32_MIN / 0 = 0xFFFFFFFF
    nop
    nop
    nop
    nop

    # ===== DIVU by zero: result = 0xFFFFFFFF per RISC-V spec =====
    divu  x5,  x1,  x3         # x5  = unsigned(INT32_MIN) / 0 = 0xFFFFFFFF
    nop
    nop
    nop
    nop

    # ===== REM by zero: result = dividend per RISC-V spec =====
    rem   x6,  x1,  x3         # x6  = INT32_MIN % 0 = 0x80000000
    nop
    nop
    nop
    nop

    # ===== REMU by zero: result = dividend per RISC-V spec =====
    remu  x7,  x1,  x3         # x7  = unsigned(INT32_MIN) % 0 = 0x80000000
    nop
    nop
    nop
    nop

    # ===== Signed overflow: INT32_MIN / -1 = INT32_MIN =====
    div   x8,  x1,  x2         # x8  = 0x80000000 / (-1) = 0x80000000
    nop
    nop
    nop
    nop

    # ===== Signed overflow: INT32_MIN % -1 = 0 =====
    rem   x9,  x1,  x2         # x9  = 0x80000000 % (-1) = 0
    nop
    nop
    nop
    nop

    # ===== Large multiply: (-1) * (-1) lower 32 = 1 =====
    mul   x10, x2,  x2         # x10 = lower32(0xFFFFFFFF * 0xFFFFFFFF) = 1
    nop
    nop
    nop
    nop

    # ===== Large multiply: MULHU 0xFFFFFFFF * 0xFFFFFFFF upper = 0xFFFFFFFE =====
    mulhu x11, x2,  x2         # x11 = upper32(unsigned) = 0xFFFFFFFE
    nop
    nop
    nop
    nop

    # ===== MULH: (-1) * (-1) signed upper = 0 =====
    mulh  x12, x2,  x2         # x12 = upper32(signed(-1)*signed(-1)) = 0
    nop
    nop
    nop
    nop

    DONE

    DATA_SECTION
    TOHOST_SECTION
