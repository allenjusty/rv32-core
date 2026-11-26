#!/usr/bin/env python3
"""Summarize functional coverage from a (merged) Verilator coverage.dat.

Usage: scripts/cov_report.py build/regression/coverage.dat [--holes]

Each line of coverage.dat is  C '<key\\x01...\\x02value...>' <count>.
The 'h' field holds the full name, e.g.
  dma_env_pkg::dma_coverage::cg_burst.cp_beats.one          (covergroup bin)
  tb_top.dut.u_sva.c_slverr                                   (cover property)
"""
import re
import sys
from collections import OrderedDict

LINE = re.compile(r"^C '(.*)' (\d+)$")


def fields(key):
    out = {}
    for part in key.split("\x01"):
        if "\x02" in part:
            k, v = part.split("\x02", 1)
            out[k] = v
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    show_holes = "--holes" in sys.argv
    groups = OrderedDict()   # covergroup -> {item -> [(bin, count)]}
    covers = []              # (name, count)
    for line in open(sys.argv[1], encoding="latin-1"):
        m = LINE.match(line.rstrip("\n"))
        if not m:
            continue
        f, count = fields(m.group(1)), int(m.group(2))
        name = f.get("h", "")
        if f.get("t") == "covergroup":
            cg_full, item, bin_name = name.rsplit(".", 2) if name.count(".") >= 2 else (name, "?", "?")
            cg = cg_full.split("::")[-1]
            groups.setdefault(cg, OrderedDict()).setdefault(item, []).append((bin_name, count))
        elif f.get("page", "").startswith("v_user"):
            covers.append((name.split(".")[-1], count))

    total_bins = total_hit = 0
    print(f"{'covergroup':18} {'bins hit':>10} {'coverage':>9}")
    holes = []
    for cg, items in groups.items():
        n = sum(len(b) for b in items.values())
        h = sum(1 for b in items.values() for _, c in b if c > 0)
        total_bins += n
        total_hit += h
        print(f"{cg:18} {h:>4} / {n:<4} {100.0 * h / n:8.1f}%")
        for item, bins in items.items():
            holes += [f"{cg}.{item}.{b}" for b, c in bins if c == 0]
    print(f"{'TOTAL':18} {total_hit:>4} / {total_bins:<4} {100.0 * total_hit / max(total_bins, 1):8.1f}%")
    if covers:
        print("\ncover properties:")
        for name, c in covers:
            print(f"  {name:20} {c:>8}")
    if holes:
        print(f"\n{len(holes)} coverage holes" + (":" if show_holes else " (use --holes to list)"))
        if show_holes:
            for h in holes:
                print("  " + h)


if __name__ == "__main__":
    main()
