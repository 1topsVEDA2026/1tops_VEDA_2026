#!/bin/bash
# ============================================================================
# run_spike_verify.sh — End-to-end Spike vs RTL comparison for RV32IM
#
# Usage:  ./run_spike_verify.sh [test_name]
#   test_name: test_mext_basic | test_mext_corner | all (default: all)
#
# Prerequisites:
#   - riscv32-unknown-elf-* toolchain in PATH
#   - spike in PATH
#   - QuestaSim (vlog/vsim) in PATH
# ============================================================================

set -e

# ---- Configuration ----
RISCV_PREFIX=${RISCV_PREFIX:-riscv32-unknown-elf-}
SPIKE=${SPIKE:-spike}
SPIKE_ISA="rv32im_zicsr_zifencei"
AS="${RISCV_PREFIX}as"
LD="${RISCV_PREFIX}ld"
OBJCOPY="${RISCV_PREFIX}objcopy"
OBJDUMP="${RISCV_PREFIX}objdump"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$SCRIPT_DIR/tests"
BUILD_DIR="$SCRIPT_DIR/build"

# All available tests
ALL_TESTS="test_mext_basic test_mext_corner"

# Parse arguments
if [ "$1" == "" ] || [ "$1" == "all" ]; then
    TESTS="$ALL_TESTS"
else
    TESTS="$1"
fi

export PATH="$HOME/riscv-tools/bin:$PATH"

# QuestaSim environment
export LM_LICENSE_FILE=1717@14.139.1.126
export MGLS_LICENSE_FILE=1717@14.139.1.126
export Questa_HOME=/home/vlsiuser/SMDP/MentorGraphics/Questa/questasim
export PATH=$Questa_HOME/bin:$PATH

echo "============================================================"
echo "  Spike vs RTL Verification — RV32IM (AXI4 + Booth MDU)"
echo "============================================================"
echo "  RTL dir:  $RTL_DIR"
echo "  Tests:    $TESTS"
echo "  ISA:      $SPIKE_ISA"
echo "============================================================"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0

for TEST in $TESTS; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  TEST: $TEST"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    BDIR="$BUILD_DIR/$TEST"
    mkdir -p "$BDIR/sim"

    # ---- Step 1: Assemble for Spike (base 0x80000000) ----
    echo "[1/5] Assembling for Spike..."
    ${AS} -march=$SPIKE_ISA -mabi=ilp32 -I "$TEST_DIR" \
        -o "$BDIR/spike.o" "$TEST_DIR/${TEST}.S"
    ${LD} -T "$SCRIPT_DIR/link_spike.ld" -o "$BDIR/spike.elf" "$BDIR/spike.o"
    ${OBJDUMP} -d "$BDIR/spike.elf" > "$BDIR/disasm_spike.txt"
    echo "  → $BDIR/spike.elf"

    # ---- Step 2: Assemble for RTL (base 0x00000000) ----
    echo "[2/5] Assembling for RTL..."
    ${AS} -march=$SPIKE_ISA -mabi=ilp32 -I "$TEST_DIR" \
        -o "$BDIR/rtl.o" "$TEST_DIR/${TEST}.S"
    ${LD} -T "$SCRIPT_DIR/link_rtl.ld" -o "$BDIR/rtl.elf" "$BDIR/rtl.o"
    ${OBJCOPY} -O binary "$BDIR/rtl.elf" "$BDIR/rtl_raw.bin"
    ${OBJDUMP} -d "$BDIR/rtl.elf" > "$BDIR/disasm_rtl.txt"

    # Convert binary to word-hex format for $readmemh
    python3 -c "
import struct
data = open('$BDIR/rtl_raw.bin','rb').read()
pad = (4 - len(data) % 4) % 4
data += b'\x13\x00\x00\x00' * (pad // 4 + (1 if pad % 4 else 0))
words = struct.unpack('<{}I'.format(len(data)//4), data[:len(data)//4*4])
with open('$BDIR/rtl_prog_word.hex','w') as f:
    for i, w in enumerate(words):
        f.write('@{:08X}\n{:08X}\n'.format(i, w))
print('  → {} words written'.format(len(words)))
"
    cp "$BDIR/rtl_prog_word.hex" "$BDIR/sim/"

    # ---- Step 3: Run Spike ----
    echo "[3/5] Running Spike ISS..."
    ${SPIKE} --isa=$SPIKE_ISA --log-commits \
        --log="$BDIR/spike_full.log" \
        "$BDIR/spike.elf" 2>/dev/null || true

    # Extract golden log (user program instructions only)
    grep "^core.*0x8000[01]" "$BDIR/spike_full.log" | \
        awk '{if ($4 != prev) print; prev=$4}' \
        > "$BDIR/spike_golden.log"
    SPIKE_COUNT=$(wc -l < "$BDIR/spike_golden.log")
    echo "  → $SPIKE_COUNT unique instructions in spike_golden.log"

    # ---- Step 4: Run RTL in QuestaSim ----
    echo "[4/5] Running RTL simulation..."
    cd "$BDIR/sim"
    vlog -quiet +incdir+"$RTL_DIR" \
        "$RTL_DIR/rv32_pkg.sv" \
        "$RTL_DIR/booth_multiplier_radix4.sv" \
        "$RTL_DIR/mdu.sv" \
        "$RTL_DIR/alu.sv" \
        "$RTL_DIR/branch_cmp.sv" \
        "$RTL_DIR/controller.sv" \
        "$RTL_DIR/csr_regfile.sv" \
        "$RTL_DIR/decoder.sv" \
        "$RTL_DIR/hazard_unit.sv" \
        "$RTL_DIR/imm_gen.sv" \
        "$RTL_DIR/pipe_de_mw.sv" \
        "$RTL_DIR/pipe_if_de.sv" \
        "$RTL_DIR/register_file.sv" \
        "$RTL_DIR/rv32_core_top.sv" \
        "$RTL_DIR/axi4_imem_slave.sv" \
        "$RTL_DIR/axi4_dmem_slave.sv" \
        "$SCRIPT_DIR/rv32im_spike_compare_tb.sv" \
        > compile.log 2>&1

    vsim -c rv32im_spike_compare_tb -do "run -all; quit -f" > sim.log 2>&1 || true
    cd "$SCRIPT_DIR"

    RTL_COUNT=$(wc -l < "$BDIR/sim/rtl_spike_exec.log" 2>/dev/null || echo "0")
    echo "  → $RTL_COUNT entries in rtl_spike_exec.log"

    # ---- Step 5: Compare ----
    echo "[5/5] Comparing Spike vs RTL..."
    python3 compare_spike_rtl.py \
        "$BDIR/spike_golden.log" \
        "$BDIR/sim/rtl_spike_exec.log" \
        --pc-offset 0x80000000 \
        --spike-base 0x8000 \
        --rtl-base 0x0000 \
        --test-name "$TEST" -v 2>&1 | tee "$BDIR/compare_result.txt"

    # Count pass/fail
    if grep -q "ALL INSTRUCTIONS MATCH" "$BDIR/compare_result.txt" 2>/dev/null; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    echo ""
done

# ---- Summary ----
echo ""
echo "============================================================"
echo "  SPIKE VERIFICATION SUMMARY"
echo "============================================================"
echo "  PASS: $TOTAL_PASS"
echo "  FAIL: $TOTAL_FAIL"
if [ $TOTAL_FAIL -eq 0 ]; then
    echo "  STATUS: ✅ ALL TESTS MATCH"
else
    echo "  STATUS: ❌ SOME TESTS FAILED"
fi
echo "============================================================"
