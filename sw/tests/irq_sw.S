// Machine software interrupts, compared with Spike.
// A store to MSIP (0x0200_0000, Spike's CLINT) raises the interrupt while mstatus.MIE = 0;
// then `csrsi mstatus, 8` enables it. It is taken on the next instruction, before that
// instruction runs (mepc = its PC), and the instruction runs after MRET. Each case below
// puts a different kind of instruction there.
// Why not just store to MSIP with MIE = 1: Spike checks for interrupts only between
// batches of up to 5000 instructions, or right after a CSR write or MRET. After a plain
// store it would take the interrupt thousands of instructions later; the core takes it at
// the next instruction. Enabling with a CSR write makes both check at the same point.
// Registers: s0 = MSIP address, s1 = interrupt count, s3 = "leave MSIP set once" flag,
// s4 = exception count, s5 = vectored-mode entries, s2 = data buffer.
// Only the software interrupt is used: Spike's timer interrupt is always pending, so
// mie.MTIE stays 0 in every compared test.
#include "test.h"
#define MSIP 0x02000000

// raise the software interrupt; the instruction after this macro takes it
#define RAISE  csrci mstatus, 8; li t1, 1; sw t1, 0(s0); csrsi mstatus, 8

  .text
  .globl test_main
test_main:
  la   t0, irq_handler
  csrw mtvec, t0
  li   s0, MSIP
  li   s1, 0
  li   s3, 0
  li   s4, 0
  li   s5, 0
  la   s2, buf
  li   t0, 8
  csrw mie, t0                // MSIE only
  csrsi mstatus, 8            // MIE = 1

  // ---- 1. on an ALU instruction
  RAISE
  addi a0, x0, 11
  CHECK(s1, 1, 1)
  CHECK(a0, 11, 2)
  // ---- 2. on a load, 3. on a store
  li   t2, 0x55
  sw   t2, 0(s2)
  RAISE
  lw   a1, 0(s2)
  CHECK(a1, 0x55, 3)
  RAISE
  sw   a1, 4(s2)
  lw   a2, 4(s2)
  CHECK(a2, 0x55, 4)
  // ---- 4. on a taken branch, 5. on JAL, 6. on JALR
  RAISE
  beq  x0, x0, 1f
  j    fail
1:
  RAISE
  jal  ra, sub
  la   t2, sub
  RAISE
  jalr ra, 0(t2)
  CHECK(s1, 6, 5)
  // ---- 7. on a multiply and a divide
  li   a3, 100
  li   a4, 7
  RAISE
  mul  a5, a3, a4
  RAISE
  div  a6, a3, a4
  CHECK(a6, 14, 6)
  // ---- 8. on a CSR instruction (it runs only after MRET)
  RAISE
  csrw mtval, a3
  csrr a7, mtval
  CHECK(a7, 100, 7)
  // ---- 9. on an ECALL: interrupt first, then the ECALL's own exception
  RAISE
  ecall
  CHECK(s4, 1, 8)
  // ---- 10. on an illegal instruction: interrupt first, then illegal instruction
  RAISE
  .word 0xffffffff
  CHECK(s4, 2, 9)
  CHECK(s1, 11, 10)

  // ---- 11. pending while mstatus.MIE = 0: not taken until MIE is set
  csrci mstatus, 8
  li   t1, 1
  sw   t1, 0(s0)
  nop
  nop
  CHECK(s1, 11, 11)
  csrsi mstatus, 8            // taken right after this instruction
  CHECK(s1, 12, 12)
  // ---- 12. pending while mie.MSIE = 0: not taken until MSIE is set
  csrw mie, x0
  RAISE                       // MIE = 1 but MSIE = 0: stays pending
  nop
  CHECK(s1, 12, 13)
  li   t0, 8
  csrw mie, t0                // taken right after this instruction
  CHECK(s1, 13, 14)
  // ---- 13. taken again right after MRET (the handler leaves MSIP set once)
  li   s3, 1
  RAISE
  nop
  CHECK(s1, 15, 15)

  // ---- 14. vectored mode: interrupts go to BASE + 4 x cause, exceptions to BASE
  la   t0, vec_table
  ori  t0, t0, 1
  csrw mtvec, t0
  RAISE
  nop
  CHECK(s5, 1, 16)
  ecall                       // exception: entry 0
  CHECK(s4, 3, 17)
  la   t0, irq_handler
  csrw mtvec, t0

  csrci mstatus, 8
  CHECK(s1, 16, 18)
  PASS
fail:
  FAIL(99)

sub:
  addi a0, a0, 1
  ret

// Shared handler: interrupts return to mepc (the interrupted instruction runs next);
// exceptions skip the instruction. Only t5 is used, saved in mscratch.
  .align 2
irq_handler:
  csrw mscratch, t5
  csrr t5, mcause
  bltz t5, 1f                 // bit 31 set: interrupt
  csrr t5, mepc               // exception: skip the instruction
  addi t5, t5, 4
  csrw mepc, t5
  addi s4, s4, 1
  j    3f
1:
  addi s1, s1, 1
  beqz s3, 2f
  li   s3, 0                  // leave MSIP set this once
  j    3f
2:
  sw   zero, 0(s0)            // clear MSIP
3:
  csrr t5, mscratch
  mret

// Vectored table: entry 0 = exceptions, entry 3 = machine software interrupt
  .align 6
vec_table:
  j    irq_handler            // 0: exceptions
  j    fail                   // 1
  j    fail                   // 2
  j    vec_msi                // 3: machine software interrupt
vec_msi:
  addi s5, s5, 1
  j    irq_handler

  .data
  .align 4
buf: .space 16
