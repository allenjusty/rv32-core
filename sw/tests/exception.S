// Every exception cause (mcause 0, 2, 3, 4, 6, 11), with the default handler that
// skips the trapping instruction and counts traps in mscratch. Also: illegal words
// on a wrong path (must not trap), a trap inside a trap handler, and rd / memory
// left unchanged by a trapping instruction.
#include "test.h"
  .text
  .globl test_main
test_main:
  la   s0, buf
  li   s1, 0x11223344
  sw   s1, 0(s0)
  li   s11, 0                  // expected trap count

  // ---- illegal instruction (mcause 2), found in ID
  .word 0xffffffff;  addi s11, s11, 1
  .word 0x00000000;  addi s11, s11, 1     // all zeros
  .word 0x00004501;  addi s11, s11, 1     // a 16-bit encoding (C is not supported)
  .word 0x40001033;  addi s11, s11, 1     // SLL with funct7 = 0100000
  .word 0x02001013;  addi s11, s11, 1     // SLLI with bit 25 set (RV64 shamt)
  .word 0x10200073;  addi s11, s11, 1     // SRET
  .word 0x00002063;  addi s11, s11, 1     // branch funct3 = 010
  .word 0x00003003;  addi s11, s11, 1     // LD (RV64)
  .word 0x00003023;  addi s11, s11, 1     // SD (RV64)
  .word 0x00001067;  addi s11, s11, 1     // JALR funct3 = 001
  .word 0x0000200f;  addi s11, s11, 1     // MISC-MEM funct3 = 010
  .word 0x0000402f;  addi s11, s11, 1     // AMO (A not supported)
  .word 0x00004073;  addi s11, s11, 1     // SYSTEM funct3 = 100
  // ---- illegal CSR accesses (mcause 2), found in MEM
  li   t0, 7
  csrr t0, 0x7c0;    addi s11, s11, 1     // CSR that does not exist
  CHECK(t0, 7, 1)                         // rd unchanged
  csrw mvendorid, t0; addi s11, s11, 1    // write to a read-only CSR
  csrrs t1, marchid, t0; addi s11, s11, 1 // set with rs1 != x0 is a write too
  csrrsi t1, mhartid, 1; addi s11, s11, 1

  // ---- ECALL (11) and EBREAK (3)
  ecall;             addi s11, s11, 1
  ebreak;            addi s11, s11, 1

  // ---- load / store misaligned (4 / 6), found in EX
  li   t2, 99
  lh   t2, 1(s0);    addi s11, s11, 1
  lhu  t2, 3(s0);    addi s11, s11, 1
  lh   t2, 3(s0);    addi s11, s11, 1
  lhu  t2, 1(s0);    addi s11, s11, 1
  lw   t2, 1(s0);    addi s11, s11, 1
  lw   t2, 2(s0);    addi s11, s11, 1
  lw   t2, 3(s0);    addi s11, s11, 1
  CHECK(t2, 99, 2)
  sh   s1, 1(s0);    addi s11, s11, 1
  sw   s1, 2(s0);    addi s11, s11, 1
  sw   s1, 3(s0);    addi s11, s11, 1
  sh   s1, 3(s0);    addi s11, s11, 1
  sw   s1, 1(s0);    addi s11, s11, 1
  lw   t3, 0(s0)
  CHECK(t3, 0x11223344, 3)                // memory unchanged

  // ---- instruction address misaligned (0), found in EX, reported on the jump
  la   t4, 1f
  jalr t5, 2(t4);    addi s11, s11, 1     // target ends in 2
1:
  CHECK(t5, 0, 4)                         // link register not written (t5 was 0 from CHECK)
  .word 0x0060006f;  addi s11, s11, 1     // jal x0, +6
  li   t0, 1
  beq  t0, t0, . + 6; addi s11, s11, 1    // taken branch to a misaligned target
  bne  t0, t0, . + 6                      // not taken: no trap even though the target is misaligned
  la   t4, 2f + 1
  jalr x0, 0(t4)                          // bit 0 is cleared: target 2f is fine
  j    fail
2:
  // ---- wrong-path instructions must not trap
  j    3f
  .word 0xffffffff
  ecall
3:
  beq  zero, zero, 4f                     // taken; next words are on the wrong path
  .word 0x00000000
  lw   t0, 1(s0)
4:
  // ---- a trap in MEM in the cycle a divide starts in EX: the divide is killed
  ecall
  div  t3, t0, t1                         // in EX while the ECALL traps in MEM
  addi s11, s11, 1
  // ---- a trap right after a divide (the divide must complete first)
  li   t0, 100
  li   t1, 7
  div  t2, t0, t1
  ecall;             addi s11, s11, 1
  CHECK(t2, 14, 5)

  // ---- a trap inside a trap handler
  la   t0, outer_handler
  csrw mtvec, t0
  ecall
  la   t0, default_trap_handler
  csrw mtvec, t0
  CHECK(s10, 1, 6)                        // inner trap was taken

  // ---- the count of traps (default handler only)
  csrr t0, mscratch
  bne  t0, s11, fail
  PASS
fail:
  FAIL(99)

  // Handler that itself traps: saves mepc, takes an ECALL to inner_handler,
  // then restores mepc and returns past the outer ECALL.
outer_handler:
  csrr s9, mepc
  la   t6, inner_handler
  csrw mtvec, t6
  ecall                                   // nested trap
  csrw mepc, s9
  csrr t6, mepc
  addi t6, t6, 4
  csrw mepc, t6
  mret
inner_handler:
  li   s10, 1
  csrr t6, mepc
  addi t6, t6, 4
  csrw mepc, t6
  mret

  .data
  .align 4
buf: .space 16
