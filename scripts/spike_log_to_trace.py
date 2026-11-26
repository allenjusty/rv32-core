#!/usr/bin/env python3
"""Convert a Spike commit log (--log-commits -l) into the expected-trace file.

One line per retired instruction and one per trap, in program order:
    R <pc> <insn> <rd>:<value>|- <addr>:<data>:<size>|- <csr>:<value>|-
(<csr> is the CSR a CSR instruction writes, or mstatus for MRET.)
    T <mcause> <mepc> <mtval>        (mcause in decimal; interrupts have bit 31 set)
Boot-ROM instructions (PC below 0x8000_0000) are skipped. The trace ends with the
store to tohost (Spike runs a few more instructions before it notices the write).
Written against Spike commit 6e188877; the log format can change between versions.

Usage: spike_log_to_trace.py spike.log out.trace --tohost 80001000
"""
import argparse
import re
import sys

CAUSES = {
    "trap_instruction_address_misaligned": 0,
    "trap_illegal_instruction": 2,
    "trap_breakpoint": 3,
    "trap_load_address_misaligned": 4,
    "trap_store_address_misaligned": 6,
    "trap_machine_ecall": 11,
}
RAM_BASE = 0x8000_0000

commit_re = re.compile(r"^core\s+\d+: 3 0x([0-9a-f]+) \(0x([0-9a-f]+)\)(.*)$")
irq_re = re.compile(r"^core\s+\d+: exception interrupt #(\d+), epc 0x([0-9a-f]+)")
exc_re = re.compile(r"^core\s+\d+: exception (\S+), epc 0x([0-9a-f]+)")
tval_re = re.compile(r"^core\s+\d+:\s+tval 0x([0-9a-f]+)")


def parse(lines, tohost):
    out = []
    pending_trap = None
    for line in lines:
        m = tval_re.match(line)
        if m and pending_trap is not None:
            pending_trap[3] = int(m.group(1), 16) & 0xFFFFFFFF
            continue
        if pending_trap is not None:
            out.append("T %d %08x %08x" % tuple(pending_trap[1:]))
            pending_trap = None

        m = irq_re.match(line)
        if m:
            cause, epc = 0x8000_0000 | int(m.group(1)), int(m.group(2), 16)
            if int(m.group(1)) != 3:
                # only the software interrupt (CLINT msip) is predictable enough to compare
                sys.exit(f"unexpected interrupt in Spike log: {line.strip()}")
            pending_trap = ["T", cause, epc, 0]
            continue

        m = exc_re.match(line)
        if m:
            name, epc = m.group(1), int(m.group(2), 16)
            if name not in CAUSES:
                sys.exit(f"unexpected trap in Spike log: {line.strip()}")
            if epc >= RAM_BASE:
                pending_trap = ["T", CAUSES[name], epc, 0]
            continue

        m = commit_re.match(line)
        if not m:
            continue
        pc, insn, rest = int(m.group(1), 16), int(m.group(2), 16), m.group(3).split()
        if pc < RAM_BASE:
            continue
        rd = st = csr = "-"
        is_mret = insn == 0x30200073
        csr_num = 0x300 if is_mret else insn >> 20      # MRET writes mstatus
        is_csr = (insn & 0x7F) == 0x73 and ((insn >> 12) & 7) not in (0, 4) or is_mret
        is_store = (insn & 0x7F) == 0x23
        i = 0
        while i < len(rest):
            tok = rest[i]
            if re.fullmatch(r"x\d+", tok):
                rd = "%d:%08x" % (int(tok[1:]), int(rest[i + 1], 16) & 0xFFFFFFFF)
                i += 2
            elif tok == "mem":
                addr = int(rest[i + 1], 16)
                if is_store:
                    data = int(rest[i + 2], 16)
                    size = (insn >> 12) & 3
                    st = "%08x:%08x:%d" % (addr, data, size)
                    i += 3
                else:
                    i += 2
            elif re.fullmatch(r"c\d+_\w+", tok):
                num = int(tok[1:].split("_")[0])
                if is_csr and num == csr_num:
                    csr = "%03x:%08x" % (num, int(rest[i + 1], 16) & 0xFFFFFFFF)
                i += 2
            else:
                i += 1
        out.append("R %08x %08x %s %s %s" % (pc, insn, rd, st, csr))
        if is_store and tohost is not None and st != "-" and int(st.split(":")[0], 16) == tohost:
            break
    if pending_trap is not None:
        out.append("T %d %08x %08x" % tuple(pending_trap[1:]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("out")
    ap.add_argument("--tohost", help="tohost address (hex)")
    a = ap.parse_args()
    tohost = int(a.tohost, 16) if a.tohost else None
    with open(a.log, errors="replace") as f:
        recs = parse(f, tohost)
    with open(a.out, "w") as f:
        f.write("\n".join(recs) + "\n")
    print(f"{a.out}: {len(recs)} records")


if __name__ == "__main__":
    main()
