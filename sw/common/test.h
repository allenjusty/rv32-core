// Macros shared by the directed assembly tests.
// Every test: includes this file, defines `test_main`, and ends with PASS or FAIL(n).
#ifndef TEST_H
#define TEST_H

#define PASS             \
  li   a0, 1;            \
  la   t0, tohost;       \
  sw   a0, 0(t0);        \
1: j 1b

#define FAIL(code)               \
  li   a0, ((code) << 1) | 1;    \
  la   t0, tohost;               \
  sw   a0, 0(t0);                \
1: j 1b

// Check a register against a value; on mismatch fail with `code`
#define CHECK(reg, val, code)    \
  li   t6, val;                  \
  beq  reg, t6, 9f;              \
  FAIL(code);                    \
9:

#endif
