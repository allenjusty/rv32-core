// Run configuration, filled from plusargs by the base test.
class core_cfg extends uvm_object;
  `uvm_object_utils(core_cfg)

  string     exp_trace;          // +EXP=<expected trace from Spike>
  bit        compare = 1;        // 0: no Spike compare (random-interrupt programs)
  bit [31:0] tohost_addr;        // +TOHOST=<hex>
  int        watchdog_cycles = 5000;    // fail if nothing retires for this long
  int        max_cycles      = 200_000_000;   // CoreMark with wait states needs ~20M
  // memory wait states (set by the test)
  int        iready_pct, ilat_max, dready_pct, dlat_max;
  // random interrupt lines (per mille per cycle; 0 = off)
  int        irq_ext_pm, irq_tmr_pm;

  function new(string name = "core_cfg");
    super.new(name);
  endfunction
endclass
