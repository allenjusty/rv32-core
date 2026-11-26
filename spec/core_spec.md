# RV32IM core: specification

A 5-stage in-order RV32IM + Zicsr core, machine mode only, with precise exceptions and
the three machine interrupts (software, timer, external). The RTL and the test flow are both built from this file. Where the
first plan left a choice open, the choice below is the one Spike (commit 6e188877) makes,
so the two can be compared instruction by instruction.

## 1. Instructions

| Group | Instructions | Notes |
|---|---|---|
| RV32I | LUI, AUIPC, JAL, JALR, BEQ/BNE/BLT/BGE/BLTU/BGEU, LB/LH/LW/LBU/LHU, SB/SH/SW, ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI, ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND, FENCE | FENCE is a no-op (one core, no caches). Any FENCE encoding with funct3 = 000 is accepted. |
| M | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU | Multiply: one cycle. Divide/remainder: iterative, about 34 cycles. Divide by zero: quotient = all ones, remainder = dividend. Overflow (-2^31 / -1): quotient = -2^31, remainder = 0. No exception in either case. |
| Zicsr | CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI | CSRRW/CSRRWI with rd = x0 do not read the CSR. CSRRS/CSRRC with rs1 = x0, and CSRRSI/CSRRCI with uimm = 0, do not write it. |
| Privileged | ECALL, EBREAK, MRET, WFI | WFI is a no-op. Spike would sleep until an interrupt, so Spike runs with `--wfi-as-nop`. |
| Zifencei | FENCE.I | Spike executes FENCE.I even when the ISA string leaves out Zifencei, so the core implements it: it flushes the pipeline and refetches the next instruction, like a CSR instruction. |
| Not implemented | A, F, D, C, SRET, any 16-bit encoding, any other encoding | Illegal instruction. |

## 2. Exceptions

On a trap: `mepc` = PC of the trapping instruction, `mcause` = code below, `mtval` as below,
`mstatus.MPIE` = `mstatus.MIE`, then `MIE` = 0, `MPP` stays 3, PC = `mtvec` with bits 1:0
cleared. MRET: PC = `mepc`, `MIE` = `MPIE`, `MPIE` = 1.

| mcause | Exception | When | mtval | Found in |
|---|---|---|---|---|
| 0 | Instruction address misaligned | Taken branch, JAL or JALR whose target is not 4-byte aligned (JALR clears target bit 0 first). Reported on the branch/jump, not the target. | Target | EX |
| 2 | Illegal instruction | Unknown encoding; unimplemented CSR; write to a read-only CSR (address bits 11:10 = 11) | Instruction bits (only the low 16 bits for a 16-bit encoding) | ID (encoding), MEM (CSR) |
| 3 | Breakpoint | EBREAK | PC | ID |
| 4 | Load address misaligned | LH/LHU not 2-byte aligned, LW not 4-byte aligned | Address | EX |
| 6 | Store address misaligned | SH not 2-byte aligned, SW not 4-byte aligned | Address | EX |
| 11 | Environment call from M-mode | ECALL | 0 | ID |

### Interrupts

* Inputs `irq_software`, `irq_timer`, `irq_external` (level) appear in `mip` bits 3, 7, 11
  (read-only: software clears the source). Enabled by `mie` bits 3, 7, 11 and `mstatus.MIE`.
* Priority when several are pending: external (11), software (3), timer (7).
* Taken in MEM on the instruction there, *before* it does anything: it does not run,
  `mepc` = its PC, `mcause` = 0x8000_0000 + code, `mtval` = 0, and it runs after MRET. An
  interrupt wins over that instruction's own exception.
* Not taken on an instruction that has already sent its data-port request (a request must
  not be withdrawn); the next instruction takes it. Not taken while MEM is empty.
* `mtvec` vectored mode (bit 0 = 1): interrupts go to BASE + 4 x code; exceptions to BASE.

