# ============================================================================
# common.inc — Shared macros for all Spike comparison test programs
# ============================================================================

# Termination: write 1 to tohost, then spin forever
.macro DONE
    li    x30, 1
    la    x31, tohost
    sw    x30, 0(x31)
1:  j     1b
.endm

# Data section template
.macro DATA_SECTION
    .section .data
    .align 4
    .globl data_area
data_area:
    .space 256
.endm

# HTIF tohost/fromhost section (required for Spike)
.macro TOHOST_SECTION
    .section .tohost, "aw", @progbits
    .globl tohost
    .align 4
tohost:
    .word 0
    .globl fromhost
    .align 4
fromhost:
    .word 0
.endm
