#!/bin/bash
# ============================================================================
# run_riscv_dv.sh — End-to-end riscv-dv random verification for RV32IM
#
# Flow:
#   1. riscv-dv generates random assembly → .S files
#   2. gcc compiles → .elf / .hex
#   3. Spike ISS runs → spike trace CSV (golden reference)
#   4. RTL simulation runs (QuestaSim) → RTL trace CSV
#   5. Compare spike_trace.csv vs rtl_trace.csv
#
# Usage:
#   ./run_riscv_dv.sh [test_name] [iterations] [seed]
#     test_name:  riscv_arithmetic_basic_test | riscv_mext_basic_test |
#                 riscv_rand_instr_test | all (default: riscv_rand_instr_test)
#     iterations: number of test iterations (default: 1)
#     seed:       random seed (default: random)
# ============================================================================

set -e

# ---- Configuration ----
RISCV_PREFIX=${RISCV_PREFIX:-riscv32-unknown-elf-}
SPIKE=${SPIKE:-spike}
SPIKE_ISA="rv32im_zicsr_zifencei"
GCC="${RISCV_PREFIX}gcc"
OBJCOPY="${RISCV_PREFIX}objcopy"
OBJDUMP="${RISCV_PREFIX}objdump"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$(dirname "$SCRIPT_DIR")"
RISCV_DV_ROOT="/home/vlsiuser/TOPS_Verification/riscv-dv"
TARGET_DIR="$SCRIPT_DIR/target/rv32im"
OUTPUT_DIR="$SCRIPT_DIR/out"

export PATH="$HOME/riscv-tools/bin:$PATH"

# QuestaSim environment
export LM_LICENSE_FILE=1717@14.139.1.126
export MGLS_LICENSE_FILE=1717@14.139.1.126
export Questa_HOME=/home/vlsiuser/SMDP/MentorGraphics/Questa/questasim
export PATH=$Questa_HOME/bin:$PATH

# Parse args
NO_GEN=0
if [ "$1" == "--no-gen" ] || [ "$1" == "--skip-gen" ]; then
    NO_GEN=1
    shift
fi

TEST_NAME="${1:-riscv_arithmetic_basic_test}"
ITERATIONS="${2:-1}"
SEED="${3:-$RANDOM}"

echo "============================================================"
echo "  RISC-V DV Random Verification — RV32IM"
echo "============================================================"
echo "  Test:        $TEST_NAME"
echo "  Iterations:  $ITERATIONS"
echo "  Seed:        $SEED"
echo "  Skip gen:    $NO_GEN"
echo "  RTL dir:     $RTL_DIR"
echo "  riscv-dv:    $RISCV_DV_ROOT"
echo "============================================================"
echo ""

mkdir -p "$OUTPUT_DIR"

# ================================================================
# Step 1: Generate random assembly using riscv-dv
# ================================================================
if [ "$NO_GEN" -eq 0 ]; then
    echo "[1/5] Generating random assembly programs..."
    cd "$RISCV_DV_ROOT"
    python3 run.py \
        --target rv32i \
        -ct "$TARGET_DIR" \
        -o "$OUTPUT_DIR" \
        --isa rv32im \
        --mabi ilp32 \
        -tn "$TEST_NAME" \
        -i "$ITERATIONS" \
        --seed "$SEED" \
        -s gen \
        --simulator pyflow \
        -v \
        2>&1 | tee "$OUTPUT_DIR/gen.log"
else
    echo "[1/5] Skipping generation (--no-gen requested)"
fi

echo ""
echo "  Generated files:"
ls "$OUTPUT_DIR/asm_test/"*.S 2>/dev/null | head -10
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_TESTS=0

