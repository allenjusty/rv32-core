# Test plan

The main check for everything is the **Spike compare**: every retired instruction (PC,
instruction, rd value, store address/data/size, CSR write) and every trap (mcause, mepc,
mtval) must match Spike, record by record. Assertions check the pipeline rules that the
trace cannot see. Coverage shows which cases were actually exercised.

A case is done only when coverage shows it was hit *and* a check would catch a failure.

## Stimulus

| Source | What | Programs |
|---|---|---|
| Directed assembly (`sw/tests/`) | Every spec rule on purpose, small and readable | alu, branch, jump, loadstore, hazard, muldiv, csr, exception, fencei, csr_all |
| riscv-dv (PyFlow), `rv32im` target | Random instruction mixes: arithmetic with corner values, random loads/stores with load-store hazards, JAL/JALR chains | 3 riscv-dv tests x many seeds (see the note below) |
| CoreMark, compare build | 5.8M instructions of real compiled C, compared with Spike | `make coremark_cmp` |
| Interrupt tests | `irq_sw.S` (compared with Spike: software interrupt on every kind of instruction, enable/disable, after MRET, vectored mode); `irq_random.S` (random timer/external interrupts plus software ones, same work run with interrupts off and on must give the same checksum) | `core_irq_test`, 12 seeds |
| Memory timing (UVM test) | `core_base_test` zero waits; `core_rand_wait_test` random waits on both ports; `core_heavy_wait_test` long waits on one port | every program runs under all three |

## Spec rules → tests → checks → coverage

| Spec area | Tests | Check | Coverage |
|---|---|---|---|
| RV32I instructions | alu, branch, jump, loadstore, all riscv-dv | Spike compare | `cg_instr` (every instruction retired), `cg_operands`, `cg_regs` |
| M extension, divide by zero, overflow | muldiv, hazard, riscv_arithmetic_basic_test, CoreMark | Spike compare; `a_div_after_start`, `a_div_bounded` | `cg_operands` (unit x operand class), `cg_div` |
| Zicsr rules (rd = x0, rs1 = x0, WARL bits, read-only CSRs) | csr, csr_all, exception | Spike compare (rd and new CSR value) | `cg_csr` (CSR x instruction, rd/rs1 = x0, read-only write) |
| Exceptions: each mcause, mepc, mtval, no retire | exception, csr_all | Spike compare of trap records; `a_trap_no_retire` | `cg_trap` (cause x stage), `cg_nested` |
| MRET, trap inside a handler | exception | Spike compare | `cg_instr` (MRET), `cg_nested` |
| FENCE.I refetch | fencei | Spike compare (patched instruction's result) | `cg_instr` (FENCE_I) |
| Forwarding EX/MEM and MEM/WB, x0 never forwards | hazard, riscv_rand_instr_test, riscv_arithmetic_basic_test, CoreMark | Spike compare; `a_no_late_fwd` | `cg_fwd` (source x operand x producer) |
| Load-use stall | hazard, loadstore, riscv_rand_instr_test, CoreMark | Spike compare | `cg_stall.cp_load_use` |
| Divider stall and flush | muldiv, exception (trap in the cycle a divide starts, trap after a divide) | Spike compare; `a_div_bounded`, `a_no_flush_div_busy` | `cg_stall.cp_div_busy`, `cg_overlap.cp_flush_div_start` |
| Branch prediction (BHT on/off), early JAL redirect | branch, jump, riscv_jump_stress_test, CoreMark | Spike compare (a wrong redirect retires wrong PCs) | `cg_branch` (type x taken x direction x prediction right/wrong), `cg_bht` |
| Misaligned targets never fetched | exception | `a_fetch_aligned`; Spike compare | `cg_trap.iaddr_ex` |
| Wrong-path instructions never trap or write | exception (illegal words after taken jumps) | Spike compare | — |
| Memory ports: request stable, one outstanding | all, with wait states | `a_i_stable`, `a_d_stable`, `a_*_one_out`, `a_*_no_new` | `cg_stall.cp_fetch`, `cg_stall.cp_dwait` |
| Interrupts: taken only when enabled, priority, precise, never withdraw a data request, bounded latency, vectored mode | irq_sw, irq_random | Spike compare (irq_sw); program self-check (irq_random); `a_irq_enabled`, `a_irq_priority`, `a_irq_no_req`, `a_irq_latency` | `cg_irq` (cause x interrupted instruction kind, direct/vectored, during fetch wait), `cg_irq_wait` |
| Flushes clear stages | all | `a_flush_id`, `a_flush_ex` | `cg_overlap` |
| Overlaps of events | wait-state tests on all programs | Spike compare | `cg_overlap`: mispredict while the data port waits, load-use while the data port waits, trap while a fetch is outstanding, flush in the cycle a divide starts |

### riscv-dv: fixing the PyFlow generator

The Python version of riscv-dv could not generate most of its tests (hangs, crashes,
programs cut short by misaligned loads). Its bugs were fixed (`sw/riscv-dv/pyflow_fixes.patch`,
bug log #11) and all 7 tests in `sw/riscv-dv/rv32im/testlist.yaml` now generate. Sub-programs
are still not supported, so `num_of_sub_program` is 0; calls and returns are covered by
riscv_jal_instr, jump stress and `jump.S`.

### One coverage item changed from the first plan

The first plan listed "load-use stall in the same cycle as a fetch wait". In this design
that cannot happen: the core only sends a fetch when the ID slot will be free, and a
load-use stall keeps ID full, so no fetch is ever outstanding during a load-use stall.
It was replaced with "load-use stall while the data port is waiting", which can happen.

"Flush while the divider is busy" cannot happen either: while a divide runs, EX stalls, so
MEM only receives bubbles and there is no older instruction left that could trap. A trap
can only meet a divide in the cycle the divide starts (the divider then never starts). That
case is covered instead, and assertion `a_no_flush_div_busy` checks that the impossible one
really never happens.

## End of test

A test ends when the store to `tohost` retires: 1 = pass, anything else = fail with
code = value >> 1. The run also fails on the first trace mismatch, if no instruction
retires for 5000 cycles (watchdog), or on any assertion failure.

## Mutation check

`scripts/mutation_test.sh` injects bugs on purpose (one per copy of the RTL) and checks
that the regression catches each one. Results are in the README.
