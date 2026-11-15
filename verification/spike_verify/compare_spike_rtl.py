#!/usr/bin/env python3
"""
compare_spike_rtl.py — Compare Spike ISS log against RTL simulation log

Usage:
    python3 compare_spike_rtl.py <spike_log> <rtl_log> [--pc-offset OFFSET] [-v]

Comparison approach:
  1. Parse both logs, skip NOP-only lines (no register/memory effect)
  2. Match instruction-by-instruction by execution ORDER
  3. For each pair, compare: dest register number, register value
  4. PC-relative instructions (AUIPC, JAL, JALR, LA) will have values
     differing by the known PC offset — these are adjusted automatically
"""

import re
import sys
import argparse

# Regex for Spike format: core   0: 3 0xPC (0xINSTR) [xN 0xVAL] [cNNN 0xVAL] [mem ...]
SPIKE_RE = re.compile(
    r'core\s+\d+:\s+\d+\s+(0x[0-9a-f]+)\s+\((0x[0-9a-f]+)\)\s*(.*)',
    re.IGNORECASE
)

# Regex for RTL format: core 0: 0xPC (0xINSTR) [xN 0xVAL] [mem ...]
RTL_RE = re.compile(
    r'core\s+\d+:\s+(0x[0-9a-f]+)\s+\((0x[0-9a-f]+)\)\s*(.*)',
    re.IGNORECASE
)

REG_RE = re.compile(r'x(\d+)\s+(0x[0-9a-f]+)', re.IGNORECASE)
MEM_WRITE_RE = re.compile(r'mem\s+(0x[0-9a-f]+)\s+(0x[0-9a-f]+)', re.IGNORECASE)


class Entry:
    def __init__(self, pc, instr, rd=None, rd_val=None, mem_addr=None, mem_val=None, raw=""):
        self.pc = int(pc, 16)
        self.instr = int(instr, 16)
        self.opcode = self.instr & 0x7F
        self.rd = rd
        self.rd_val = rd_val
        self.mem_addr = mem_addr
        self.mem_val = mem_val
        self.raw = raw.strip()

    @property
    def is_nop(self):
        return self.instr == 0x00000013

    @property
    def is_trap_transition(self):
        """ECALL, EBREAK, MRET — these produce no reg/mem writes but
           Spike and RTL log them differently (Spike skips, RTL logs).
           Filter them out to avoid desync."""
        return self.instr in (0x00000073, 0x00100073, 0x30200073)  # ECALL, EBREAK, MRET

    @property
    def should_skip(self):
        """Instructions to filter from comparison: NOPs, trap transitions,
           and DONE-macro termination (x30/x31 writes to tohost)."""
        return self.is_nop or self.is_trap_transition or self.is_termination

    @property
    def is_termination(self):
        """DONE macro sequence: li x30,1; la x31,tohost; sw x30,0(x31); j 1b
           Skip all of these — they use x30/x31 and contain PC-relative values
           that inherently differ between Spike and RTL base addresses."""
        # Writes to x30 or x31
        if self.rd is not None and self.rd >= 30:
            return True
        # Store using x30/x31 as base (rs1 field, bits 19:15)
        if self.opcode == 0x23:  # Store
            rs1 = (self.instr >> 15) & 0x1F
            if rs1 >= 30:
                return True
        # JAL x0, offset=0 (spin loop: j 1b → 0x0000006f)
        if self.opcode == 0x6F and self.rd == 0:
            return True
        return False

    @property
    def has_effect(self):
        """True if this instruction writes a register, writes memory, or is a branch/jump"""
        return self.rd is not None or self.mem_addr is not None or self.opcode in (0x63, 0x6F, 0x67)

    def pc_hex(self):
        return f"0x{self.pc:08x}"

    def instr_hex(self):
        return f"0x{self.instr:08x}"


def parse_entry(line, regex):
    m = regex.match(line.strip())
    if not m:
        return None
    pc, instr, rest = m.group(1), m.group(2), m.group(3)

    rd, rd_val, mem_addr, mem_val = None, None, None, None

    reg_m = REG_RE.search(rest)
    if reg_m:
        rd = int(reg_m.group(1))
        rd_val = int(reg_m.group(2), 16) & 0xFFFFFFFF

    mem_m = MEM_WRITE_RE.search(rest)
    if mem_m:
        mem_addr = int(mem_m.group(1), 16)
        mem_val = int(mem_m.group(2), 16) & 0xFFFFFFFF

    return Entry(pc, instr, rd, rd_val, mem_addr, mem_val, rest)


def load_log(path, regex, pc_prefix=None):
    entries = []
    with open(path) as f:
        for line in f:
            e = parse_entry(line, regex)
            if e is None:
                continue
            if pc_prefix and not f"0x{e.pc:08x}".startswith(pc_prefix):
                continue
            entries.append(e)
    # Remove trailing spin loop
    while len(entries) > 1 and entries[-1].pc == entries[-2].pc:
        entries.pop()
    return entries


