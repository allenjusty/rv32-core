#!/usr/bin/env bash
# Mutation check: does the test suite catch real bugs?
# Each mutant is a copy of the RTL with one deliberate bug. It is built on the smoke bench
# (same Spike compare and the same assertions as the UVM bench, but it builds in seconds)
# and every directed test runs with zero wait states and with random wait states.
# A mutant is KILLED when at least one run fails. Results: build/mutants/results.txt
#
# Usage: scripts/mutation_test.sh [mutant]     (needs `make sw sw_irq` first)
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=$ROOT/build/mutants
mkdir -p "$OUT"
: > "$OUT/results.txt"

# name # file # sed expression   (fields separated by #)
# (Left out: letting an interrupted CSR instruction write its CSR. It is an equivalent
#  mutant: the CSR unit already gives the trap priority over the write, so nothing changes.)
MUTANTS=(
  "no_exmem_fwd#core_top.sv#s/if (mem_fwd_ok \&\& mem_rd == ex_rs1)     fwd_a = mem_result;/if (1'b0) fwd_a = mem_result;/"
  "no_load_use_stall#core_top.sv#s/assign load_use = ex_valid \&\& ex_ctrl.is_load/assign load_use = 1'b0 \&\& ex_ctrl.is_load/"
  "no_operand_refresh#core_top.sv#s/      ex_a <= fwd_a;                  \/\/ keep forwarded values: their producers move on/      ;/"
  "mulh_low_half#core_mul.sv#s/assign y = (op == 2'b00) ? prod\[31:0\] : prod\[63:32\];/assign y = prod[31:0];/"
  "div0_quotient_0#core_div.sv#s/is_rem ? a_orig : 32'hFFFF_FFFF/is_rem ? a_orig : 32'h0/"
  "no_taken_fix#core_top.sv#s/(br_taken != ex_pred_taken)/(br_taken \&\& !ex_pred_taken)/"
  "id_redirect_misaligned#core_top.sv#s/assign id_redirect   = id_fire \&\& !id_exc \&\& !id_target\[1\] \&\&/assign id_redirect   = id_fire \&\& !id_exc \&\&/"
  "held_fetch_not_killed#core_top.sv#s/assign f_kill_now     = redirect_any || (f_hold \&\& f_hold_kill);/assign f_kill_now     = redirect_any;/"
  "csrrs_x0_writes#core_csr.sv#s/assign writes = (csr_op == 2'b01) || !csr_src_x0;/assign writes = 1'b1;/"
  "mret_mpie_0#core_csr.sv#s/        mstatus_mpie <= 1'b1;/        mstatus_mpie <= 1'b0;/"
  "lb_zero_extend#core_top.sv#s/      3'b000:  wb_value = {{24{ld_shift\[7\]}},  ld_shift\[7:0\]};    \/\/ LB/      3'b000:  wb_value = {24'b0, ld_shift[7:0]};/"
  "store_be_no_shift#core_top.sv#s/dmem_req_be = 4'b0001 << mem_addr\[1:0\];/dmem_req_be = 4'b0001;/"
  "irq_mepc_plus4#core_top.sv#s/.trap_en(mem_trap), .trap_cause, .trap_pc(mem_pc),/.trap_en(mem_trap), .trap_cause, .trap_pc(irq_take ? mem_pc + 32'd4 : mem_pc),/"
  "irq_timer_first#core_csr.sv#s/if (irq_en_bits\[11\])     irq_cause = 32'h8000_000B;/if (irq_en_bits[7])      irq_cause = 32'h8000_0007;\n    else if (irq_en_bits[11]) irq_cause = 32'h8000_000B;/"
  "irq_ignores_mie#core_csr.sv#s/assign irq_en_bits = mip \& {20'b0, mie_q};/assign irq_en_bits = mip;/"
  "irq_withdraws_dreq#core_top.sv#s/assign irq_take = mem_valid \&\& irq_pending \&\& !mem_d_req \&\& !mem_d_acc;/assign irq_take = mem_valid \&\& irq_pending;/"
  "vector_no_shift#core_csr.sv#s/{26'b0, trap_cause\[3:0\], 2'b00}/{28'b0, trap_cause[3:0]}/"
)

