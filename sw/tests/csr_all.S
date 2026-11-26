// Every implemented CSR with all six CSR instructions (CSRRW, CSRRS, CSRRC and the
// immediate forms), each once with a write and once without (rs1 / uimm = 0).
// Read-only CSRs trap on the writes (counted by the default handler).
// Values are chosen so that nothing harmful is written: mstatus.MIE stays 0, mtvec is
// restored at once, and misa / mip only see writes that leave them unchanged in Spike.
#include "test.h"

// all six forms; WVAL = register value, IMM = immediate for the write forms
#define CSR_ALL(csr, WVAL, IMM)   \
  li     t0, WVAL;                \
  csrrw  t1, csr, t0;             \
  csrrs  t1, csr, t0;             \
  csrrs  t1, csr, x0;             \
  csrrc  t1, csr, t0;             \
  csrrc  x0, csr, x0;             \
  csrrwi t1, csr, IMM;            \
  csrrsi t1, csr, IMM;            \
  csrrsi t1, csr, 0;              \
  csrrci t1, csr, IMM;            \
  csrrci t1, csr, 0;              \
  li     t1, 0

  .text
  .globl test_main
test_main:
  la   s0, default_trap_handler
  CSR_ALL(mstatus,  0x00000080, 0x10)     // MPIE only, never MIE
  CSR_ALL(mstatush, 0xffffffff, 0x1f)
  // misa: Spike clears the M bit on any write with bit 12 = 0, so only writes that keep
  // the value are used, and CSRRWI (which can only write bits 4:0) is left out.
  li     t0, 0x40001100
  csrrw  t1, misa, t0
  csrrs  t1, misa, t0
  csrrs  t1, misa, x0
  li     t0, 0
  csrrc  t1, misa, t0
  csrrc  x0, misa, x0
  csrrsi t1, misa, 0x1f                   // A-E are not supported: no change
  csrrsi t1, misa, 0
  csrrci t1, misa, 0x1f
  csrrci t1, misa, 0
  CSR_ALL(mie,      0xffffffff, 0x1f)
  csrw   mie, x0
  CSR_ALL(mtvec,    0x80000101, 0x1d)
  csrw   mtvec, s0
  CSR_ALL(mscratch, 0x12345678, 0x15)
  CSR_ALL(mepc,     0x80000123, 0x1f)
  CSR_ALL(mcause,   0x8000000b, 0x0b)
  CSR_ALL(mtval,    0xdeadbeef, 0x11)
  CSR_ALL(mip,      0x00000000, 0x00)
  CSR_ALL(mcycle,   0x00001000, 0x10)
  CSR_ALL(mcycleh,  0x00000000, 0x00)
  CSR_ALL(minstret, 0x00002000, 0x10)
  CSR_ALL(minstreth,0x00000000, 0x00)
  // read-only: every write form traps (6 per CSR: a non-zero value or immediate)
  csrw   mscratch, x0                     // reset the trap count
  CSR_ALL(mvendorid, 1, 1)
  CSR_ALL(marchid,   1, 1)
  CSR_ALL(mimpid,    1, 1)
  CSR_ALL(mhartid,   1, 1)
  CSR_ALL(0xf15,     1, 1)
  csrr   t2, mscratch
  li     t3, 30                           // 6 write forms x 5 CSRs
  bne    t2, t3, fail
  PASS
fail:
  FAIL(99)
