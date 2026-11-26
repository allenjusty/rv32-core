// JAL and JALR: link values, calls and returns, computed targets, rd = x0 / rd = rs1.
#include "test.h"
  .text
  .globl test_main
test_main:
  li   s0, 0
  jal  ra, func1             // call
  CHECK(s0, 1, 1)
  la   t0, func2
  jalr ra, 0(t0)             // call through a register
  CHECK(s0, 3, 2)
  la   t0, func2 - 8
  jalr ra, 8(t0)             // offset added to the base
  CHECK(s0, 5, 3)
  la   t0, func1 + 1         // bit 0 of the target is cleared by JALR
  jalr ra, 0(t0)
  CHECK(s0, 6, 4)
  jal  x0, 1f                // jump without link
  j    fail
1:
  la   t2, 2f
  jalr t2, 0(t2)             // rd == rs1: target uses the old value
2:
  la   t3, 2b                // link = address after the JALR = 2b
  bne  t2, t3, fail
  // JALR right after the instruction that makes its target (forwarding)
  la   t0, 3f
  addi t0, t0, 0
  jalr x0, 0(t0)
  j    fail
3:
  // a chain of jumps
  j    4f
5: j   6f
4: j   5b
6:
  // recursion-like nested calls with the stack
  li   a0, 5
  jal  ra, sum_to_n          // a0 = 5+4+3+2+1
  CHECK(a0, 15, 5)
  PASS
fail:
  FAIL(99)

func1:
  addi s0, s0, 1
  ret
func2:
  addi s0, s0, 2
  jr   ra

sum_to_n:                    // a0 = n + sum_to_n(n-1)
  addi sp, sp, -8
  sw   ra, 4(sp)
  sw   a0, 0(sp)
  li   t0, 1
  ble  a0, t0, 1f
  addi a0, a0, -1
  jal  ra, sum_to_n
  lw   t1, 0(sp)
  add  a0, a0, t1
1:
  lw   ra, 4(sp)
  addi sp, sp, 8
  ret
