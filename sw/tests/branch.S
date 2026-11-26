// Every branch type, taken and not taken, forward and backward targets,
// plus loops that train the BHT (taken many times, then falls through).
#include "test.h"
  .text
  .globl test_main
test_main:
  li   s0, 0
  li   s1, 1
  li   s2, -1
  li   s3, 0x80000000
  li   a0, 0                 // count of taken branches

#define TAKEN(op, x, y)  op x, y, 1f; j fail; 1: addi a0, a0, 1
#define NOT_TAKEN(op, x, y)  op x, y, fail
  TAKEN(beq, s1, s1)
  NOT_TAKEN(beq, s1, s0)
  TAKEN(bne, s1, s0)
  NOT_TAKEN(bne, s2, s2)
  TAKEN(blt, s2, s1)          // -1 < 1 signed
  NOT_TAKEN(blt, s1, s2)
  TAKEN(blt, s3, s0)          // min < 0
  TAKEN(bge, s1, s2)
  TAKEN(bge, s1, s1)          // equal
  NOT_TAKEN(bge, s2, s1)
  TAKEN(bltu, s1, s2)         // 1 < 0xffffffff unsigned
  NOT_TAKEN(bltu, s2, s1)
  TAKEN(bgeu, s2, s1)
  TAKEN(bgeu, s0, s0)
  NOT_TAKEN(bgeu, s0, s1)
  CHECK(a0, 9, 1)

  // Backward loop: taken 20 times then not taken (trains the BHT both ways)
  li   t0, 20
  li   t1, 0
loop1:
  addi t1, t1, 1
  addi t0, t0, -1
  bnez t0, loop1
  CHECK(t1, 20, 2)

  // Backward BEQ loop: taken while t1 == t2, then falls through
  li   t0, 0
  li   t2, 0
loop_beq:
  addi t0, t0, 1
  slti t1, t0, 12          // 1 while t0 < 12
  li   t2, 1
  beq  t1, t2, loop_beq
  CHECK(t0, 12, 4)

  // Nested loops with an inner branch that alternates taken / not taken
  li   t0, 6
  li   t2, 0
outer:
  li   t1, 5
inner:
  andi t3, t1, 1
  beqz t3, skip
  addi t2, t2, 1
skip:
  addi t1, t1, -1
  bnez t1, inner
  addi t0, t0, -1
  bgtz t0, outer
  CHECK(t2, 18, 3)

  // Forward branch over a block, repeated (taken, predicted taken after training)
  li   t0, 8
fwd:
  bnez t0, 1f
  j    fail
1:
  addi t0, t0, -1
  bnez t0, fwd

  // Branch that depends on the instruction right before it (forwarding into compare)
  li   t0, 3
  addi t0, t0, -3
  beqz t0, 1f
  j    fail
1:
  lw   t1, -8(sp)             // load-use into a branch
  li   t1, 0
  sw   t1, -4(sp)
  lw   t2, -4(sp)
  bnez t2, fail
  PASS
fail:
  FAIL(99)
