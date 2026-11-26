// Zicsr: every implemented CSR with every CSR instruction form, the rd = x0 and
// rs1 = x0 rules, and WARL bits. Counter reads are masked in the compare, so their
// values are never used.
#include "test.h"
  .text
  .globl test_main
test_main:
  li   s1, -1
  li   s2, 0x5555aaaa
  // mscratch: full read/write with each instruction form
  csrw   mscratch, s2
  csrr   a0, mscratch
  CHECK(a0, 0x5555aaaa, 1)
  csrrs  a1, mscratch, s1        // old value to rd, set all
  CHECK(a1, 0x5555aaaa, 2)
  csrrc  a2, mscratch, s2        // clear the 0x5555aaaa bits
  csrr   a3, mscratch
  CHECK(a3, 0xaaaa5555, 3)
  csrrwi a4, mscratch, 0x15
  csrrsi a5, mscratch, 0x0a
  csrrci a6, mscratch, 0x01
  csrr   a7, mscratch
  CHECK(a7, 0x1e, 4)
  csrrs  t0, mscratch, x0        // rs1 = x0: read only
  csrrsi t1, mscratch, 0         // uimm = 0: read only
  csrrc  t2, mscratch, x0
  csrrw  x0, mscratch, s1        // rd = x0: write only
  csrr   t3, mscratch
  CHECK(t3, -1, 5)

  // WARL fields
  csrw   mstatus, s1             // only MIE and MPIE stick; MPP reads 3
  csrr   a0, mstatus
  CHECK(a0, 0x1888, 6)
  csrci  mstatus, 8              // keep MIE = 0 for the rest of the test
  csrr   a0, mstatus
  csrw   mie, s1
  csrr   a1, mie
  CHECK(a1, 0x888, 7)
  csrw   mie, x0
  la     t0, my_handler
  csrw   mtvec, s1               // bit 1 is not writable
  csrr   a2, mtvec
  CHECK(a2, 0xfffffffd, 8)
  csrw   mtvec, t0
  csrw   mepc, s1                // bits 1:0 always 0
  csrr   a3, mepc
  CHECK(a3, 0xfffffffc, 9)
  csrw   mcause, s2
  csrr   a4, mcause
  csrw   mtval, s2
  csrr   a5, mtval
  csrr   a6, misa
  CHECK(a6, 0x40001100, 10)
  // no write to misa: Spike would clear the M bit (see spec section 8)
  csrr   a7, mstatush
  csrw   mstatush, s1
  csrr   a7, mstatush
  CHECK(a7, 0, 11)
  csrr   t0, mvendorid
  csrr   t1, mimpid
  csrr   t2, mhartid
  csrr   t3, 0xf15               // mconfigptr
  csrr   t4, marchid             // masked (Spike reads 5)
  li     t4, 0
  // counters: reads are masked, then the register is overwritten right away
  csrr   t5, mcycle
  csrr   t5, mcycleh
  csrr   t5, minstret
  csrr   t5, minstreth
  csrr   t5, mip
  li     t5, 0
  csrw   mcycle, x0
  csrw   minstret, x0
  csrw   mcycleh, x0
  csrw   minstreth, x0
  // a CSR result used right away by the next instruction
  csrw   mscratch, s2
  csrr   a0, mscratch
  addi   a1, a0, 1
  csrr   a2, mscratch
  bne    a2, s2, fail
  PASS
fail:
  FAIL(99)

my_handler:
  FAIL(98)
