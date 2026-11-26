// M extension: every instruction with edge operands, divide by zero and the
// signed overflow case (-2^31 / -1). No exception is expected.
#include "test.h"
  .text
  .globl test_main
test_main:
  li   s0, 0
  li   s1, 1
  li   s2, -1
  li   s3, 0x7fffffff
  li   s4, 0x80000000
  li   s5, 0x12345678
  li   s6, -7
  li   s7, 3

  mul    a0, s5, s5
  mulh   a1, s5, s5
  mulh   a2, s4, s4          // min * min, high = 0x40000000
  CHECK(a2, 0x40000000, 1)
  mulh   a3, s2, s2
  CHECK(a3, 0, 2)
  mulhu  a4, s2, s2          // high of 0xffffffff^2 = 0xfffffffe
  CHECK(a4, 0xfffffffe, 3)
  mulhsu a5, s2, s2          // -1 * 0xffffffff, high = -1
  CHECK(a5, -1, 4)
  mulhsu a6, s4, s3
  mulhu  a7, s4, s3
  mul    t0, s4, s2          // min * -1 wraps to min
  CHECK(t0, 0x80000000, 5)
  mul    t1, s0, s5
  mulh   t2, s6, s7          // -21, high = -1
  CHECK(t2, -1, 6)

  div    a0, s6, s7          // -7 / 3 = -2 (rounds toward 0)
  CHECK(a0, -2, 7)
  rem    a1, s6, s7          // -1 (sign of dividend)
  CHECK(a1, -1, 8)
  divu   a2, s6, s7
  remu   a3, s6, s7
  div    a4, s7, s6          // 3 / -7 = 0
  rem    a5, s7, s6          // 3
  CHECK(a5, 3, 9)
  // divide by zero: quotient all ones, remainder = dividend
  div    a6, s5, s0
  CHECK(a6, -1, 10)
  divu   a7, s5, s0
  CHECK(a7, -1, 11)
  rem    t0, s5, s0
  CHECK(t0, 0x12345678, 12)
  remu   t1, s6, s0
  CHECK(t1, -7, 13)
  div    t2, s0, s0
  // signed overflow
  div    t3, s4, s2
  CHECK(t3, 0x80000000, 14)
  rem    t4, s4, s2
  CHECK(t4, 0, 15)
  divu   t5, s4, s2          // unsigned: 0x80000000 / 0xffffffff = 0
  CHECK(t5, 0, 16)
  remu   t6, s4, s2
  // more values
  div    a0, s3, s1
  div    a1, s4, s1
  divu   a2, s2, s1
  rem    a3, s3, s7
  divu   a4, s5, s7
  remu   a5, s5, s7
  div    a6, s4, s7
  rem    a7, s4, s7
  // back-to-back divides and a divide followed by a dependent multiply
  div    t0, s5, s7
  div    t1, t0, s7
  mul    t2, t1, s7
  rem    t3, s5, s5
  CHECK(t3, 0, 17)
  // divide result into a branch
  divu   t4, s7, s7
  beqz   t4, fail
  PASS
fail:
  FAIL(99)
