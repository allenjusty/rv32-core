// Random interrupts, self-checking (not compared with Spike: Spike has no random
// interrupt source). The testbench raises the timer and external lines at random cycles
// (+IRQ_EXT_PM / +IRQ_TMR_PM); the work also raises software interrupts itself.
//
// The same work runs twice: with interrupts off, then on. The two checksums must be equal,
// so an instruction lost, repeated or corrupted around an interrupt shows up. The handler
// also checks every mcause, and the ECALL count must be the same in both runs.
#include "test.h"
#define MSIP   0x02000000
#define IRQGEN 0x02010000
#define ITER   200

  .text
  .globl test_main
test_main:
  la   t0, handler
  csrw mtvec, t0
  li   s10, IRQGEN
  li   s11, MSIP

  // run 1: interrupts off
  csrw mie, x0
  call work
  mv   s9, a0

  // run 2: all three interrupts on
  li   t0, 0x888
  csrw mie, t0
  csrsi mstatus, 8
  call work
  csrci mstatus, 8
  csrw mie, x0
  bne  a0, s9, fail_sum

  la   t0, ecall_count
  lw   t1, 0(t0)
  li   t2, 2 * ITER / 8
  bne  t1, t2, fail_ecall
  la   t0, irq_count
  lw   t1, 0(t0)
  beqz t1, fail_noirq
  PASS
fail_sum:   FAIL(1)
fail_ecall: FAIL(2)
fail_noirq: FAIL(3)

// ---------------------------------------------------------------- the work
// Returns a checksum in a0. Uses a0, t0-t6, s0-s2 (never s9-s11).
work:
  addi sp, sp, -16
  sw   ra, 12(sp)
  la   s1, wbuf
  li   t0, 0                  // clear the buffer so both runs start the same
1:
  add  t1, s1, t0
  sw   zero, 0(t1)
  addi t0, t0, 4
  li   t1, 256
  blt  t0, t1, 1b
  li   a0, 0x1234
  li   s0, 0
  li   s2, ITER
loop:
  slli t0, s0, 2
  andi t0, t0, 0xfc
  add  t1, s1, t0
  lw   t2, 0(t1)              // load, then use right away (load-use)
  add  t2, t2, a0
  xor  t2, t2, s0
  sw   t2, 0(t1)
  mul  t3, t2, s2
  add  a0, a0, t3
  addi t4, s0, 3
  divu t5, a0, t4             // a divide in every iteration
  remu t6, a0, t4
  add  a0, a0, t5
  xor  a0, a0, t6
  lb   t3, 1(t1)
  lhu  t4, 2(t1)
  add  a0, a0, t3
  add  a0, a0, t4
  sb   a0, 3(t1)
  andi t3, s0, 7
  bnez t3, 2f
  ecall                       // every 8 iterations: an exception among the interrupts
  jal  ra, helper
2:
  andi t3, s0, 31
  bnez t3, 3f
  li   t4, 1
  sw   t4, 0(s11)             // raise a software interrupt every 32 iterations
3:
  csrw mscratch, a0
  csrr t5, mscratch
  srli t5, t5, 3
  add  a0, a0, t5
  addi s0, s0, 1
  blt  s0, s2, loop
  lw   ra, 12(sp)
  addi sp, sp, 16
  ret

helper:
  la   t0, helper2
  jr   t0
helper2:
  addi a0, a0, 7
  ret

// ---------------------------------------------------------------- the handler
// Saves the registers it uses. Interrupts: acknowledge the source and count.
// Exceptions: only ECALL is expected; skip it and count.
  .align 2
handler:
  addi sp, sp, -16
  sw   t0, 0(sp)
  sw   t1, 4(sp)
  sw   t2, 8(sp)
  csrr t0, mcause
  bltz t0, irq
  li   t1, 11
  bne  t0, t1, hfail
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  la   t1, ecall_count
  j    count
irq:
  li   t1, 0x8000000b
  beq  t0, t1, ext
  li   t1, 0x80000007
  beq  t0, t1, tmr
  li   t1, 0x80000003
  beq  t0, t1, swi
  j    hfail
ext:
  li   t1, 1
  sw   t1, 0(s10)             // acknowledge the external line
  j    1f
tmr:
  li   t1, 2
  sw   t1, 0(s10)             // acknowledge the timer line
  j    1f
swi:
  sw   zero, 0(s11)           // clear MSIP
1:
  la   t1, irq_count
count:
  lw   t2, 0(t1)
  addi t2, t2, 1
  sw   t2, 0(t1)
  lw   t0, 0(sp)
  lw   t1, 4(sp)
  lw   t2, 8(sp)
  addi sp, sp, 16
  mret
hfail:
  FAIL(4)

  .data
  .align 4
irq_count:   .word 0
ecall_count: .word 0
wbuf:        .space 256
