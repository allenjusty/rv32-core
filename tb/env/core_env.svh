// Environment: retire monitor -> scoreboard, tohost monitor, coverage.
class core_env extends uvm_env;
  `uvm_component_utils(core_env)

  retire_monitor   mon;
  spike_scoreboard sb;
  tohost_monitor   th;
  core_coverage    cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    mon = retire_monitor::type_id::create("mon", this);
    sb  = spike_scoreboard::type_id::create("sb", this);
    th  = tohost_monitor::type_id::create("th", this);
    cov = core_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    mon.ap.connect(sb.analysis_export);
    mon.ap.connect(th.analysis_export);
    mon.ap.connect(cov.analysis_export);
  endfunction
endclass
