// Tests. The program comes from plusargs (+HEX, +EXP, +TOHOST); the test picks the
// memory timing. The regression runs every program under each test with many seeds.
package core_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import core_env_pkg::*;

  // Zero wait states: the textbook pipeline timing
  class core_base_test extends uvm_test;
    `uvm_component_utils(core_base_test)

    core_env           env;
    core_cfg           cfg;
    virtual core_tb_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    // Spike compare on (overridden by the random-interrupt test)
    virtual function void set_compare();
      cfg.compare = 1;
    endfunction

    // Memory timing for this test (overridden by the wait-state tests)
    virtual function void set_waits();
      cfg.iready_pct = 0; cfg.ilat_max = 0; cfg.dready_pct = 0; cfg.dlat_max = 0;
    endfunction

    function void build_phase(uvm_phase phase);
      cfg = core_cfg::type_id::create("cfg");
      set_compare();
      if (cfg.compare && !$value$plusargs("EXP=%s", cfg.exp_trace))
        `uvm_fatal("ARGS", "+EXP=<expected trace> missing")
      if (!$value$plusargs("TOHOST=%h", cfg.tohost_addr)) `uvm_fatal("ARGS", "+TOHOST=<hex address> missing")
      void'($value$plusargs("WATCHDOG=%d", cfg.watchdog_cycles));
      void'($value$plusargs("MAX_CYCLES=%d", cfg.max_cycles));
      set_waits();
      uvm_config_db#(core_cfg)::set(this, "*", "cfg", cfg);
      if (!uvm_config_db#(virtual core_tb_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "core_tb_if not set")
      env = core_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      int idle = 0, cycles = 0;
      phase.raise_objection(this);
      vif.iready_pct = cfg.iready_pct; vif.ilat_max = cfg.ilat_max;
      vif.dready_pct = cfg.dready_pct; vif.dlat_max = cfg.dlat_max;
      vif.irq_ext_pm = cfg.irq_ext_pm; vif.irq_tmr_pm = cfg.irq_tmr_pm;
      `uvm_info("TEST", $sformatf("waits: I not-ready %0d%%, I latency +0..%0d, D not-ready %0d%%, D latency 0..%0d",
                                  cfg.iready_pct, cfg.ilat_max, cfg.dready_pct, cfg.dlat_max), UVM_LOW)
      fork
        env.th.done.wait_trigger();
        // watchdog: fail if nothing retires for watchdog_cycles, or the run is too long
        forever begin
          @(posedge vif.clk);
          cycles++;
          idle = vif.tr_valid ? 0 : idle + 1;
          if (idle > cfg.watchdog_cycles)
            `uvm_fatal("WATCHDOG", $sformatf("no instruction retired for %0d cycles", idle))
          if (cycles > cfg.max_cycles)
            `uvm_fatal("WATCHDOG", $sformatf("test ran longer than %0d cycles", cfg.max_cycles))
        end
        // stop at the first mismatch
        forever begin
          @(posedge vif.clk);
          if (env.sb.failed) break;
        end
      join_any
      disable fork;
      repeat (5) @(posedge vif.clk);
      `uvm_info("TEST", $sformatf("%0d instructions retired, %0d traps", env.mon.n_retired, env.mon.n_traps), UVM_LOW)
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      uvm_report_server rs = uvm_report_server::get_server();
      if (rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0 && env.sb.all_matched())
        $display("TEST PASSED");
      else
        $display("TEST FAILED");
    endfunction
  endclass

  // Moderate random wait states on both ports
  class core_rand_wait_test extends core_base_test;
    `uvm_component_utils(core_rand_wait_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void set_waits();
      cfg.iready_pct = $urandom_range(10, 50); cfg.ilat_max = $urandom_range(1, 3);
      cfg.dready_pct = $urandom_range(10, 50); cfg.dlat_max = $urandom_range(1, 3);
    endfunction
  endclass

  // Long waits, mostly on one port at a time (fetch-starved or data-starved)
  class core_heavy_wait_test extends core_base_test;
    `uvm_component_utils(core_heavy_wait_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void set_waits();
      if ($urandom_range(1)) begin
        cfg.iready_pct = 80; cfg.ilat_max = 8; cfg.dready_pct = 0;  cfg.dlat_max = 0;
      end else begin
        cfg.iready_pct = 0;  cfg.ilat_max = 0; cfg.dready_pct = 80; cfg.dlat_max = 8;
      end
    endfunction
  endclass
  // Random interrupts plus random wait states, on the self-checking interrupt programs.
  // No Spike compare: the program checks itself, and the assertions check the rules.
  class core_irq_test extends core_base_test;
    `uvm_component_utils(core_irq_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    virtual function void set_compare();
      cfg.compare = 0;
    endfunction
    virtual function void set_waits();
      // a third of the seeds without waits, the rest with random waits
      if ($urandom_range(2) != 0) begin
        cfg.iready_pct = $urandom_range(0, 50); cfg.ilat_max = $urandom_range(0, 3);
        cfg.dready_pct = $urandom_range(0, 50); cfg.dlat_max = $urandom_range(0, 3);
      end
      // from rare to a storm of interrupts
      cfg.irq_ext_pm = $urandom_range(0, 1) ? $urandom_range(1, 5) : $urandom_range(8, 15);
      cfg.irq_tmr_pm = $urandom_range(1, 10);
      `uvm_info("TEST", $sformatf("random interrupts: external %0d, timer %0d per 1000 cycles",
                                  cfg.irq_ext_pm, cfg.irq_tmr_pm), UVM_LOW)
    endfunction
  endclass
endpackage
