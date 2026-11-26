// Assertions for the core, bound into core_top (so internal signals are visible).
// Kept simple (one implication each) because Verilator supports SVA only in part.
module core_sva
  import core_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  // ports
  input logic        imem_req_valid, imem_req_ready, imem_rsp_valid,
  input logic [31:0] imem_req_addr,
  input logic        dmem_req_valid, dmem_req_ready, dmem_rsp_valid, dmem_req_we,
  input logic [31:0] dmem_req_addr, dmem_req_wdata,
  input logic [3:0]  dmem_req_be,
  // internals
  input logic [31:0] id_rs1val, id_rs2val,
  input logic [4:0]  id_rs1, id_rs2,
  input logic        flush_id, flush_ex, id_valid, ex_valid,
  input logic        div_busy, div_done, div_start,
  input logic        tr_valid, trap_valid,
  input logic [31:0] trap_cause,
  input logic        irq_pending, irq_take, mem_d_req, mem_d_acc,
  input logic [31:0] irq_en_bits,      // mip & mie (from the CSR unit)
  input logic        mem_valid, mem_exc,
  input ctrl_t       mem_ctrl, ex_ctrl,
  input logic [31:0] mem_instr, ex_instr
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // x0 always reads 0
  a_x0_rs1: assert property (id_rs1 == 5'd0 |-> id_rs1val == 32'd0);
  a_x0_rs2: assert property (id_rs2 == 5'd0 |-> id_rs2val == 32'd0);

  // Fetch addresses are 4-byte aligned
  a_fetch_aligned: assert property (imem_req_valid |-> imem_req_addr[1:0] == 2'b00);

  // A request stays stable until it is accepted
  a_i_stable: assert property (imem_req_valid && !imem_req_ready |=> imem_req_valid && $stable(imem_req_addr));
  a_d_stable: assert property (dmem_req_valid && !dmem_req_ready |=>
                               dmem_req_valid && $stable(dmem_req_addr) && $stable(dmem_req_we) &&
                               $stable(dmem_req_be) && $stable(dmem_req_wdata));

  // At most one request outstanding per port
  int i_out, d_out;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      i_out <= 0; d_out <= 0;
    end else begin
      i_out <= i_out + int'(imem_req_valid && imem_req_ready) - int'(imem_rsp_valid);
      d_out <= d_out + int'(dmem_req_valid && dmem_req_ready) - int'(dmem_rsp_valid);
    end
  end
  a_i_one_out: assert property (i_out <= 1);
  a_d_one_out: assert property (d_out <= 1);
  a_i_no_new:  assert property (i_out == 1 && !imem_rsp_valid |-> !imem_req_valid);
  a_d_no_new:  assert property (d_out == 1 && !dmem_rsp_valid |-> !dmem_req_valid);

  // A flushed stage holds no valid instruction in the next cycle
  a_flush_id: assert property (flush_id |=> !id_valid);
  a_flush_ex: assert property (flush_ex |=> !ex_valid);

  // Divider: a result only after a start, and busy for a bounded time
  logic div_started;
  int   div_cycles;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      div_started <= 1'b0; div_cycles <= 0;
    end else begin
      if (div_start) div_started <= 1'b1;
      else if (!div_busy && !div_done) div_started <= 1'b0;
      div_cycles <= div_busy ? div_cycles + 1 : 0;
    end
  end
  a_div_after_start: assert property (div_done |-> div_started);
  a_div_bounded:     assert property (div_cycles <= 32);

  // A trapping instruction (in MEM) never retires (in WB next cycle)
  a_trap_no_retire: assert property (trap_valid |=> !tr_valid);

  // EX never needs a value that a load or CSR instruction in MEM has not made yet
  // (the load-use stall and the CSR flush must prevent it)
  logic [4:0] mrd;
  assign mrd = mem_instr[11:7];
  a_no_late_fwd: assert property (
    ex_valid && !flush_ex && mem_valid && !mem_exc && (mem_ctrl.is_load || mem_ctrl.is_csr) && mrd != 5'd0 |->
    !((ex_ctrl.use_rs1 && ex_instr[19:15] == mrd) || (ex_ctrl.use_rs2 && ex_instr[24:20] == mrd)));

  // Interrupts: taken only when pending and enabled (mstatus.MIE and the mie bit), never on
  // an instruction that has already sent its data request, and never left waiting long
  logic [9:0] irq_wait;
  always_ff @(posedge clk)
    if (!rst_n || !irq_pending || trap_valid) irq_wait <= '0;
    else if (irq_wait != 10'h3FF)             irq_wait <= irq_wait + 10'd1;
  a_irq_enabled:   assert property (trap_valid && trap_cause[31] |-> irq_pending);
  a_irq_no_req:    assert property (irq_take |-> !mem_d_req && !mem_d_acc);
  a_irq_latency:   assert property (irq_wait < 10'd600);   // longest: a divide plus heavy fetch waits
  // Priority when several are pending: external (11), then software (3), then timer (7)
  a_irq_priority:  assert property (irq_take |->
                     trap_cause == (irq_en_bits[11] ? 32'h8000_000B :
                                    irq_en_bits[3]  ? 32'h8000_0003 : 32'h8000_0007));
  c_irq_two_pending: cover property (irq_take && ($countones(irq_en_bits) > 1));

  // Cover: the interesting overlaps from the coverage plan
  c_trap_during_fetch_wait: cover property (trap_valid && i_out == 1 && !imem_rsp_valid);
  c_flush_div_start:        cover property (flush_ex && div_start);

  // A flush never meets a divide that is already running: while it runs EX stalls, MEM
  // only gets bubbles, and nothing older is left that could trap
  a_no_flush_div_busy: assert property (div_busy |-> !flush_ex);
endmodule

bind core_top core_sva u_sva (.*, .irq_en_bits(u_csr.irq_en_bits));
