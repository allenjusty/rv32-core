/* 1 MiB of RAM at 0x8000_0000, same as Spike's -m0x80000000:0x100000 */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 1M }
SECTIONS {
  .text.init : { *(.text.init) } > RAM
  .text      : { *(.text*) } > RAM
  . = ALIGN(0x1000);
  .tohost    : { *(.tohost) } > RAM
  .data      : { *(.data*) *(.sdata*) *(.rodata*) *(.srodata*) } > RAM
  .bss       : { _bss_start = .; *(.bss*) *(.sbss*) *(COMMON) } > RAM
  . = ALIGN(16);
  _end = .;
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
