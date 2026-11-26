# RV32IM 5-stage core, verified against Spike

A small in-order RISC-V core (RV32IM + Zicsr, machine mode, precise exceptions and
interrupts) written in
SystemVerilog, and the verification environment that checks it **instruction by
instruction against Spike**, the RISC-V reference simulator. Built with free tools only
(Verilator, UVM 1800.2-2017, Spike, riscv-dv, GCC).

| | |
|---|---|
| Core | 5-stage pipeline (IF, ID, EX, MEM, WB), forwarding, load-use stall, iterative divider, 64-entry 2-bit BHT, machine-mode CSRs, traps and interrupts (software, timer, external; direct and vectored) |
| Reference | Spike, commit log converted to an expected trace; every retired instruction and every trap compared |
| Stimulus | 11 directed assembly tests, 28 riscv-dv random programs (7 tests, Python riscv-dv with 15 bugs fixed), CoreMark (5.8M instructions), a random-interrupt self-checking program |
| Memory timing | Random wait states on both memory ports (3 UVM tests) plus random interrupts (1 UVM test) |
| Checks | Spike compare, 20 SVA assertions, program self-checks, watchdog |
| Regression | 250 / 250 runs pass (41 programs x memory-timing and interrupt tests x random seeds) |
| Coverage | 428 / 428 functional coverage bins (100 %) |
| Mutation check | 17 / 17 injected bugs caught (one more turned out to be an equivalent mutant) |
| BHT | CPI 1.310 → 1.233 on CoreMark (5.9 % better), mispredict rate 55.3 % → 9.1 % |

## How it is checked

```
 test program (.S)  ──gcc──►  ELF ──►  Spike --log-commits ──► spike_log_to_trace.py ──► expected trace
                                │
                                └────►  RTL (core + memory with random wait states)
                                              │ retirement trace (WB) + trap record (MEM)
                                              ▼
                                   UVM: retire_monitor ──► spike_scoreboard (compare, stop at 1st mismatch)
                                                       ├─► tohost_monitor (end of test, pass/fail)
                                                       └─► core_coverage  (+ pipeline probes)
```

Each record holds the PC, the instruction, the rd value, the store address/data/size and
the new value of any CSR written (including `mstatus` on MRET); each trap holds mcause,
mepc and mtval. A few values can never match Spike and are masked: reads of the cycle and
instret counters, `mip` (Spike has a timer) and `marchid` (spec section 8).

## Results

### Regression
| Programs | Count | Instructions compared (per run) | Runs | Pass |
|---|---|---|---|---|
| Directed assembly tests | 11 | 2,704 | 66 | 66 |
| riscv-dv random programs | 28 | 109,010 | 168 | 168 |
| CoreMark (compare build) | 1 | 5,779,698 | 4 | 4 |
| Random interrupts (self-checking, no Spike) | 1 | — | 12 | 12 |
| **Total** | **41** | | **250** | **250** |

Each Spike-compared program runs under `core_base_test` (no wait states, 1 seed),
`core_rand_wait_test` (random waits on both ports, 3 seeds) and `core_heavy_wait_test`
(long waits on one port, 2 seeds; not CoreMark, which is too slow there). The interrupt
program runs under `core_irq_test` (random interrupts and waits, 12 seeds). The directed tests also pass on BHT-on and BHT-off builds with 20 wait-state
settings on the fast plain-SV bench.

### Functional coverage
| Covergroup | What it measures | Bins |
|---|---|---|
| cg_instr | every implemented instruction retired | 55 / 55 |
| cg_operands, cg_div | operand classes (0, 1, -1, max, min) for ALU / MUL / DIV; divide by zero, overflow | 53 / 53 |
| cg_fwd | forwarding source x operand x producer (ALU, MUL, DIV, load) | 14 / 14 |
| cg_stall | load-use, divider busy, fetch wait, data wait | 4 / 4 |
| cg_branch, cg_bht | branch type x taken x direction x predicted right/wrong; counter states | 64 / 64 |
| cg_ldst | each load/store x byte offset (misaligned ones trap) | 44 / 44 |
| cg_trap, cg_nested | each mcause x the stage that found it; trap inside a trap handler | 8 / 8 |
| cg_csr | each CSR x each CSR instruction (one impossible combination left out), rd/rs1 = x0, read-only writes | 141 / 141 |
| cg_overlap, cg_regs | overlapping events (mispredict during a data wait, trap during a fetch wait, ...); x0 and rd = rs cases | 9 / 9 |
| cg_irq, cg_irq_wait | each interrupt x kind of instruction interrupted, direct/vectored, during a fetch wait; interrupt waiting behind a divide or a data request | 36 / 36 |

Two items of the first coverage plan turned out to be impossible in this design (a
load-use stall during a fetch wait, and a flush while the divider is busy); the reasons
are in [docs/testplan.md](docs/testplan.md), and the second is now an assertion.

### Mutation check
Bugs injected on purpose, one per copy of the RTL; each must make some test fail.

