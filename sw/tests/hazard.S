// Data hazards: forwarding from EX/MEM and MEM/WB on rs1 and rs2, load-use stalls,
// MUL and DIV producers, and x0 never forwarding.
#include "test.h"
  .text
  .globl test_main
test_main:
  la   s0, buf
  li   a0, 5
  // EX/MEM -> EX on rs1, then rs2, then both
  addi a1, a0, 1         // 6
  addi a2, a1, 1         // rs1 from EX/MEM: 7
  add  a3, a0, a2        // rs2 from EX/MEM: 12
  add  a4, a3, a3        // both from EX/MEM: 24
  CHECK(a4, 24, 1)
  // MEM/WB -> EX
  li   a1, 10
  nop
  addi a2, a1, 1         // from MEM/WB: 11
  CHECK(a2, 11, 2)
  // newest value wins when both stages hold the same register
  li   a1, 1
  li   a1, 2
  addi a2, a1, 0
  CHECK(a2, 2, 3)
  // load-use on rs1 and on rs2
  li   t0, 77
  sw   t0, 0(s0)
  lw   t1, 0(s0)
  addi t2, t1, 1         // stall one cycle, then MEM/WB forward
  CHECK(t2, 78, 4)
  lw   t1, 0(s0)
  add  t2, a0, t1        // rs2 load-use
  CHECK(t2, 82, 5)
  lw   t1, 0(s0)
  nop
  add  t2, t1, t1        // load then one gap: MEM/WB forward, no stall
  CHECK(t2, 154, 6)
  // load-use into a store (data and address)
  lw   t1, 0(s0)
  sw   t1, 4(s0)
  lw   t3, 4(s0)
  CHECK(t3, 77, 7)
  la   t4, buf
  sw   t4, 8(s0)
  lw   t5, 8(s0)
  sw   a0, 12(t5)        // load-use on the address register
  lw   t6, 12(s0)
  CHECK(t6, 5, 8)
  // MUL and DIV results forwarding
  li   a1, 7
  mul  a2, a1, a1
  addi a3, a2, 1
  CHECK(a3, 50, 9)
  div  a4, a3, a1
  addi a5, a4, 0
  CHECK(a5, 7, 10)
  rem  a6, a3, a1
  add  a7, a6, a4        // 1 + 7
  CHECK(a7, 8, 11)
  // a divide whose operand comes from a load right before it
  lw   t1, 0(s0)
  divu t2, t1, a1        // 77 / 7
  CHECK(t2, 11, 12)
  // writes to x0 must not forward
  addi x0, a0, 100
  add  t3, x0, x0
  CHECK(t3, 0, 13)
  lw   x0, 0(s0)
  add  t3, x0, a0
  CHECK(t3, 5, 14)
  // A producer, then a load or store, then a consumer of the producer. When the
  // load/store waits in MEM, the producer leaves WB while the consumer is still in EX, so
  // EX must keep the forwarded value (run with data-port wait states to stress this).
  li   t0, 0
  li   t1, 0
  li   t3, 0
  li   t4, 30
1:
  addi t0, t0, 3         // producer
  lw   t5, 0(s0)         // load in MEM (may wait)
  add  t1, t0, t1        // consumer: the producer is rs1
  addi t3, t3, 1         // producer
  sw   t3, 4(s0)         // store in MEM (may wait)
  add  t1, t1, t3        // consumer: the producer is rs2
  addi t4, t4, -1
  bnez t4, 1b
  CHECK(t1, 1860, 16)    // sum(3i) + sum(i) for i = 1..30 = 1395 + 465

  // long chain through every stage
  li   t0, 1
  add  t0, t0, t0
  add  t0, t0, t0
  add  t0, t0, t0
  add  t0, t0, t0
  CHECK(t0, 16, 15)
  PASS
fail:
  FAIL(99)
  .data
  .align 4
buf: .space 32
