// Watches retired stores for the write to tohost: 1 = pass, else fail with code = value >> 1.
// The test waits on `done` to end.
class tohost_monitor extends uvm_subscriber #(core_rec);
  `uvm_component_utils(tohost_monitor)

  core_cfg   cfg;
  uvm_event  done;
  bit [31:0] value;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    done = new("done");
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(core_cfg)::get(this, "", "cfg", cfg)) `uvm_fatal("NOCFG", "no cfg")
  endfunction

  function void write(core_rec t);
    if (t.is_trap || !t.st_valid || t.st_addr != cfg.tohost_addr || done.is_on()) return;
    value = t.st_data;
    if (value != 1)
      `uvm_error("TOHOST", $sformatf("test program reported failure: tohost = %0d (code %0d)", value, value >> 1))
    else
      `uvm_info("TOHOST", "test program wrote 1 to tohost (pass)", UVM_LOW)
    done.trigger();
  endfunction
endclass