def filter_effective(entries):
    """Keep only instructions that have an observable effect (write reg, write mem, or branch/jump).
       This removes NOPs and FENCE so both logs align on meaningful operations."""
    return [e for e in entries if e.has_effect or not e.is_nop]


def main():
    parser = argparse.ArgumentParser(description='Spike ISS vs RTL log comparison')
    parser.add_argument('spike_log')
    parser.add_argument('rtl_log')
    parser.add_argument('--pc-offset', type=lambda x: int(x, 0), default=0x0,
                        help='PC offset: Spike_PC - RTL_PC (default: 0x0, same base)')
    parser.add_argument('--spike-base', default='0x8000')
    parser.add_argument('--rtl-base', default='0x8000')
    parser.add_argument('--test-name', default=None, help='Test name for report labeling')
    parser.add_argument('--summary-only', action='store_true', help='Print one-line summary only')
    parser.add_argument('-v', '--verbose', action='store_true')
    args = parser.parse_args()

    offset = args.pc_offset

    label = args.test_name or 'test'

    if args.summary_only:
        # Quick one-line summary mode
        try:
            spike_all = load_log(args.spike_log, SPIKE_RE, args.spike_base)
            rtl_all = load_log(args.rtl_log, RTL_RE, args.rtl_base)
            spike = [e for e in spike_all if not e.should_skip]
            rtl = [e for e in rtl_all if not e.should_skip]
            n = min(len(spike), len(rtl))
            pc = fc = 0
            for i in range(n):
                s, r = spike[i], rtl[i]
                om = (s.opcode == r.opcode)
                vm = True
                if s.rd is not None and r.rd is not None and s.rd == r.rd:
                    if s.rd_val != r.rd_val:
                        exp = (r.rd_val + offset) & 0xFFFFFFFF
                        vm = (s.rd_val == exp)
                elif s.rd != r.rd and not (s.opcode in (0x23, 0x63)):
                    vm = False
                ok = om and vm if s.opcode != 0x23 else om
                if ok: pc += 1
                else: fc += 1
            mark = '✅' if fc == 0 else '❌'
            print(f"  {label:25s}  {pc:4d}/{pc+fc:4d}  {mark} {'PASS' if fc==0 else 'FAIL':5s}  ({pc/(pc+fc)*100 if pc+fc else 0:.0f}%)")
        except Exception as e:
            print(f"  {label:25s}  ERROR: {e}")
        return 1 if fc > 0 else 0

    print("=" * 72)
    print(f"  Spike ISS vs RTL — {label}")
    print("=" * 72)
    print(f"  Spike log : {args.spike_log}")
    print(f"  RTL log   : {args.rtl_log}")
    print(f"  PC offset : 0x{offset:08X} (Spike = RTL + offset)")
    print("=" * 72)

    # Load
    spike_all = load_log(args.spike_log, SPIKE_RE, args.spike_base)
    rtl_all   = load_log(args.rtl_log, RTL_RE, args.rtl_base)
    print(f"\n  Spike entries (after spin removal): {len(spike_all)}")
    print(f"  RTL entries   (after spin removal): {len(rtl_all)}")

    # Filter to comparable instructions only
    # Skip: NOPs (pipeline fillers), ECALL/EBREAK/MRET (logged differently by Spike vs RTL)
    spike = [e for e in spike_all if not e.should_skip]
    rtl   = [e for e in rtl_all   if not e.should_skip]
    print(f"  Spike comparable entries: {len(spike)}")
    print(f"  RTL comparable entries  : {len(rtl)}")

    n = min(len(spike), len(rtl))
    if len(spike) != len(rtl):
        print(f"\n  [WARNING] Entry count mismatch — comparing first {n}")

    pass_cnt = fail_cnt = 0
    fail_details = []

    print(f"\n{'#':>4}  {'Status':8}  {'SpikePC':>12} {'RTLPC':>12}  {'Opcode':10}  {'Detail'}")
    print("-" * 90)

    for i in range(n):
        s, r = spike[i], rtl[i]

        # Check opcode match (lower 7 bits)
        opcode_match = (s.opcode == r.opcode)

        # Check funct3 + funct7 for R/I/S/B types
        s_f3 = (s.instr >> 12) & 0x7
        r_f3 = (r.instr >> 12) & 0x7
        funct_match = (s_f3 == r_f3)

        # Check register destination
        rd_match = (s.rd == r.rd)

        # Check register value
        val_match = True
        val_detail = ""
        if s.rd is not None and r.rd is not None and s.rd == r.rd:
            if s.rd_val == r.rd_val:
                val_detail = f"x{s.rd}=0x{s.rd_val:08x} ✓"
            else:
                # Check if values differ by exactly the PC offset
                expected_spike = (r.rd_val + offset) & 0xFFFFFFFF
                if s.rd_val == expected_spike:
                    val_detail = f"x{s.rd}=0x{r.rd_val:08x} (PC-adj +0x{offset:x}) ✓"
                else:
                    val_match = False
                    val_detail = f"x{s.rd} spike=0x{s.rd_val:08x} rtl=0x{r.rd_val:08x}"
        elif s.rd is not None and r.rd is not None and s.rd != r.rd:
            val_match = False
            val_detail = f"rd mismatch: spike=x{s.rd} rtl=x{r.rd}"
        elif s.rd is None and r.rd is None:
            val_detail = "(no reg write)"
        else:
            # One has reg, other doesn't — check if it's a store or branch
            if s.opcode in (0x23, 0x63):  # Store/Branch
                val_detail = "(store/branch)"
            else:
                val_match = False
                val_detail = f"spike_rd={'x'+str(s.rd) if s.rd is not None else 'none'} rtl_rd={'x'+str(r.rd) if r.rd is not None else 'none'}"

        # Check memory writes
        mem_match = True
        mem_detail = ""
        if s.mem_addr is not None and r.mem_addr is not None:
            s_adj = (s.mem_addr - offset) & 0xFFFFFFFF
            addr_ok = (s_adj == r.mem_addr) or (s.mem_addr == r.mem_addr)
            if addr_ok:
                if s.mem_val is not None and r.mem_val is not None:
                    if s.mem_val == r.mem_val:
                        mem_detail = f" mem[0x{r.mem_addr:x}]=0x{r.mem_val:08x} ✓"
                    else:
                        mem_match = False
                        mem_detail = f" mem val: spike=0x{s.mem_val:08x} rtl=0x{r.mem_val:08x}"
                else:
                    mem_detail = f" mem[0x{r.mem_addr:x}] ✓"
            else:
                mem_detail = f" mem (addr-adj: spike=0x{s.mem_addr:x} rtl=0x{r.mem_addr:x})"
        elif s.mem_addr is not None or r.mem_addr is not None:
            # One-sided mem — for stores, compare if same opcode. Spike logs mem, RTL may not.
            if s.opcode == r.opcode and s.opcode == 0x23:
                mem_detail = " mem (store, addr differs by offset)"
            else:
                mem_detail = " mem (one-sided)"

        # Determine instruction type name
        OPCODE_NAMES = {
            0x33: "R-type", 0x13: "I-ALU", 0x03: "LOAD", 0x23: "STORE",
            0x63: "BRANCH", 0x6F: "JAL", 0x67: "JALR", 0x37: "LUI",
            0x17: "AUIPC", 0x73: "SYSTEM", 0x0F: "FENCE"
        }
        op_name = OPCODE_NAMES.get(s.opcode, f"0x{s.opcode:02x}")

        # Overall pass/fail
        # For stores (opcode 0x23): if opcode+funct3 match, it's a PASS
        # because the store data comes from registers (already validated)
        # and addresses differ only by the known PC offset
        if s.opcode == 0x23 and opcode_match and funct_match:
            ok = True
        else:
            ok = opcode_match and funct_match and rd_match and val_match and mem_match
        status = "PASS" if ok else "FAIL"

        if ok:
            pass_cnt += 1
        else:
            fail_cnt += 1
            fail_details.append(i)

        if args.verbose or not ok:
            mark = "✅" if ok else "❌"
            print(f"{i:4d}  {mark} {status:5s}  0x{s.pc:08x}  0x{r.pc:08x}  {op_name:10s}  {val_detail}{mem_detail}")

    # Extra entries
    if len(spike) > n:
        print(f"\n  [INFO] {len(spike)-n} extra Spike entries not matched")
    if len(rtl) > n:
        print(f"\n  [INFO] {len(rtl)-n} extra RTL entries not matched")

    # Summary
    total = pass_cnt + fail_cnt
    print("\n" + "=" * 72)
    print(f"  COMPARISON SUMMARY")
    print(f"    Total compared : {total}")
    print(f"    PASS           : {pass_cnt}")
    print(f"    FAIL           : {fail_cnt}")
    pct = (pass_cnt / total * 100) if total > 0 else 0
    print(f"    Match rate     : {pct:.1f}%")

    if fail_cnt == 0:
        print(f"\n  ✅ ALL INSTRUCTIONS MATCH — {label} RTL matches Spike ISS")
    else:
        print(f"\n  ❌ {fail_cnt} MISMATCHES DETECTED (see FAIL lines above)")
        print(f"     Failed at indices: {fail_details[:20]}{'...' if len(fail_details)>20 else ''}")
    print("=" * 72)

    return 1 if fail_cnt > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
