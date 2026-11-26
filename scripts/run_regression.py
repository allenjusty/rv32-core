#!/usr/bin/env python3
"""Run the core regression on the UVM bench, in parallel.

Every program in build/sw/ (directed tests from `make sw`, riscv-dv programs from
scripts/gen_riscv_dv.py, CoreMark) runs under each Spike-compare UVM test with several
random seeds. The test picks the memory timing; the seed picks the random wait states.
The random-interrupt programs in build/sw_irq/ (`make sw_irq`) run under core_irq_test.

Usage:
    scripts/run_regression.py                 # full: every program x every test x seeds
    scripts/run_regression.py --quick         # every program once per test, fixed seed 1
    scripts/run_regression.py --seeds 5
    scripts/run_regression.py --prog alu --test core_heavy_wait_test --seeds 20

Needs `make tb` first. Writes build/regression/summary.txt and a merged coverage report.
"""
import argparse
import os
import random
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SIM = ROOT / "build" / "uvm" / "sim"
SW = ROOT / "build" / "sw"
SW_IRQ = ROOT / "build" / "sw_irq"    # self-checking random-interrupt programs (no Spike trace)
IRQ_TEST, IRQ_SEEDS = "core_irq_test", 12
OUT = ROOT / "build" / "regression"

# test -> seeds per program in a full regression
TESTS = {
    "core_base_test": 1,          # zero wait states: one seed is enough (deterministic)
    "core_rand_wait_test": 3,
    "core_heavy_wait_test": 2,
}


def programs(only=None):
    progs = sorted(p.stem for p in SW.glob("*.trace") if (SW / f"{p.stem}.hex").exists())
    if only:
        progs = [p for p in progs if p == only or p.startswith(only)]
    return progs


def run_one(prog, test, seed, extra):
    d = OUT / "runs" / f"{prog}__{test}__{seed}"
    d.mkdir(parents=True, exist_ok=True)
    src = SW_IRQ if test == IRQ_TEST else SW
    tohost = (src / f"{prog}.tohost").read_text().strip()
    cmd = [str(SIM), f"+UVM_TESTNAME={test}", f"+verilator+seed+{seed}", "+UVM_VERBOSITY=UVM_LOW",
           f"+HEX={src / (prog + '.hex')}", f"+TOHOST={tohost}"] + extra
    if test != IRQ_TEST:
        cmd.append(f"+EXP={SW / (prog + '.trace')}")
    with open(d / "sim.log", "w") as log:
        try:
            rc = subprocess.run(cmd, cwd=d, stdout=log, stderr=subprocess.STDOUT, timeout=900).returncode
        except subprocess.TimeoutExpired:
            rc = -1
    text = (d / "sim.log").read_text(errors="replace")
    passed = rc == 0 and "TEST PASSED" in text
    first_err = ""
    if not passed:
        for line in text.splitlines():
            if ("UVM_ERROR" in line or "UVM_FATAL" in line) and "@" in line or "Assertion failed" in line:
                first_err = line.strip()[:160]
                break
        if not first_err:
            first_err = f"exit code {rc}, no PASS line"
    rerun = f"cd {d} && {' '.join(cmd)}"
    return prog, test, seed, passed, first_err, rerun, d / "coverage.dat"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="every program once per test, seed 1")
    ap.add_argument("--seeds", type=int, help="seeds per program and test (overrides the table)")
    ap.add_argument("--test", help="run only this UVM test")
    ap.add_argument("--prog", help="run only programs whose name starts with this")
    ap.add_argument("-j", type=int, default=min(6, max(1, (os.cpu_count() or 2) - 2)),
                    help="parallel simulations (each needs a few hundred MB; the dev machine has 8 GB)")
    args, extra = ap.parse_known_args()

    if not SIM.exists():
        sys.exit("build/uvm/sim not found: run 'make tb' first")
    progs = programs(args.prog)
    if not progs and not list(SW_IRQ.glob("*.hex")):
        sys.exit("no programs in build/sw: run 'make sw' (and scripts/gen_riscv_dv.py)")

    tests = {} if args.test == IRQ_TEST else ({args.test: TESTS.get(args.test, 1)} if args.test else dict(TESTS))
    jobs = []
    for t, n in tests.items():
        n = 1 if args.quick else (args.seeds or n)
        for p in progs:
            if p == "coremark" and t == "core_heavy_wait_test":
                continue   # 5.8M instructions with long waits takes too long; covered by the other two
            seeds = [1] if args.quick else random.sample(range(1, 1_000_000), n)
            jobs += [(p, t, s) for s in seeds]

    # random-interrupt programs
    if not args.test or args.test == IRQ_TEST:
        irq_progs = sorted(p.stem for p in SW_IRQ.glob("*.hex"))
        if args.prog:
            irq_progs = [p for p in irq_progs if p.startswith(args.prog)]
        n = 1 if args.quick else (args.seeds or IRQ_SEEDS)
        for p in irq_progs:
            seeds = [1, 2] if args.quick else random.sample(range(1, 1_000_000), n)
            jobs += [(p, IRQ_TEST, s) for s in seeds]
        progs = progs + irq_progs

    print(f"Running {len(jobs)} simulations ({len(progs)} programs) with {args.j} jobs...")
    with ThreadPoolExecutor(max_workers=args.j) as ex:
        results = list(ex.map(lambda j: run_one(*j, extra), jobs))

    OUT.mkdir(parents=True, exist_ok=True)
    lines = [f"{'program':34} {'test':22} {'seed':>7}  result"]
    fails = [r for r in results if not r[3]]
    for p, t, s, ok, err, _, _ in sorted(results):
        lines.append(f"{p:34} {t:22} {s:>7}  {'PASS' if ok else 'FAIL  ' + err}")
    lines.append("")
    lines.append(f"{len(results) - len(fails)}/{len(results)} passed")
    if fails:
        lines.append("\nRerun failures with:")
        lines += [f"  {r[5]}" for r in fails]
    summary = "\n".join(lines)
    (OUT / "summary.txt").write_text(summary + "\n")
    print(summary if len(results) <= 80 or fails else "\n".join(lines[-3:]))

    dats = [str(r[6]) for r in results if r[6].exists()]
    if dats:
        merged = OUT / "coverage.dat"
        subprocess.run(["verilator_coverage", "--write", str(merged)] + dats, check=False)
        rep = subprocess.run([sys.executable, str(ROOT / "scripts" / "cov_report.py"), str(merged)],
                             capture_output=True, text=True)
        print(rep.stdout)
        (OUT / "coverage_summary.txt").write_text(rep.stdout)

    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
