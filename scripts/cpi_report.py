#!/usr/bin/env python3
"""Make perf/results.md from the two CoreMark runs (BHT off, BHT on).

Usage: cpi_report.py coremark_bht0.log coremark_bht1.log
"""
import re
import sys


def parse(path):
    text = open(path).read()
    m = re.search(r"CPI bht=(\d+) cycles=(\d+) retired=(\d+) cpi=([\d.]+) branches=(\d+) "
                  r"mispredicts=(\d+) jal=(\d+) jalr=(\d+)", text)
    t = re.search(r"Timed region: (\d+) cycles, (\d+) instructions, CPI ([\d.]+)", text)
    if not m or not t:
        sys.exit(f"{path}: result lines missing")
    return {
        "bht": int(m[1]), "cycles": int(m[2]), "retired": int(m[3]), "cpi_all": float(m[4]),
        "branches": int(m[5]), "mispredicts": int(m[6]), "jal": int(m[7]), "jalr": int(m[8]),
        "t_cycles": int(t[1]), "t_instr": int(t[2]), "cpi": float(t[3]),
        # CoreMark's own checks: the CRCs must match (it prints "ERROR! ... crc" otherwise).
        # The only error allowed is its "run at least 10 seconds" rule, which is about a
        # valid published *score*; this is a CPI measurement in simulation.
        "valid": "seedcrc          : 0xe9f5" in text and not [
            l for l in text.splitlines() if l.startswith("ERROR!") and "at least 10 secs" not in l],
    }


def main():
    off, on = parse(sys.argv[1]), parse(sys.argv[2])
    gain = (off["cpi"] - on["cpi"]) / off["cpi"] * 100
    rows = [
        ("CPI, timed region (mcycle / minstret)", f"{off['cpi']:.3f}", f"{on['cpi']:.3f}"),
        ("Cycles, timed region", f"{off['t_cycles']:,}", f"{on['t_cycles']:,}"),
        ("Instructions, timed region", f"{off['t_instr']:,}", f"{on['t_instr']:,}"),
        ("Conditional branches (whole run)", f"{off['branches']:,}", f"{on['branches']:,}"),
        ("Branch mispredicts (whole run)", f"{off['mispredicts']:,}", f"{on['mispredicts']:,}"),
        ("Mispredict rate", f"{100 * off['mispredicts'] / off['branches']:.1f}%",
         f"{100 * on['mispredicts'] / on['branches']:.1f}%"),
        ("JAL / JALR (whole run)", f"{off['jal']:,} / {off['jalr']:,}", f"{on['jal']:,} / {on['jalr']:,}"),
        ("CoreMark CRC self-check", "passed" if off["valid"] else "FAILED", "passed" if on["valid"] else "FAILED"),
    ]
    print("# CPI result: BHT off vs on\n")
    print("CoreMark (PERFORMANCE_RUN, same binary for both), zero memory wait states, "
          "plain SystemVerilog harness on Verilator. "
          "This is a CPI measurement, not an official CoreMark score (CoreMark's 10-second rule "
          "for a valid score is not met in simulation; its CRC self-checks pass).\n")
    print("| | BHT off (predict not taken) | BHT on (64 x 2-bit) |")
    print("|---|---|---|")
    for r in rows:
        print(f"| {r[0]} | {r[1]} | {r[2]} |")
    print(f"\n**CPI improves by {gain:.1f}%** with the BHT.\n")
    print("Why the gain is modest: a correctly predicted taken branch still costs 1 bubble with the BHT,")
    print("because the target is only known in ID (no branch target buffer). Without the BHT a taken")
    print("branch costs 2 bubbles. A wrongly predicted branch costs 2 bubbles either way. A BTB read")
    print("in IF would remove the last bubble.")


if __name__ == "__main__":
    main()
