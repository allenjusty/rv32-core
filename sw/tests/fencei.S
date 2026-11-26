// FENCE.I refetches, so a store to an instruction followed by FENCE.I runs the new
// instruction. Also FENCE (a no-op) and WFI (a no-op).
#include "test.h"
  .text
  .globl test_main
test_main:
  fence
  fence rw, rw
  wfi                          // a no-op (Spike runs with --wfi-as-nop to match)
  li   a0, 0
  la   t0, patch
  li   t1, 0x00500513          // addi a0, x0, 5
  sw   t1, 0(t0)
  fence.i
patch:
  addi a0, x0, 1               // replaced by addi a0, x0, 5
  CHECK(a0, 5, 1)
  PASS