# ================================================================
# Step 2-5: For each generated test
# ================================================================
for ASM_FILE in "$OUTPUT_DIR/asm_test/"*.S; do
    [ -f "$ASM_FILE" ] || continue
    TEST_BASE=$(basename "$ASM_FILE" .S)
    WORK_DIR="$OUTPUT_DIR/tests/$TEST_BASE"
    mkdir -p "$WORK_DIR"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  TEST $TOTAL_TESTS: $TEST_BASE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # ---- Step 2: Compile with GCC ----
    echo "  [2/5] Compiling..."
    ${GCC} -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles \
        -T "$RISCV_DV_ROOT/scripts/link.ld" \
        -I "$OUTPUT_DIR/asm_test/" \
        -I "$RISCV_DV_ROOT/user_extension" \
        -o "$WORK_DIR/$TEST_BASE.elf" "$ASM_FILE" 2>"$WORK_DIR/gcc.log" || {
        echo "  [SKIP] GCC compilation failed"
        cat "$WORK_DIR/gcc.log"
        continue
    }

    # Generate hex for RTL via verilog objcopy + convert_hex.py
    ${OBJCOPY} -O verilog "$WORK_DIR/$TEST_BASE.elf" "$WORK_DIR/rtl_raw.hex"
    python3 "$SCRIPT_DIR/convert_hex.py" "$WORK_DIR/rtl_raw.hex" "$WORK_DIR/rtl_prog_word.hex"
    ${OBJDUMP} -d "$WORK_DIR/$TEST_BASE.elf" > "$WORK_DIR/disasm.txt"

    # ---- Step 3: Run Spike ISS ----
    echo "  [3/5] Running Spike..."
    ${SPIKE} --isa=$SPIKE_ISA --log-commits \
        --log="$WORK_DIR/spike.log" \
        "$WORK_DIR/$TEST_BASE.elf" 2>/dev/null || true

    SPIKE_LINES=$(wc -l < "$WORK_DIR/spike.log" 2>/dev/null || echo "0")
    echo "    Spike log: $SPIKE_LINES entries"

    # ---- Step 4: Run RTL in QuestaSim ----
    echo "  [4/5] Running RTL simulation..."
    RTL_SIM_DIR="$WORK_DIR/sim"
    mkdir -p "$RTL_SIM_DIR"
    cp "$WORK_DIR/rtl_prog_word.hex" "$RTL_SIM_DIR/"

    cd "$RTL_SIM_DIR"
    vlib work > /dev/null 2>&1 || true
    vlog -quiet +incdir+"$RTL_DIR" \
        +define+HEX_FILE=\"rtl_prog_word.hex\" \
        +define+TRACE_OUT=\"rtl_trace.log\" \
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
        "$SCRIPT_DIR/rv32im_riscv_dv_tb.sv" \
        > compile.log 2>&1

    vsim -c rv32im_riscv_dv_tb -do "run -all; quit -f" > sim.log 2>&1 || true
    cd "$SCRIPT_DIR"

    RTL_LINES=$(wc -l < "$RTL_SIM_DIR/rtl_trace.log" 2>/dev/null || echo "0")
    echo "    RTL trace: $RTL_LINES entries"

    # ---- Step 5: Compare traces ----
    echo "  [5/5] Comparing traces..."
    if [ -f "$WORK_DIR/spike.log" ] && [ -f "$RTL_SIM_DIR/rtl_trace.log" ]; then
        python3 "$RTL_DIR/spike_verify/compare_spike_rtl.py" \
            "$WORK_DIR/spike.log" \
            "$RTL_SIM_DIR/rtl_trace.log" \
            --pc-offset 0x0 \
            --spike-base 0x8000 \
            --rtl-base 0x8000 \
            --test-name "$TEST_BASE" \
            > "$WORK_DIR/compare.log" 2>&1 || true

        grep -E "ALL INSTRUCTIONS MATCH|MISMATCHES DETECTED|Match rate|Total compared" "$WORK_DIR/compare.log" || true

        if grep -q "ALL INSTRUCTIONS MATCH" "$WORK_DIR/compare.log" 2>/dev/null; then
            echo "  ✅ PASS"
            TOTAL_PASS=$((TOTAL_PASS + 1))
        else
            echo "  ❌ FAIL — see $WORK_DIR/compare.log"
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
        fi
    else
        echo "  ⚠️  Missing trace files, skipping comparison"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    echo ""
done

# ================================================================
# Summary
# ================================================================
echo ""
echo "============================================================"
echo "  RISC-V DV VERIFICATION SUMMARY"
echo "============================================================"
echo "  Total tests: $TOTAL_TESTS"
echo "  PASS:        $TOTAL_PASS"
echo "  FAIL:        $TOTAL_FAIL"
if [ $TOTAL_FAIL -eq 0 ] && [ $TOTAL_TESTS -gt 0 ]; then
    echo "  STATUS:      ✅ ALL TESTS PASSED"
else
    echo "  STATUS:      ❌ SOME TESTS FAILED"
fi
echo "============================================================"
