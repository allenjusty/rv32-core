// One interface between the UVM bench and the core:
//  - the retirement trace (WB) and trap record (MEM)
//  - the memory wait-state knobs (written by the test)
//  - pipeline probes for functional coverage (driven from tb_top with hierarchical names)
interface core_tb_if (input logic clk, input logic rst_n);
  import core_pkg::*;

  // retirement trace
  logic        tr_valid, tr_rd_we, tr_st_valid, tr_csr_valid;
  logic [31:0] tr_pc, tr_insn, tr_rd_val, tr_st_addr, tr_st_data, tr_csr_val;
  logic [4:0]  tr_rd;
  logic [1:0]  tr_st_size;
  logic [11:0] tr_csr_addr;
  // trap record
  logic        trap_valid;
  logic [31:0] trap_cause, trap_epc, trap_tval;

  // memory and interrupt knobs
  int iready_pct = 0, ilat_max = 0, dready_pct = 0, dlat_max = 0;
  int irq_ext_pm = 0, irq_tmr_pm = 0;

  // ---- probes (coverage only)
  // ID
  logic        id_fire, id_wait_fetch, load_use;
  ctrl_t       id_ctrl;
  logic [1:0]  bht_cnt;
  // EX
  logic        ex_valid, ex_fire, ex_any_exc, br_taken, ex_pred_taken;
  ctrl_t       ex_ctrl;
  logic [31:0] ex_pc, ex_instr, ex_imm, fwd_a, fwd_b, alu_y;
  logic        mem_fwd_ok, wb_fwd_ok;
  logic [31:0] mem_instr_p, wb_instr_p;
  ctrl_t       mem_ctrl_p, wb_ctrl_p;
  logic        div_busy, div_start, flush_ex;
  // MEM
  logic        mem_valid, mem_stall, mem_exc, csr_en, csr_illegal;
  // fetch
  logic        fetch_wait;    // a fetch request held or a response not back yet
  // interrupts
  logic        irq_take, irq_pending, mtvec_vectored, div_busy_any;
  ctrl_t       mem_ctrl_irq;
endinterface
