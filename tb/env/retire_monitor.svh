// Samples the retirement trace (WB) and trap record (MEM) every clock and publishes
// core_rec objects. If both appear in one cycle the WB record goes first: it is older.
class retire_monitor extends uvm_monitor;
  `uvm_component_utils(retire_monitor)

  virtual core_tb_if         vif;
  uvm_analysis_port #(core_rec) ap;
  longint unsigned           n_retired, n_traps;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual core_tb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "core_tb_if not set")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (!vif.rst_n) continue;
      if (vif.tr_valid) begin
        core_rec r = core_rec::type_id::create("r");
        r.pc        = vif.tr_pc;
        r.insn      = vif.tr_insn;
        r.rd_we     = vif.tr_rd_we;
        r.rd        = vif.tr_rd;
        r.rd_val    = vif.tr_rd_val;
        r.st_valid  = vif.tr_st_valid;
        r.st_addr   = vif.tr_st_addr;
        r.st_data   = vif.tr_st_data;
        r.st_size   = vif.tr_st_size;
        r.csr_valid = vif.tr_csr_valid;
        r.csr_addr  = vif.tr_csr_addr;
        r.csr_val   = vif.tr_csr_val;
        n_retired++;
        ap.write(r);
      end
      if (vif.trap_valid) begin
        core_rec t = core_rec::type_id::create("t");
        t.is_trap = 1;
        t.cause   = vif.trap_cause;
        t.epc     = vif.trap_epc;
        t.tval    = vif.trap_tval;
        n_traps++;
        ap.write(t);
      end
    end
  endtask
endclass
