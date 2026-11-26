// Every load and store size at every legal byte offset, sign and zero extension,
// and store-then-load of the same address.
#include "test.h"
  .text
  .globl test_main
test_main:
  la   s0, buf
  li   s1, 0x80c1e2f3
  sw   s1, 0(s0)
  sw   s1, 4(s0)
  // byte loads at offsets 0-3
  lb   a0, 0(s0)
  CHECK(a0, 0xfffffff3, 1)
  lb   a1, 1(s0)
  lb   a2, 2(s0)
  lb   a3, 3(s0)
  CHECK(a3, 0xffffff80, 2)
  lbu  a4, 0(s0)
  CHECK(a4, 0xf3, 3)
  lbu  a5, 1(s0)
  lbu  a6, 2(s0)
  lbu  a7, 3(s0)
  // half loads at offsets 0 and 2
  lh   t0, 0(s0)
  lh   t1, 2(s0)
  CHECK(t1, 0xffff80c1, 4)
  lhu  t2, 0(s0)
  lhu  t3, 2(s0)
  CHECK(t3, 0x80c1, 5)
  lw   t4, 4(s0)
  // byte stores at offsets 0-3, then read back the word
  li   t5, 0x11
  sb   t5, 8(s0)
  li   t5, 0x22
  sb   t5, 9(s0)
  li   t5, 0x33
  sb   t5, 10(s0)
  li   t5, 0x144             // only the low byte (0x44) is stored
  sb   t5, 11(s0)
  lw   t6, 8(s0)
  li   s2, 0x44332211
  bne  t6, s2, fail
  // half stores at offsets 0 and 2
  li   t5, 0xbeef
  sh   t5, 12(s0)
  li   t5, 0x1dead
  sh   t5, 14(s0)
  lw   a0, 12(s0)
  li   s2, 0xdeadbeef
  bne  a0, s2, fail
  // negative offsets
  addi s3, s0, 16
  sw   s1, -4(s3)
  lw   a1, -4(s3)
  bne  a1, s1, fail
  // store then load the same address right away
  li   a2, 0x5a5a5a5a
  sw   a2, 16(s0)
  lw   a3, 16(s0)
  bne  a3, a2, fail
  sb   zero, 17(s0)
  lw   a4, 16(s0)
  li   s2, 0x5a5a005a
  bne  a4, s2, fail
  // load into x0 does nothing
  lw   x0, 0(s0)
  PASS
fail:
  FAIL(99)

  .data
  .align 4
buf: .space 64
