// RV32I ALU instructions with edge-case operands (0, 1, -1, max, min).
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

  // register-register
  add  a0, s3, s1        // overflow wraps to min
  CHECK(a0, 0x80000000, 1)
  sub  a1, s4, s1
  CHECK(a1, 0x7fffffff, 2)
  sub  a2, s0, s2
  and  a3, s5, s2
  or   a4, s5, s4
  xor  a5, s5, s2
  slt  a6, s4, s3
  CHECK(a6, 1, 3)
  sltu a7, s4, s3
  CHECK(a7, 0, 4)
  slt  t0, s2, s0
  sltu t1, s2, s0
  sll  t2, s5, s5        // shift amount = low 5 bits (24)
  srl  t3, s4, s2        // shift by 31
  sra  t4, s4, s2
  CHECK(t4, -1, 5)
  sra  t5, s5, s1
  sll  a0, s2, s0

  // immediates
  addi a0, s3, 1
  addi a1, s0, -2048
  addi a2, s0, 2047
  slti a3, s2, 0
  sltiu a4, s0, -1       // 0 < 0xffffffff unsigned
  CHECK(a4, 1, 6)
  xori a5, s5, -1
  ori  a6, s4, 0x7ff
  andi a7, s5, 0xf0
  slli t0, s1, 31
  srli t1, s4, 31
  srai t2, s4, 31
  srai t3, s5, 0
  lui  t4, 0xfffff
  auipc t5, 0
  auipc t6, 0xfffff

  // results into x0 are dropped
  add  x0, s5, s5
  addi x0, x0, 5
  bne  x0, zero, fail
  // the same register as source and destination
  addi s6, s5, 0
  add  s6, s6, s6
  sub  s6, s6, s6
  CHECK(s6, 0, 7)
  PASS
fail:
  FAIL(99)