A trapping instruction does not retire: no rd write, no memory write, no `minstret` count.
There are no access faults: tests only touch RAM.

## 3. CSRs

Any CSR not listed raises illegal instruction.

| Address | CSR | Behavior |
|---|---|---|
| 0x300 | mstatus | MIE (bit 3), MPIE (bit 7) writable; MPP (12:11) fixed at 3; other bits 0 |
| 0x310 | mstatush | Reads 0, writes ignored |
| 0x301 | misa | Reads 0x4000_1100, writes ignored. **Spike lets software clear the M bit (it then treats M instructions as illegal), so tests must never write misa.** |
| 0x304 | mie | Bits 3, 7, 11 (MSIE, MTIE, MEIE) writable, no effect |
| 0x344 | mip | Read-only: bits 3, 7, 11 show the interrupt lines; writes ignored. **Spike lets software set MTIP and has its own timer, so tests never write mip and keep mie.MTIE = 0 when compared.** |
| 0x305 | mtvec | Bits 31:2 (BASE) and bit 0 (vectored mode) writable, bit 1 reads 0 (same as Spike). |
| 0x340 | mscratch | Read/write |
| 0x341 | mepc | Read/write, bits 1:0 always 0 |
| 0x342 | mcause | Read/write (all 32 bits) |
| 0x343 | mtval | Read/write |
| 0xB00 / 0xB80 | mcycle / mcycleh | 64-bit cycle counter, writable |
| 0xB02 / 0xB82 | minstret / minstreth | 64-bit retired-instruction counter, writable |
| 0xF11-0xF15 | mvendorid, marchid, mimpid, mhartid, mconfigptr | Read-only 0 (Spike's marchid is 5: masked in the compare) |

A CSR instruction that writes a counter: the software write wins over that cycle's increment.

## 4. Memory map and test end

| Range | Use |
|---|---|
| 0x8000_0000, 1 MiB | RAM. Reset PC = 0x8000_0000. Spike: `-m0x80000000:0x100000`. |
| `tohost` symbol | Test end. Writing 1 = pass; writing (code << 1) \| 1 = fail with that code. `tohost` and `fromhost` are both defined, as in riscv-tests. |

## 5. Pipeline

IF, ID, EX, MEM, WB, in order, one instruction per stage.

* **IF**: holds `pc_f`, the address of the next fetch. Sends one fetch request at a time.
* **ID**: receives the instruction from the instruction port, decodes it, reads the register
  file (with bypass from a same-cycle WB write), computes branch/JAL targets, reads the BHT.
  Redirects fetch for JAL, and for a branch the BHT predicts taken. Flags illegal encodings,
  ECALL and EBREAK.
* **EX**: ALU, multiplier, iterative divider, branch compare, address adder, misalignment
  checks. Resolves branches and JALR, updates the BHT.
* **MEM**: data-port access (waits here for the response), CSR read/write, MRET, FENCE.I,
  and the trap unit. This is the commit point: every exception is taken here, so exceptions
  are precise (the only older instruction is in WB and can no longer trap).
* **WB**: load byte select and sign extension, register write, `minstret` count, trace port.

### Redirects and flushes (MEM highest priority)

| From | When | Flushes | New PC |
|---|---|---|---|
| MEM | Trap or interrupt | IF, ID, EX (incl. a running divide) | mtvec BASE (vectored: + 4 x cause for interrupts) |
| MEM | MRET | IF, ID, EX | mepc |
| MEM | CSR instruction (even read-only) or FENCE.I | IF, ID, EX | PC + 4 |
| EX | Branch mispredicted, or JALR | IF, ID | actual target / PC + 4 |
| ID | JAL, or branch predicted taken | IF | target |

A branch, JAL or JALR whose target is not 4-byte aligned never redirects: it carries the
exception to MEM, so the core never fetches from a misaligned address.

### Hazards

* **Forwarding**: EX takes rs1/rs2 from EX/MEM, then MEM/WB, then the value read in ID. Never
  for x0. While EX is stalled it re-captures the forwarded values every cycle, so a value does
  not get lost when its producer moves on to WB and then leaves.
* **Load-use**: a load in EX and a dependent instruction in ID: ID stalls one cycle (a bubble
  goes to EX); the data then forwards from MEM/WB.
* **Divide**: a DIV/DIVU/REM/REMU in EX stalls IF, ID and EX until the result is ready; MEM and
  WB keep moving.
* **Data-port wait**: MEM waits for the response; IF, ID, EX and MEM stall, WB gets a bubble.
* **Fetch wait**: ID has no instruction yet; ID holds and sends bubbles to EX.

### Branch prediction

| Case | BHT off (predict not-taken) | BHT on |
|---|---|---|
| Branch not taken, predicted not taken | 0 bubbles | 0 bubbles |
| Branch taken, predicted taken | not possible | 1 bubble (ID redirect) |
| Branch mispredicted | 2 bubbles (EX redirect) | 2 bubbles (EX redirect) |
| JAL | 1 bubble | 1 bubble |
| JALR | 2 bubbles | 2 bubbles |

BHT: 64 two-bit saturating counters indexed by PC[7:2], reset to 01 (weakly not taken),
read in ID, updated in EX with the real outcome. Parameter `BHT_EN` = 0 gives the
predict-not-taken baseline.

## 6. Memory ports

Two ports, instruction and data, the same signals each:

| Signal | Dir | Meaning |
|---|---|---|
| req_valid | out | Request. Once high it stays high, with the same payload, until accepted. |
| req_ready | in | Request accepted when valid and ready are both high. Must not depend on req_valid. |
| req_addr | out | Byte address (word-aligned on the instruction port) |
| req_we, req_be, req_wdata | out | Write enable, byte enables, write data in its byte lanes |
| rsp_valid | in | One-cycle pulse with the read data (also sent for writes) |
| rsp_rdata | in | Whole 32-bit word; the core selects and sign-extends bytes |

* One request outstanding per port.
* Instruction port: the response comes at least one clock after the request is accepted,
  so with no wait states the instruction reaches ID in the next cycle.
* Data port: the response may come in the same cycle the request is accepted (zero wait
  states: a combinational read, as in the textbook pipeline) or any number of cycles later.
* The testbench memory adds random wait states on both ports. CPI runs use zero wait states.

## 7. Retirement trace

From WB, one record per retired instruction: valid, PC, instruction, rd number, rd value,
rd write (rd != x0), store (valid, address, data, size), CSR write (valid, address, new value;
MRET reports its new mstatus here).
From MEM, one record per trap: valid, mcause, mepc, mtval. When both appear in the same cycle,
the WB record is older and is compared first.

## 8. Compare rules against Spike

* Compared per retired instruction: PC, instruction bits, rd and its value, store address,
  data and size, and the new value of the CSR a CSR instruction writes (and of mstatus for
  MRET). Per trap: mcause, mepc, mtval.
* Masked rd values: reads of mcycle(h), minstret(h), mip, marchid. Also masked: the new
  value written to a counter or to mip (it depends on the old value, which differs:
  Spike's built-in timer sets mip.MTIP by itself).
* Spike's boot ROM leaves some registers non-zero; every test writes a register before it
  reads it.
* Tests never write mip or misa, and keep mie.MTIE = 0 (Spike's timer interrupt is always
  pending). The compared interrupt test uses only the software interrupt (Spike's CLINT
  MSIP at 0x0200_0000), raised while MIE = 0 and then enabled with a CSR write, because
  Spike only checks for interrupts after a CSR write, an MRET, or a batch of instructions.
* Random interrupts (testbench generator at 0x0201_0000) are not compared with Spike; those
  programs check themselves (sw/tests_irq/).
* The compare ends at the store to `tohost` (Spike runs a few more instructions before it
  notices the write).
