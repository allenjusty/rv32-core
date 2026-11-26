#!/usr/bin/env python3
"""Generate riscv-dv random programs and their Spike traces into build/sw/.

For each riscv-dv test (sw/riscv-dv/rv32im/testlist.yaml) and seed:
  1. riscv-dv PyFlow generates an assembly program (with sw/riscv-dv/pyflow_fixes.patch
     applied; killed after --gen-timeout seconds just in case)
  2. GCC compiles it with riscv-dv's linker script
  3. Spike runs it; the log becomes the expected trace
Output: build/sw/dv_<test>_<seed>.{elf,hex,tohost,trace}, picked up by run_regression.py.

Usage:
    scripts/gen_riscv_dv.py                        # every test, 2 seeds each
    scripts/gen_riscv_dv.py --seeds 5 --test riscv_rand_instr_test -j 4
    scripts/gen_riscv_dv.py --retrace                # new Spike traces for existing programs

Environment: RISCV_DV (riscv-dv checkout), DV_PYTHON (python with riscv-dv's
requirements; default ~/tools/dvenv/bin/python3), and spike / riscv-none-elf-* on PATH.
"""
import argparse
import os
import random
import re
import signal
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "sw" / "riscv-dv" / "rv32im"
SW = ROOT / "build" / "sw"
DV_OUT = ROOT / "build" / "dv"
RISCV_DV = Path(os.environ.get("RISCV_DV", Path.home() / "tools" / "riscv-dv"))
DV_PYTHON = Path(os.environ.get("DV_PYTHON", Path.home() / "tools" / "dvenv" / "bin" / "python3"))
PREFIX = os.environ.get("PREFIX", "riscv-none-elf-")
SPIKE_FLAGS = ["--isa=rv32im_zicsr", "--priv=m", "--wfi-as-nop", "-m0x80000000:0x100000", "--log-commits", "-l"]


def tests_in_list():
    return re.findall(r"^- test:\s*(\S+)", (TARGET / "testlist.yaml").read_text(), re.M)


def run(cmd, timeout, **kw):
    """Run in its own process group so a hung generator and its children can be killed."""
    p = subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, **kw)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        return -1, "timeout"


def spike_trace(name):
    """Run Spike on build/sw/<name>.elf and write build/sw/<name>.trace."""
    elf = SW / f"{name}.elf"
    tohost = (SW / f"{name}.tohost").read_text().strip()
    slog = SW / f"{name}.spike.log"
    rc, log = run(["spike"] + SPIKE_FLAGS + ["--instructions=2000000", f"--log={slog}", str(elf)], 300)
    if rc != 0:
        slog.unlink(missing_ok=True)
        return f"spike rc {rc}: {log.strip()[-200:]}"
    rc, log = run([sys.executable, str(ROOT / "scripts" / "spike_log_to_trace.py"), str(slog),
                   str(SW / f"{name}.trace"), "--tohost", tohost], 300)
    slog.unlink(missing_ok=True)
    if rc != 0:
        (SW / f"{name}.trace").unlink(missing_ok=True)
        return "trace conversion failed: " + log.strip()[-200:]
    return "ok: " + log.strip().split(": ")[-1]


def one(test, seed, gen_timeout):
    name = f"dv_{test.removeprefix('riscv_').removesuffix('_test')}_{seed}"
    out = DV_OUT / name
    env = dict(os.environ, PATH=f"{DV_PYTHON.parent}:{os.environ['PATH']}")
    rc, log = run([str(DV_PYTHON), "run.py", "--test", test, "--simulator", "pyflow",
                   "--custom_target", str(TARGET), "--target", "rv32im",
                   "--isa", "rv32im_zicsr", "--mabi", "ilp32", "--steps", "gen",
                   "-o", str(out), "--start_seed", str(seed), "-i", "1"],
                  gen_timeout, cwd=RISCV_DV, env=env)
    asm = out / "asm_test" / f"{test}_0.S"
    if rc != 0 or not asm.exists():
        return name, f"generator failed ({'hung' if rc == -1 else 'rc ' + str(rc)})"

    elf = SW / f"{name}.elf"
    rc, log = run([f"{PREFIX}gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-static", "-mcmodel=medany",
                   "-nostdlib", "-nostartfiles", f"-I{RISCV_DV / 'user_extension'}",
                   "-T", str(RISCV_DV / "scripts" / "link.ld"), str(asm), "-o", str(elf)], 120)
    if rc != 0:
        return name, "compile failed: " + log.strip().splitlines()[-1]
    subprocess.run([f"{PREFIX}objcopy", "-O", "verilog", "--change-addresses=-0x80000000",
                    str(elf), str(SW / f"{name}.hex")], check=True)
    nm = subprocess.run([f"{PREFIX}nm", str(elf)], capture_output=True, text=True).stdout
    tohost = next(l.split()[0] for l in nm.splitlines() if l.endswith(" tohost"))
    (SW / f"{name}.tohost").write_text(tohost + "\n")
    return name, spike_trace(name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", action="append", help="riscv-dv test (default: all in the testlist)")
    ap.add_argument("--seeds", type=int, default=2, help="programs per test")
    ap.add_argument("--seed-list", help="comma-separated seeds instead of random ones")
    ap.add_argument("-j", type=int, default=4, help="parallel generators")
    ap.add_argument("--gen-timeout", type=int, default=600, help="seconds before a generator is killed")
    ap.add_argument("--retrace", action="store_true",
                    help="only re-run Spike on the existing build/sw/dv_*.elf (after a parser change)")
    a = ap.parse_args()

    if a.retrace:
        for elf in sorted(SW.glob("dv_*.elf")):
            print(f"  {elf.stem:40} {spike_trace(elf.stem)}", flush=True)
        return

    SW.mkdir(parents=True, exist_ok=True)
    tests = a.test or tests_in_list()
    seeds = [int(s) for s in a.seed_list.split(",")] if a.seed_list else None
    jobs = [(t, s) for t in tests for s in (seeds or random.sample(range(1, 100000), a.seeds))]
    print(f"Generating {len(jobs)} programs with {a.j} jobs...")
    with ThreadPoolExecutor(max_workers=a.j) as ex:
        for name, status in ex.map(lambda j: one(j[0], j[1], a.gen_timeout), jobs):
            print(f"  {name:40} {status}", flush=True)


if __name__ == "__main__":
    main()
