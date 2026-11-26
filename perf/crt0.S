// C start-up for the CPI runs: stack, clear .bss, call main, report through tohost.
  .section .text.init
  .globl _start
_start:
  la   sp, _stack_top
  la   t0, _bss_start
  la   t1, _end
1:
  bgeu t0, t1, 2f
  sw   zero, 0(t0)
  addi t0, t0, 4
  j    1b
2:
  call main
  slli a0, a0, 1          // main's return value 0 -> tohost = 1 (pass)
  ori  a0, a0, 1
  la   t0, tohost
  sw   a0, 0(t0)
3: j 3b

  .section .tohost, "aw", @progbits
  .align 6
  .globl tohost
tohost:   .dword 0
  .align 6
  .globl fromhost
fromhost: .dword 0