| Injected bug | Caught by |
|---|---|
| no forwarding from EX/MEM (`no_exmem_fwd`) | alu (Spike compare) |
| no load-use stall (`no_load_use_stall`) | branch (a_no_late_fwd assertion) |
| EX does not keep forwarded operands while stalled (`no_operand_refresh`) | hazard (program self-check: code 16, with waits) |
| MULH* return the low half (`mulh_low_half`) | muldiv (program self-check: code 1) |
| divide by zero gives 0 (`div0_quotient_0`) | muldiv (program self-check: code 10) |
| a wrongly predicted-taken branch is not corrected (`no_taken_fix`) | alu (program self-check: code 99) |
| ID redirects to a misaligned target (`id_redirect_misaligned`) | exception (a_fetch_aligned assertion) |
| a held fetch is not killed by a redirect (`held_fetch_not_killed`) | alu (Spike compare, with waits) |
| CSRRS/CSRRC with rs1 = x0 write the CSR (`csrrs_x0_writes`) | csr (program self-check: code 98) |
| MRET sets MPIE to 0 (`mret_mpie_0`) | exception (Spike compare) |
| LB zero-extends (`lb_zero_extend`) | loadstore (program self-check: code 1) |
| byte store enables not shifted (`store_be_no_shift`) | loadstore (program self-check: code 99) |
| interrupt mepc points past the interrupted instruction (`irq_mepc_plus4`) | irq_sw (program self-check: code 2) |
| interrupts ignore the mie enable bits (`irq_ignores_mie`) | irq_sw (program self-check: code 13) |
| interrupt withdraws a data request already sent (`irq_withdraws_dreq`) | irq_random (a_irq_no_req assertion) |
| vectored mtvec offset not multiplied by 4 (`vector_no_shift`) | irq_sw (a_fetch_aligned assertion) |
| timer interrupt given priority over external (`irq_timer_first`) | irq_random (a_irq_priority assertion) |

Three mutants survived at first. Two showed real gaps in the tests (bug log #12, #13). The
third was an *equivalent* mutant (it changes nothing observable), but it showed that
interrupt priority was not checked, so an assertion was added (bug log #17).

### CPI: BHT off vs on
See [perf/results.md](perf/results.md). A correctly predicted taken branch still costs one
bubble, because the BHT gives only a direction and the target is computed in ID; a BTB
would remove it.

## Interrupts

Interrupts are taken in MEM, on the instruction there, before it does anything (it runs
after MRET). Two ways of checking them:

* **Compared with Spike** (`sw/tests/irq_sw.S`): software interrupts land on every kind of
  instruction (ALU, load, store, branch, JAL/JALR, MUL/DIV, CSR, ECALL, illegal), plus
  pending-while-disabled, again-right-after-MRET, and vectored mode. Spike only checks for
  interrupts after a CSR write, an MRET or a batch of instructions, so the test raises the
  interrupt while disabled and enables it with a CSR write (bug log #16).
* **Random, self-checking** (`sw/tests_irq/irq_random.S`, `core_irq_test`): the testbench
  raises timer and external interrupts at random cycles. The same work runs with
  interrupts off and on, and the results must be equal. Assertions check enable, priority,
  latency, and that a sent data request is never withdrawn.

## riscv-dv fixes

The Python version of riscv-dv (needed because the SystemVerilog one wants a commercial
simulator) could not generate most of its tests. 15 bugs were fixed: hangs, a misplaced
`else`, shallow copies sharing fields, a shared list that kept growing, off-by-one random
picks, Python `and`/`or` used inside solver constraints, an unfinished loop stream, three
streams that were never ported, and more. The fixes are in
[sw/riscv-dv/pyflow_fixes.patch](sw/riscv-dv/pyflow_fixes.patch) (each one marked `Fix:`),
applied to riscv-dv commit f557b89. Sub-programs are still not supported.

## Bugs found
[docs/bug_log.md](docs/bug_log.md) lists every real bug: symptom, how it was caught, root
cause, fix, and whether it was in the design, the testbench, a test program or a
difference between the spec and Spike.

## Repository

```
spec/      core_spec.md                       the spec, written before the RTL
rtl/       core_top (pipeline), decode, alu, mul, div, bht, regfile, csr
tb/        common/tb_mem.sv (memory, wait states), smoke/ (plain SV bench),
           env/ (UVM), tests/, coverage/, sva/
sw/        common/ (crt, link.ld, macros), tests/ (directed, Spike-compared), tests_irq/
           (random interrupts, self-checking), riscv-dv/ (rv32im target, testlist, fixes patch)
perf/      CoreMark port, crt0, results.md
scripts/   spike_log_to_trace.py, compare_trace.py, gen_riscv_dv.py, run_regression.py,
           mutation_test.sh, cov_report.py, cpi_report.py
docs/      testplan.md, bug_log.md
```

## Running it

Tools: Verilator 5.054, Spike 6e188877, xPack `riscv-none-elf-gcc` 15.2.0, riscv-dv
(PyFlow), CoreMark (cloned separately). The CI workflow shows a full setup from scratch.

```sh
make lint                       # Verilator -Wall
make sw                         # directed tests + their Spike traces
make smoke && make run_all      # fast plain-SV bench, Spike compare
make run T=hazard ARGS="+DREADY_PCT=50 +DLAT_MAX=3"     # one test with data-port waits
scripts/gen_riscv_dv.py --seeds 4                       # riscv-dv programs + Spike traces
                                                        # (riscv-dv with sw/riscv-dv/pyflow_fixes.patch)
make sw_irq && make run_irq T=irq_random                # random interrupts, self-checking
make coremark_cmp               # CoreMark as a 5.8M-instruction compare test
make tb                         # UVM bench (about 1-3 minutes)
make test T=exception TEST=core_heavy_wait_test SEED=4
scripts/run_regression.py       # everything, random seeds, merged coverage
scripts/mutation_test.sh        # injected bugs
make cpi                        # CoreMark CPI, BHT off vs on
```