WAITS="+IREADY_PCT=40 +ILAT_MAX=3 +DREADY_PCT=40 +DLAT_MAX=3"
DWAITS="+DREADY_PCT=50 +DLAT_MAX=3"      # data port only: the fetch side runs ahead
TESTS=$(ls build/sw/*.trace | xargs -n1 basename | sed 's/\.trace$//' | grep -v '^dv_\|^coremark$')
IRQ_TESTS=$(ls build/sw_irq/*.hex 2>/dev/null | xargs -n1 basename | sed 's/\.hex$//')

run_mutant() {
  IFS='#' read -r name file expr <<< "$1"
  D="$OUT/$name"
  mkdir -p "$D"
  cp -r Makefile rtl tb sw scripts "$D/"
  sed -i "$expr" "$D/rtl/$file"
  if diff -q "rtl/$file" "$D/rtl/$file" > /dev/null; then
    echo "$name: mutation did not apply" >> "$OUT/results.txt"; return
  fi
  if ! (cd "$D" && make -s smoke > build.log 2>&1); then
    echo "$name: build failed" >> "$OUT/results.txt"; return
  fi
  local killed_by=""
  for t in $TESTS; do
    for args in "" "$WAITS +verilator+seed+1" "$WAITS +verilator+seed+2" "$DWAITS +verilator+seed+3"; do
      R="$D/run_$t"; mkdir -p "$R"
      (cd "$R" && timeout 120 ../build/smoke_bht1/sim +HEX=$ROOT/build/sw/$t.hex \
         +TOHOST=$(cat $ROOT/build/sw/$t.tohost) +TRACE=rtl.trace $args > sim.log 2>&1)
      # how it was caught: an SVA assertion, the program's own check, the watchdog, or Spike
      local w=${args:+, with waits}
      if grep -q "u_sva\.a_" "$R/sim.log"; then
        killed_by="$t ($(grep -m1 -o 'u_sva\.a_[a-z0-9_]*' "$R/sim.log" | cut -d. -f2) assertion$w)"; break 2
      elif grep -q "tohost = " "$R/sim.log"; then
        killed_by="$t (program self-check: $(grep -m1 -o 'code [0-9]*' "$R/sim.log")$w)"; break 2
      elif grep -q "no instruction retired" "$R/sim.log"; then
        killed_by="$t (watchdog: hang$w)"; break 2
      fi
      if ! python3 scripts/compare_trace.py build/sw/$t.trace "$R/rtl.trace" > "$R/compare.log" 2>&1; then
        killed_by="$t (Spike compare${args:+, with waits})"; break 2
      fi
    done
  done
  # self-checking random-interrupt programs (no Spike trace)
  if [ -z "$killed_by" ]; then
    for t in $IRQ_TESTS; do
      for args in "+IRQ_EXT_PM=2 +IRQ_TMR_PM=2 +verilator+seed+1" "+IRQ_EXT_PM=10 +IRQ_TMR_PM=5 $WAITS +verilator+seed+2"; do
        R="$D/run_$t"; mkdir -p "$R"
        (cd "$R" && timeout 300 ../build/smoke_bht1/sim +HEX=$ROOT/build/sw_irq/$t.hex \
           +TOHOST=$(cat $ROOT/build/sw_irq/$t.tohost) +MAX_CYCLES=20000000 $args > sim.log 2>&1)
        if grep -q "u_sva\.a_" "$R/sim.log"; then
          killed_by="$t ($(grep -m1 -o 'u_sva\.a_[a-z0-9_]*' "$R/sim.log" | cut -d. -f2) assertion)"; break 2
        elif ! grep -q "TEST PASSED" "$R/sim.log"; then
          killed_by="$t (program self-check: $(grep -m1 -o 'code [0-9]*\|no instruction retired\|MAX_CYCLES' "$R/sim.log"))"; break 2
        fi
      done
    done
  fi
  if [ -n "$killed_by" ]; then
    printf "%-24s KILLED    by %s\n" "$name" "$killed_by" >> "$OUT/results.txt"
  else
    printf "%-24s SURVIVED\n" "$name" >> "$OUT/results.txt"
  fi
}

ONLY=${1:-}
for m in "${MUTANTS[@]}"; do
  [ -n "$ONLY" ] && [ "${m%%#*}" != "$ONLY" ] && continue
  run_mutant "$m"          # one at a time: builds share the machine's memory
done
echo "DONE" >> "$OUT/results.txt"
cat "$OUT/results.txt"
