#!/usr/bin/env python3
"""Compare the RTL trace with the expected (Spike) trace, record by record.

Masked (see spec section 8): the rd value of reads of mcycle(h), minstret(h), mip and
marchid, and the new value written to a counter or mip (it depends on the old value,
which differs: Spike's timer sets mip.MTIP by itself). Stops at the first mismatch and prints the records around it.

Usage: compare_trace.py expected.trace rtl.trace
"""
import sys

MASKED_CSRS = {0xB00, 0xB80, 0xB02, 0xB82, 0x344, 0xF12}   # rd value of a read is masked
VALUE_MASKED = {0xB00, 0xB80, 0xB02, 0xB82, 0x344}        # the new CSR value is masked too


def masked(rec):
    f = rec.split()
    if f[0] != "R":
        return rec
    insn = int(f[2], 16)
    if (insn & 0x7F) == 0x73 and ((insn >> 12) & 7) not in (0, 4) and (insn >> 20) in MASKED_CSRS:
        if f[3] != "-":
            f[3] = f[3].split(":")[0] + ":(masked)"
        if (insn >> 20) in VALUE_MASKED and len(f) > 5 and f[5] != "-":
            f[5] = f[5].split(":")[0] + ":(masked)"
    return " ".join(f)


def main():
    exp = [l.strip() for l in open(sys.argv[1]) if l.strip()]
    got = [l.strip() for l in open(sys.argv[2]) if l.strip()]
    for i, (e, g) in enumerate(zip(exp, got)):
        if masked(e) != masked(g):
            print(f"MISMATCH at record {i}:")
            print(f"  expected (Spike): {e}")
            print(f"  got      (RTL)  : {g}")
            print("Previous records:")
            for j in range(max(0, i - 8), i):
                print(f"  {exp[j]}")
            sys.exit(1)
    if len(got) < len(exp):
        print(f"MISMATCH: RTL trace ended after {len(got)} records, Spike has {len(exp)}")
        print(f"  next expected: {exp[len(got)]}")
        sys.exit(1)
    if len(got) > len(exp):
        print(f"MISMATCH: RTL trace has {len(got) - len(exp)} extra records; first: {got[len(exp)]}")
        sys.exit(1)
    print(f"COMPARE PASSED: {len(exp)} records match")


if __name__ == "__main__":
    main()
