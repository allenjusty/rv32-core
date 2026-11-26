// Start-up code for the directed tests.
// Spike's boot ROM leaves some registers non-zero, so every register is cleared first.
// The default trap handler skips the trapping instruction (mepc + 4) and counts traps
// in mscratch; a test may install its own handler.
#include "test.h"

  .section .text.init
  .globl _start
_start:
  li x1, 0;  li x2, 0;  li x3, 0;  li x4, 0;  li x5, 0;  li x6, 0;  li x7, 0
  li x8, 0;  li x9, 0;  li x10, 0; li x11, 0; li x12, 0; li x13, 0; li x14, 0
  li x15, 0; li x16, 0; li x17, 0; li x18, 0; li x19, 0; li x20, 0; li x21, 0
  li x22, 0; li x23, 0; li x24, 0; li x25, 0; li x26, 0; li x27, 0; li x28, 0
  li x29, 0; li x30, 0; li x31, 0
  la   sp, _stack_top
  la   t0, default_trap_handler
  csrw mtvec, t0
  csrw mscratch, x0
  j    test_main

  .align 2
  .weak default_trap_handler
default_trap_handler:
  csrrw t6, mscratch, t6      // t6 <-> mscratch (trap count)
  addi  t6, t6, 1
  csrrw t6, mscratch, t6
  csrrw t6, mepc, t6          // swap again to get mepc without losing t6
  addi  t6, t6, 4
  csrrw t6, mepc, t6
  mret

  .section .tohost, "aw", @progbits
  .align 6
  .globl tohost
tohost:   .dword 0
  .align 6
  .globl fromhost
fromhost: .dword 0
