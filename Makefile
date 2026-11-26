# RV32IM core - common commands.  Run `source ~/tools/env.sh` first.
#
#   make lint                 Verilator -Wall lint
#   make sw                   build every directed test and its Spike trace
#   make smoke                build the plain-SV bench (fast, no UVM)
#   make run T=alu            run one test on the smoke bench and compare with Spike
#   make run_all              all directed tests on the smoke bench
#   make tb / make test       UVM bench (see below)

PREFIX   ?= riscv-none-elf-
CC       := $(PREFIX)gcc
OBJCOPY  := $(PREFIX)objcopy
NM       := $(PREFIX)nm
SPIKE    ?= spike
MARCH    := -march=rv32im_zicsr_zifencei -mabi=ilp32
CFLAGS   := $(MARCH) -nostdlib -nostartfiles -static -Isw/common -T sw/common/link.ld
SPIKE_FLAGS := --isa=rv32im_zicsr --priv=m --wfi-as-nop -m0x80000000:0x100000 --log-commits -l
SPIKE_MAX ?= 500000
BHT      ?= 1
SEED     ?= 1
BUILD_JOBS ?= 4
export OBJCACHE ?= ccache

TESTS    := $(notdir $(basename $(wildcard sw/tests/*.S)))
SWDIR    := build/sw

.PHONY: lint sw sw_irq smoke run run_all run_irq tb test cpi clean
.SECONDARY:

lint:   ## Verilator lint, all warnings
	verilator --lint-only -Wall --assert rtl/lint.vlt -f rtl/core.f --top-module core_top

# ---------------------------------------------------------------- software + Spike
# test.elf -> test.hex (for the memory model), test.tohost (address), test.trace (Spike)
$(SWDIR)/%.elf: sw/tests/%.S sw/common/crt.S sw/common/test.h sw/common/link.ld
	@mkdir -p $(SWDIR)
	$(CC) $(CFLAGS) sw/common/crt.S $< -o $@

$(SWDIR)/%.hex: $(SWDIR)/%.elf
	$(OBJCOPY) -O verilog --change-addresses=-0x80000000 $< $@

$(SWDIR)/%.tohost: $(SWDIR)/%.elf
	$(NM) $< | awk '/ tohost$$/ {print $$1}' > $@

$(SWDIR)/%.trace: $(SWDIR)/%.elf $(SWDIR)/%.tohost
	timeout 60 $(SPIKE) $(SPIKE_FLAGS) --instructions=$(SPIKE_MAX) --log=$(SWDIR)/$*.spike.log $< ; \
	    test $$? -eq 0 || (echo "spike failed on $*: test bug or SPIKE_MAX too small"; exit 1)
	python3 scripts/spike_log_to_trace.py $(SWDIR)/$*.spike.log $@ --tohost $$(cat $(SWDIR)/$*.tohost)
	@rm -f $(SWDIR)/$*.spike.log

sw: $(foreach t,$(TESTS),$(SWDIR)/$(t).hex $(SWDIR)/$(t).trace)

# ---------------------------------------------------------------- smoke bench
SMOKE_FLAGS := --binary --timing --assert -j $(BUILD_JOBS) -Wno-fatal -Wno-lint -Wno-style \
               -GBHT_EN=$(BHT) rtl/lint.vlt -f rtl/core.f tb/common/tb_mem.sv tb/sva/core_sva.sv \
               tb/smoke/core_smoke_tb.sv --top-module core_smoke_tb

smoke:  ## build the plain-SV bench
	@mkdir -p build
	verilator $(SMOKE_FLAGS) -Mdir build/smoke_bht$(BHT) -o sim > build/smoke_bht$(BHT).log 2>&1 \
	    || (grep -E "%Error" build/smoke_bht$(BHT).log | head -20; exit 1)

T ?= alu
run: $(SWDIR)/$(T).hex $(SWDIR)/$(T).trace  ## run one test on the smoke bench: make run T=alu ARGS="+DREADY_PCT=30"
	@mkdir -p build/runs/$(T)
	cd build/runs/$(T) && ../../smoke_bht$(BHT)/sim +HEX=../../sw/$(T).hex +TOHOST=$$(cat ../../sw/$(T).tohost) \
	    +TRACE=rtl.trace +verilator+seed+$(SEED) $(ARGS) | tee sim.log
	python3 scripts/compare_trace.py $(SWDIR)/$(T).trace build/runs/$(T)/rtl.trace

run_all: sw
	@for t in $(TESTS); do $(MAKE) -s run T=$$t ARGS="$(ARGS)" > /dev/null 2>&1 \
	    && echo "PASS $$t" || echo "FAIL $$t"; done

# ---------------------------------------------------------------- random-interrupt programs
# Self-checking, not compared with Spike (Spike has no random interrupt source).
# build/sw_irq/<name>.{hex,tohost}; run_regression.py runs them under core_irq_test.
IRQ_TESTS := $(notdir $(basename $(wildcard sw/tests_irq/*.S)))
IRQDIR    := build/sw_irq
IRQ_ARGS  ?= +IRQ_EXT_PM=2 +IRQ_TMR_PM=2

$(IRQDIR)/%.elf: sw/tests_irq/%.S sw/common/crt.S sw/common/test.h sw/common/link.ld
	@mkdir -p $(IRQDIR)
	$(CC) $(CFLAGS) sw/common/crt.S $< -o $@
	$(OBJCOPY) -O verilog --change-addresses=-0x80000000 $@ $(IRQDIR)/$*.hex
	$(NM) $@ | awk '/ tohost$$/ {print $$1}' > $(IRQDIR)/$*.tohost

sw_irq: $(foreach t,$(IRQ_TESTS),$(IRQDIR)/$(t).elf)

run_irq: sw_irq   ## make run_irq T=irq_random ARGS="+DREADY_PCT=30"
	@mkdir -p build/runs_irq/$(T)
	cd build/runs_irq/$(T) && ../../smoke_bht$(BHT)/sim +HEX=../../sw_irq/$(T).hex \
	    +TOHOST=$$(cat ../../sw_irq/$(T).tohost) +verilator+seed+$(SEED) $(IRQ_ARGS) $(ARGS) | tee sim.log
	grep -q "TEST PASSED" build/runs_irq/$(T)/sim.log

# ---------------------------------------------------------------- UVM bench
# Build once; the program (+HEX/+EXP/+TOHOST) and the test are chosen at run time.
UVM_HOME ?= $(HOME)/tools/uvm-2017-1.0
TEST     ?= core_base_test
VERB     ?= UVM_LOW
UVM_FLAGS := --binary --timing --vpi --assert --coverage-user --trace-vcd --timescale-override 1ns/1ps \
             -j $(BUILD_JOBS) -Wno-fatal -Wno-lint -Wno-style -Werror-COVERIGN \
             +incdir+$(UVM_HOME) +incdir+$(UVM_HOME)/dpi \
             $(UVM_HOME)/uvm_pkg_all_v2017_1_0_dpi.svh $(UVM_HOME)/dpi/uvm_dpi.cc \
             rtl/lint.vlt -f rtl/core.f -f tb/tb.f --top-module tb_top -Mdir build/uvm -o sim

tb:     ## build the UVM bench (a few minutes)
	@mkdir -p build
	verilator $(UVM_FLAGS) > build/uvm_build.log 2>&1 || (grep -E "%Error" build/uvm_build.log | head -30; exit 1)
	@echo "built build/uvm/sim"

test: $(SWDIR)/$(T).hex $(SWDIR)/$(T).trace   ## make test T=alu TEST=core_rand_wait_test SEED=3
	@mkdir -p build/uvm_runs/$(T)_$(TEST)_$(SEED)
	cd build/uvm_runs/$(T)_$(TEST)_$(SEED) && ../../uvm/sim +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED) \
	    +HEX=../../sw/$(T).hex +EXP=../../sw/$(T).trace +TOHOST=$$(cat ../../sw/$(T).tohost) \
	    +UVM_VERBOSITY=$(VERB) $(ARGS) | tee sim.log

# ---------------------------------------------------------------- CPI (BHT off vs on)
# CoreMark is fetched separately (not part of this repo): git clone https://github.com/eembc/coremark
COREMARK   ?= $(HOME)/tools/coremark
ITERATIONS ?= 20
CM_FLAGS   := -O2 $(MARCH) -nostdlib -nostartfiles -static -T perf/link.ld \
              -DITERATIONS=$(ITERATIONS) -DPERFORMANCE_RUN=1 -DCOMPILER_FLAGS='"-O2 -march=rv32im_zicsr"' \
              -Iperf/port -I$(COREMARK)

build/perf/coremark.elf: perf/crt0.S perf/port/*.c perf/port/*.h perf/link.ld
	@mkdir -p build/perf
	$(CC) $(CM_FLAGS) perf/crt0.S perf/port/*.c $(COREMARK)/core_list_join.c $(COREMARK)/core_main.c \
	    $(COREMARK)/core_matrix.c $(COREMARK)/core_state.c $(COREMARK)/core_util.c -lgcc -o $@
	$(OBJCOPY) -O verilog --change-addresses=-0x80000000 $@ build/perf/coremark.hex
	$(NM) $@ | awk '/ tohost$$/ {print $$1}' > build/perf/coremark.tohost

# CoreMark as a long Spike-compare test (counter reads compiled out, see core_portme.c).
# Spike needs a little memory at the print address 0x4000_0000.
coremark_cmp: perf/crt0.S perf/port/*.c perf/port/*.h perf/link.ld   ## build/sw/coremark.* (~5.8M instructions)
	@mkdir -p $(SWDIR)
	$(CC) $(CM_FLAGS) -DNO_COUNTERS perf/crt0.S perf/port/*.c $(COREMARK)/core_list_join.c $(COREMARK)/core_main.c \
	    $(COREMARK)/core_matrix.c $(COREMARK)/core_state.c $(COREMARK)/core_util.c -lgcc -o $(SWDIR)/coremark.elf
	$(OBJCOPY) -O verilog --change-addresses=-0x80000000 $(SWDIR)/coremark.elf $(SWDIR)/coremark.hex
	$(NM) $(SWDIR)/coremark.elf | awk '/ tohost$$/ {print $$1}' > $(SWDIR)/coremark.tohost
	timeout 600 $(SPIKE) --isa=rv32im_zicsr --priv=m --wfi-as-nop -m0x80000000:0x100000,0x40000000:0x1000 --log-commits -l \
	    --instructions=10000000 --log=$(SWDIR)/coremark.spike.log $(SWDIR)/coremark.elf
	python3 scripts/spike_log_to_trace.py $(SWDIR)/coremark.spike.log $(SWDIR)/coremark.trace \
	    --tohost $$(cat $(SWDIR)/coremark.tohost)
	@rm -f $(SWDIR)/coremark.spike.log

cpi: build/perf/coremark.elf   ## CoreMark with the BHT off and on, zero wait states
	$(MAKE) -s smoke BHT=0
	$(MAKE) -s smoke BHT=1
	for b in 0 1; do \
	  build/smoke_bht$$b/sim +HEX=build/perf/coremark.hex +TOHOST=$$(cat build/perf/coremark.tohost) \
	      +CPI +MAX_CYCLES=200000000 > build/perf/coremark_bht$$b.log || exit 1; \
	done
	python3 scripts/cpi_report.py build/perf/coremark_bht0.log build/perf/coremark_bht1.log > perf/results.md
	cat perf/results.md

clean:
	rm -rf build
