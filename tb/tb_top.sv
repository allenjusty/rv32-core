// UVM testbench top: clock, reset, core, memory, interface and run_test().
module tb_top;
  import uvm_pkg::*;
  import core_test_pkg::*;

  logic clk = 1'b0, rst_n = 1'b0;
  always #5ns clk = ~clk;
  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
  end

  core_tb_if vif (clk, rst_n);

  logic        imem_req_valid, imem_req_ready, imem_rsp_valid;
  logic [31:0] imem_req_addr, imem_rsp_rdata;
  logic        dmem_req_valid, dmem_req_ready, dmem_req_we, dmem_rsp_valid;
  logic [31:0] dmem_req_addr, dmem_req_wdata, dmem_rsp_rdata;
  logic [3:0]  dmem_req_be;
  logic        tohost_done;
  logic        irq_software, irq_timer, irq_external;
  logic [31:0] tohost_value;

  core_top #(.BHT_EN(1'b1)) dut (
    .clk, .rst_n,
    .irq_software, .irq_timer, .irq_external,
    .imem_req_valid, .imem_req_ready, .imem_req_addr, .imem_rsp_valid, .imem_rsp_rdata,
    .dmem_req_valid, .dmem_req_ready, .dmem_req_addr, .dmem_req_we, .dmem_req_be,
    .dmem_req_wdata, .dmem_rsp_valid, .dmem_rsp_rdata,
    .tr_valid(vif.tr_valid), .tr_pc(vif.tr_pc), .tr_insn(vif.tr_insn), .tr_rd_we(vif.tr_rd_we),
    .tr_rd(vif.tr_rd), .tr_rd_val(vif.tr_rd_val), .tr_st_valid(vif.tr_st_valid),
    .tr_st_addr(vif.tr_st_addr), .tr_st_data(vif.tr_st_data), .tr_st_size(vif.tr_st_size),
    .tr_csr_valid(vif.tr_csr_valid), .tr_csr_addr(vif.tr_csr_addr), .tr_csr_val(vif.tr_csr_val),
    .trap_valid(vif.trap_valid), .trap_cause(vif.trap_cause), .trap_epc(vif.trap_epc),
    .trap_tval(vif.trap_tval)
  );

  tb_mem u_mem (
    .clk, .rst_n,
    .i_req_valid(imem_req_valid), .i_req_ready(imem_req_ready), .i_req_addr(imem_req_addr),
    .i_rsp_valid(imem_rsp_valid), .i_rsp_rdata(imem_rsp_rdata),
    .d_req_valid(dmem_req_valid), .d_req_ready(dmem_req_ready), .d_req_addr(dmem_req_addr),
    .d_req_we(dmem_req_we), .d_req_be(dmem_req_be), .d_req_wdata(dmem_req_wdata),
    .d_rsp_valid(dmem_rsp_valid), .d_rsp_rdata(dmem_rsp_rdata),
    .tohost_done, .tohost_value,
    .iready_pct(vif.iready_pct), .ilat_max(vif.ilat_max),
    .dready_pct(vif.dready_pct), .dlat_max(vif.dlat_max),
    .irq_ext_pm(vif.irq_ext_pm), .irq_tmr_pm(vif.irq_tmr_pm),
    .irq_software, .irq_timer, .irq_external
  );

  // Pipeline probes for coverage
  assign vif.id_fire       = dut.id_fire;
  assign vif.id_wait_fetch = dut.id_valid && !dut.id_bits_ok;
  assign vif.load_use      = dut.load_use;
  assign vif.id_ctrl       = dut.id_ctrl;
  assign vif.bht_cnt       = dut.bht_cnt;
  assign vif.ex_valid      = dut.ex_valid;
  assign vif.ex_fire       = dut.ex_fire;
  assign vif.ex_any_exc    = dut.ex_any_exc;
  assign vif.br_taken      = dut.br_taken;
  assign vif.ex_pred_taken = dut.ex_pred_taken;
  assign vif.ex_ctrl       = dut.ex_ctrl;
  assign vif.ex_pc         = dut.ex_pc;
  assign vif.ex_instr      = dut.ex_instr;
  assign vif.ex_imm        = dut.ex_imm;
  assign vif.fwd_a         = dut.fwd_a;
  assign vif.fwd_b         = dut.fwd_b;
  assign vif.alu_y         = dut.alu_y;
  assign vif.mem_fwd_ok    = dut.mem_fwd_ok;
  assign vif.wb_fwd_ok     = dut.wb_fwd_ok;
  assign vif.mem_instr_p   = dut.mem_instr;
  assign vif.wb_instr_p    = dut.wb_instr;
  assign vif.mem_ctrl_p    = dut.mem_ctrl;
  assign vif.wb_ctrl_p     = dut.wb_ctrl;
  assign vif.div_busy      = dut.div_busy;
  assign vif.div_start     = dut.div_start;
  assign vif.flush_ex      = dut.flush_ex;
  assign vif.mem_valid     = dut.mem_valid;
  assign vif.mem_stall     = dut.mem_stall;
  assign vif.mem_exc       = dut.mem_exc;
  assign vif.csr_en        = dut.csr_en;
  assign vif.csr_illegal   = dut.csr_illegal;
  assign vif.fetch_wait    = dut.f_hold || (dut.f_out && !imem_rsp_valid);
  assign vif.div_busy_any  = dut.div_busy;
  assign vif.irq_take      = dut.irq_take;
  assign vif.irq_pending   = dut.irq_pending;
  assign vif.mtvec_vectored = dut.u_csr.mtvec_q[0];
  assign vif.mem_ctrl_irq  = dut.mem_ctrl;

  initial begin
    uvm_config_db#(virtual core_tb_if)::set(null, "*", "vif", vif);
    if ($test$plusargs("DUMP")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top);
    end
    run_test();
  end
endmodule
