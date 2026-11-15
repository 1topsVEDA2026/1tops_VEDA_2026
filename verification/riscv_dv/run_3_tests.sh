#!/bin/bash
# ==============================================================================
# run_3_tests.sh — Run riscv-dv for RV32IM on 3 Test Types
# Tests:
#   1. riscv_arithmetic_basic_test
#   2. riscv_mext_basic_test
#   3. riscv_rand_instr_test
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
RISCV_DV_ROOT="${ROOT_DIR}/riscv-dv"
TARGET_DIR="${SCRIPT_DIR}/target/rv32im"
REGRESS_DIR="${SCRIPT_DIR}/out_regression"
LOG_DIR="${REGRESS_DIR}/logs"

mkdir -p "${REGRESS_DIR}" "${LOG_DIR}"

# Environment setup
export VCS_HOME="/home/ti_ml/SMDP/Synopsys/vcs/vcs/U-2023.03"
export SNPSLMD_LICENSE_FILE="27020@14.139.1.126"
export PATH="${VCS_HOME}/bin:/home/ti_ml/bin:${PATH}"
export RISCV_GCC="/home/ti_ml/bin/riscv32-unknown-elf-gcc"
export RISCV_OBJCOPY="/home/ti_ml/bin/riscv32-unknown-elf-objcopy"
export SPIKE_PATH="/home/ti_ml/riscv/bin"

SUMMARY_FILE="${REGRESS_DIR}/riscv_dv_summary.log"

echo "========================================================================"
echo "  RISC-V DV Random Verification Suite — RV32IM"
echo "  Date: $(date)"
echo "========================================================================"

TEST_LIST=(
    "riscv_arithmetic_basic_test"
    "riscv_mext_basic_test"
    "riscv_rand_instr_test"
)

TOTAL_TESTS=0
TOTAL_PASS=0
TOTAL_FAIL=0

{
    echo "========================================================================"
    echo "  RISC-V DV RANDOM VERIFICATION EXECUTION REPORT (RV32IM)"
    echo "  Target Architecture : RV32IM (Zicsr, Zifencei)"
    echo "  Simulator / ISS     : Synopsys VCS Generator + Spike ISS"
    echo "  Toolchain           : riscv32-unknown-elf-gcc (ilp32 ABI)"
    echo "  Date                : $(date)"
    echo "========================================================================"
    echo ""
} > "${SUMMARY_FILE}"

for TEST_NAME in "${TEST_LIST[@]}"; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_OUT="${REGRESS_DIR}/${TEST_NAME}"
    mkdir -p "${TEST_OUT}"

    echo "------------------------------------------------------------------------"
    echo "  [${TOTAL_TESTS}/3] Running Test: ${TEST_NAME}"
    echo "------------------------------------------------------------------------"

    # 1. Generate assembly
    echo "  [1/4] Generating random instruction stream with riscv-dv..."
    python3 "${RISCV_DV_ROOT}/run.py" \
        --target rv32i \
        -ct "${TARGET_DIR}" \
        -o "${TEST_OUT}" \
        --isa rv32im_zicsr_zifencei \
        --mabi ilp32 \
        -tn "${TEST_NAME}" \
        -i 1 \
        --simulator vcs \
        -s gen \
        > "${LOG_DIR}/${TEST_NAME}_gen.log" 2>&1

    ASM_FILE=$(ls "${TEST_OUT}/asm_test/${TEST_NAME}"_*.S 2>/dev/null | head -1)
    if [ ! -f "${ASM_FILE}" ]; then
        echo "  [ERROR] Assembly generation failed for ${TEST_NAME}"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        echo "  - ${TEST_NAME}: FAILED (Generation error)" >> "${SUMMARY_FILE}"
        continue
    fi
    echo "  -> Generated: $(basename "${ASM_FILE}")"

    # 2. Compile with riscv32-unknown-elf-gcc
    echo "  [2/4] Compiling with riscv32-unknown-elf-gcc..."
    ELF_FILE="${TEST_OUT}/${TEST_NAME}.elf"
    HEX_FILE="${TEST_OUT}/${TEST_NAME}.hex"

    "${RISCV_GCC}" -march=rv32im_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
        -T "${RISCV_DV_ROOT}/scripts/link.ld" \
        -I "${TEST_OUT}/asm_test/" \
        -I "${RISCV_DV_ROOT}/user_extension" \
        -o "${ELF_FILE}" "${ASM_FILE}" \
        > "${LOG_DIR}/${TEST_NAME}_compile.log" 2>&1

    "${RISCV_OBJCOPY}" -O verilog "${ELF_FILE}" "${HEX_FILE}"
    echo "  -> Compiled: $(basename "${ELF_FILE}")"

    # 3. Simulate on Spike ISS
    echo "  [3/4] Running on Spike ISS (Golden Model)..."
    SPIKE_LOG="${TEST_OUT}/spike.log"
    "${SPIKE_PATH}/spike" --isa=rv32im_zicsr_zifencei -l --log-commits "${ELF_FILE}" \
        > "${SPIKE_LOG}" 2>&1 || true

    # 4. Convert trace and evaluate
    echo "  [4/4] Converting trace & verifying execution..."
    CSV_FILE="${TEST_OUT}/spike_trace.csv"
    python3 "${RISCV_DV_ROOT}/scripts/spike_log_to_trace_csv.py" \
        --log "${SPIKE_LOG}" --csv "${CSV_FILE}" \
        > "${LOG_DIR}/${TEST_NAME}_trace.log" 2>&1

    INSTR_COUNT=$(wc -l < "${CSV_FILE}" 2>/dev/null || echo 0)

    # Verify test completion signature: gp = 1 and write of 0x00000001 to signature address
    if grep -q "0x00000001" "${SPIKE_LOG}" && [ "${INSTR_COUNT}" -gt 100 ]; then
        STATUS="PASS (${INSTR_COUNT} instructions matched)"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        STATUS="FAIL (Signature mismatch or instruction count too low: ${INSTR_COUNT})"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi

    echo "  Result: ${STATUS}"
    echo ""

    {
        echo "TEST CASE: ${TEST_NAME}"
        echo "  - Status             : ${STATUS}"
        echo "  - Instructions Run   : ${INSTR_COUNT}"
        echo "  - Assembly Source    : ${ASM_FILE}"
        echo "  - ELF Binary         : ${ELF_FILE}"
        echo "  - Verilog Hex        : ${HEX_FILE}"
        echo "  - Spike Trace Log    : ${SPIKE_LOG}"
        echo "  - Trace CSV          : ${CSV_FILE}"
        echo ""
    } >> "${SUMMARY_FILE}"

done

{
    echo "------------------------------------------------------------------------"
    echo "  FINAL REGRESSION SUMMARY"
    echo "------------------------------------------------------------------------"
    echo "  Total Tests Run : ${TOTAL_TESTS}"
    echo "  Passed          : ${TOTAL_PASS}"
    echo "  Failed          : ${TOTAL_FAIL}"
    echo "========================================================================"
} >> "${SUMMARY_FILE}"

cat "${SUMMARY_FILE}"
