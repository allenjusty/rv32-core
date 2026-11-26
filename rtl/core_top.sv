// 5-stage in-order RV32IM + Zicsr core, machine mode only.
//
//   IF -> ID -> EX -> MEM -> WB
//
// Redirects (MEM highest priority):
//   MEM: trap -> mtvec, MRET -> mepc, CSR / FENCE.I -> pc+4 (refetch)  flushes IF, ID, EX
//   EX : branch mispredict, JALR                                       flushes IF, ID
//   ID : JAL, branch predicted taken by the BHT                        flushes IF
// Forwarding into EX from EX/MEM and MEM/WB. All exceptions and interrupts are taken in MEM.
// An interrupt is taken on the instruction in MEM *before* it does anything: that
// instruction does not run, mepc points at it, and it runs after MRET.
module core_top
  import core_pkg::*;
#(
  parameter bit BHT_EN      = 1'b1,
  parameter int BHT_ENTRIES = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // Interrupt lines (level-sensitive, cleared by software at the source)
  input  logic        irq_software,
  input  logic        irq_timer,
  input  logic        irq_external,

  // Instruction port
  output logic        imem_req_valid,
  input  logic        imem_req_ready,
  output logic [31:0] imem_req_addr,
  input  logic        imem_rsp_valid,
  input  logic [31:0] imem_rsp_rdata,

  // Data port
  output logic        dmem_req_valid,
  input  logic        dmem_req_ready,
  output logic [31:0] dmem_req_addr,
  output logic        dmem_req_we,
  output logic [3:0]  dmem_req_be,
  output logic [31:0] dmem_req_wdata,
  input  logic        dmem_rsp_valid,
  input  logic [31:0] dmem_rsp_rdata,

  // Retirement trace (from WB)
  output logic        tr_valid,
  output logic [31:0] tr_pc,
  output logic [31:0] tr_insn,
  output logic        tr_rd_we,      // rd written (rd != x0)
  output logic [4:0]  tr_rd,
  output logic [31:0] tr_rd_val,
  output logic        tr_st_valid,
  output logic [31:0] tr_st_addr,
  output logic [31:0] tr_st_data,    // store data, masked to the store size
  output logic [1:0]  tr_st_size,    // 0 byte, 1 half, 2 word
  output logic        tr_csr_valid,
  output logic [11:0] tr_csr_addr,
  output logic [31:0] tr_csr_val,

  // Trap record (from MEM)
  output logic        trap_valid,
  output logic [31:0] trap_cause,
  output logic [31:0] trap_epc,
  output logic [31:0] trap_tval
);

  // ================================================================ declarations
  // IF
  logic [31:0] pc_f;
  logic        f_hold;        // request raised last cycle and not yet accepted
  logic [31:0] f_hold_addr;
  logic        f_hold_kill;   // a redirect happened while the request was held
  logic        f_out;         // a fetch was accepted and its response has not come back
                              // (if it was killed, ID is empty and simply ignores it)

  // ID
  logic        id_valid, id_have;
  logic [31:0] id_pc, id_instr_q, id_instr;

  // EX
  logic        ex_valid;
  logic [31:0] ex_pc, ex_instr, ex_imm, ex_a, ex_b;
  ctrl_t       ex_ctrl;
  logic        ex_pred_taken;
  logic        ex_exc;
  logic [3:0]  ex_cause;
  logic [31:0] ex_tval;

  // MEM
  logic        mem_valid;
  logic [31:0] mem_pc, mem_instr, mem_result, mem_addr, mem_sdata, mem_rs1val;
  ctrl_t       mem_ctrl;
  logic        mem_exc;
  logic [3:0]  mem_cause;
  logic [31:0] mem_tval;
  logic        mem_d_acc;     // data request accepted, waiting for the response
  logic        mem_d_req;     // data request raised (it must now stay until accepted)

  // WB
  logic        wb_valid;
  logic [31:0] wb_pc, wb_instr, wb_result, wb_value;
  ctrl_t       wb_ctrl;
  logic [1:0]  wb_addr_lo;
  logic        wb_st_valid;
  logic [31:0] wb_st_addr, wb_st_data;
  logic        wb_csr_valid;
  logic [11:0] wb_csr_addr;
  logic [31:0] wb_csr_val;

  // Control
  logic        mem_stall, mem_fire, ex_stall, ex_fire, id_fire, load_use;
  logic        mem_redirect, ex_redirect, id_redirect, redirect_any;
  logic [31:0] mem_redirect_pc, ex_redirect_pc, id_redirect_pc, redirect_pc;
  logic        flush_ex, flush_id;
  logic        br_taken, bht_upd;     // EX branch outcome, also updates the BHT

  // ================================================================ IF
  // A new fetch is raised only when the ID slot will be free next cycle and no
  // other fetch is outstanding. A raised request stays stable until accepted.
  logic issue_new, f_accept, f_kill_now;
  assign issue_new = !f_hold && (!f_out || imem_rsp_valid) && (!id_valid || id_fire) && !redirect_any;
  assign imem_req_valid = f_hold || issue_new;
  assign imem_req_addr  = f_hold ? f_hold_addr : pc_f;
  assign f_accept       = imem_req_valid && imem_req_ready;
  // The fetch being accepted is on the wrong path if a redirect happens now or happened
  // while it was held.
  assign f_kill_now     = redirect_any || (f_hold && f_hold_kill);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pc_f        <= RESET_PC;
      f_hold      <= 1'b0;
      f_hold_kill <= 1'b0;
      f_out       <= 1'b0;
      f_hold_addr <= '0;
    end else begin
      if (redirect_any)                 pc_f <= redirect_pc;
      else if (f_accept && !f_kill_now) pc_f <= pc_f + 32'd4;

      f_hold      <= imem_req_valid && !imem_req_ready;
      f_hold_addr <= imem_req_addr;
      f_hold_kill <= imem_req_valid && !imem_req_ready && ((f_hold && f_hold_kill) || redirect_any);

      if (f_accept)            f_out <= 1'b1;
      else if (imem_rsp_valid) f_out <= 1'b0;
    end
  end

  // ================================================================ ID
  ctrl_t       id_ctrl;
  logic [31:0] id_imm, id_rs1val, id_rs2val, id_target;
  logic        id_bits_ok, id_pred_taken, id_exc;
  logic [3:0]  id_cause;
  logic [31:0] id_tval;
  logic [1:0]  bht_cnt;
  logic [4:0]  id_rs1, id_rs2;

  // The instruction arrives straight from the port, or from id_instr_q if ID was
  // stalled when it arrived.
  assign id_bits_ok = id_have || imem_rsp_valid;
  assign id_instr   = id_have ? id_instr_q : imem_rsp_rdata;
  assign id_rs1     = id_instr[19:15];
  assign id_rs2     = id_instr[24:20];

  core_decode u_dec (.instr(id_instr), .ctrl(id_ctrl), .imm(id_imm));

  // Register file; WB writes and ID reads (with same-cycle bypass)
  logic wb_rf_we;
  assign wb_rf_we = wb_valid && wb_ctrl.rd_we;
  core_regfile u_rf (
    .clk, .ra1(id_rs1), .ra2(id_rs2), .rd1(id_rs1val), .rd2(id_rs2val),
    .we(wb_rf_we), .wa(wb_instr[11:7]), .wd(wb_value)
  );

  // Exceptions found in ID
  always_comb begin
    id_exc   = 1'b1;
    id_cause = EXC_ILLEGAL;
    id_tval  = '0;
    if (id_ctrl.illegal)     id_tval  = (id_instr[1:0] == 2'b11) ? id_instr : {16'b0, id_instr[15:0]};
    else if (id_ctrl.ecall)  id_cause = EXC_ECALL_M;
    else if (id_ctrl.ebreak) begin id_cause = EXC_BREAKPOINT; id_tval = id_pc; end
    else                     id_exc   = 1'b0;
  end

  // Load-use hazard: the load in EX produces its value only in MEM
  logic [4:0] ex_rd;
  assign ex_rd    = ex_instr[11:7];
  assign load_use = ex_valid && ex_ctrl.is_load && (ex_rd != 5'd0) &&
                    ((id_ctrl.use_rs1 && id_rs1 == ex_rd) || (id_ctrl.use_rs2 && id_rs2 == ex_rd));

  assign id_fire  = id_valid && id_bits_ok && !ex_stall && !load_use && !flush_id;

  // Early redirect: JAL always, a branch when the BHT says taken. Never to a
  // misaligned target (that instruction traps in MEM instead).
  core_bht #(.ENTRIES(BHT_ENTRIES)) u_bht (
    .clk, .rst_n, .rd_pc(id_pc), .rd_cnt(bht_cnt),
    .upd_en(bht_upd), .upd_pc(ex_pc), .upd_taken(br_taken)
  );
  assign id_target     = id_pc + id_imm;
  assign id_pred_taken = id_ctrl.is_branch && BHT_EN && bht_cnt[1] && !id_target[1];
  assign id_redirect   = id_fire && !id_exc && !id_target[1] && (id_ctrl.is_jal || id_pred_taken);
  assign id_redirect_pc = id_target;

  always_ff @(posedge clk) begin
    if (!rst_n || flush_id) begin
      id_valid <= 1'b0;
      id_have  <= 1'b0;
    end else if (f_accept && !f_kill_now) begin
      id_valid <= 1'b1;               // the slot is free: raised only when ID empties
      id_have  <= 1'b0;
      id_pc    <= imem_req_addr;
    end else if (id_fire) begin
      id_valid <= 1'b0;
      id_have  <= 1'b0;
    end else if (id_valid && !id_have && imem_rsp_valid) begin
      id_have    <= 1'b1;             // arrived while ID is stalled: keep it
      id_instr_q <= imem_rsp_rdata;
    end
  end

  // ================================================================ EX
  // Forwarding. EX/MEM is skipped for loads and CSR instructions: their value is made
  // in MEM. A dependent instruction can never be in EX then (load-use stall; a CSR
  // instruction flushes EX), and an assertion checks this.
  logic [4:0]  ex_rs1, ex_rs2, mem_rd, wb_rd;
  logic        mem_fwd_ok, wb_fwd_ok;
  logic [31:0] fwd_a, fwd_b;
  assign ex_rs1     = ex_instr[19:15];
  assign ex_rs2     = ex_instr[24:20];
  assign mem_rd     = mem_instr[11:7];
  assign wb_rd      = wb_instr[11:7];
  assign mem_fwd_ok = mem_valid && mem_ctrl.rd_we && !mem_exc && !mem_ctrl.is_load &&
                      !mem_ctrl.is_csr && (mem_rd != 5'd0);
  assign wb_fwd_ok  = wb_valid && wb_ctrl.rd_we && (wb_rd != 5'd0);

  always_comb begin
    if (mem_fwd_ok && mem_rd == ex_rs1)     fwd_a = mem_result;
    else if (wb_fwd_ok && wb_rd == ex_rs1)  fwd_a = wb_value;
    else                                    fwd_a = ex_a;
    if (mem_fwd_ok && mem_rd == ex_rs2)     fwd_b = mem_result;
    else if (wb_fwd_ok && wb_rd == ex_rs2)  fwd_b = wb_value;
    else                                    fwd_b = ex_b;
  end

  // ALU, multiplier, divider
  logic [31:0] op_a, op_b, alu_y, mul_y, div_y, ex_result, pc_plus4;
  logic        div_busy, div_done, div_start;
  assign op_a = (ex_ctrl.a_sel == A_PC) ? ex_pc : (ex_ctrl.a_sel == A_ZERO) ? 32'd0 : fwd_a;
  assign op_b = ex_ctrl.b_imm ? ex_imm : fwd_b;
  assign pc_plus4 = ex_pc + 32'd4;

  core_alu u_alu (.op(ex_ctrl.alu_op), .a(op_a), .b(op_b), .y(alu_y));
  core_mul u_mul (.op(ex_ctrl.funct3[1:0]), .a(fwd_a), .b(fwd_b), .y(mul_y));

  assign div_start = ex_valid && ex_ctrl.is_div && !ex_exc && !div_busy && !div_done;
  core_div u_div (
    .clk, .rst_n, .flush(flush_ex), .start(div_start), .ack(ex_fire),
    .op(ex_ctrl.funct3[1:0]), .a(fwd_a), .b(fwd_b),
    .busy(div_busy), .done(div_done), .y(div_y)
  );

  always_comb begin
    if (ex_ctrl.is_jal || ex_ctrl.is_jalr) ex_result = pc_plus4;
    else if (ex_ctrl.is_mul)               ex_result = mul_y;
    else if (ex_ctrl.is_div)               ex_result = div_y;
    else                                   ex_result = alu_y;
  end

  // Branches and jumps
  logic [31:0] br_target, jalr_target;
  always_comb begin
    unique case (ex_ctrl.funct3)
      3'b000:  br_taken = (fwd_a == fwd_b);
      3'b001:  br_taken = (fwd_a != fwd_b);
      3'b100:  br_taken = ($signed(fwd_a) <  $signed(fwd_b));
      3'b101:  br_taken = ($signed(fwd_a) >= $signed(fwd_b));
      3'b110:  br_taken = (fwd_a <  fwd_b);
      3'b111:  br_taken = (fwd_a >= fwd_b);
      default: br_taken = 1'b0;
    endcase
  end
  assign br_target   = ex_pc + ex_imm;                       // branch and JAL
  assign jalr_target = (fwd_a + ex_imm) & ~32'd1;

  // Exceptions found in EX: misaligned jump target, misaligned load/store address
  logic        ex_exc_new;
  logic [3:0]  ex_cause_new;
  logic [31:0] ex_tval_new;
  logic        ld_mis, st_mis;
  always_comb begin
    unique case (ex_ctrl.funct3[1:0])
      2'b01:   ld_mis = alu_y[0];            // half
      2'b10:   ld_mis = alu_y[1:0] != 2'b00; // word
      default: ld_mis = 1'b0;                // byte
    endcase
    st_mis = ld_mis;
    ex_exc_new   = 1'b1;
    ex_cause_new = EXC_IADDR_MISALIGN;
    ex_tval_new  = br_target;
    if (ex_ctrl.is_branch && br_taken && br_target[1]) ;
    else if (ex_ctrl.is_jal && br_target[1])            ;
    else if (ex_ctrl.is_jalr && jalr_target[1])         ex_tval_new = jalr_target;
    else if (ex_ctrl.is_load && ld_mis)  begin ex_cause_new = EXC_LADDR_MISALIGN; ex_tval_new = alu_y; end
    else if (ex_ctrl.is_store && st_mis) begin ex_cause_new = EXC_SADDR_MISALIGN; ex_tval_new = alu_y; end
    else ex_exc_new = 1'b0;
  end

  logic ex_any_exc;
  assign ex_any_exc = ex_exc || ex_exc_new;
  assign ex_stall   = mem_stall || (ex_valid && ex_ctrl.is_div && !ex_exc && !div_done);
  assign ex_fire    = ex_valid && !ex_stall && !flush_ex;

  // EX redirect: wrong branch prediction, or any JALR
  always_comb begin
    ex_redirect    = 1'b0;
    ex_redirect_pc = jalr_target;
    if (ex_fire && !ex_any_exc) begin
      if (ex_ctrl.is_branch && (br_taken != ex_pred_taken)) begin
        ex_redirect    = 1'b1;
        ex_redirect_pc = br_taken ? br_target : pc_plus4;
      end else if (ex_ctrl.is_jalr) begin
        ex_redirect    = 1'b1;
      end
    end
  end
  assign bht_upd = ex_fire && ex_ctrl.is_branch && !ex_any_exc;

  always_ff @(posedge clk) begin
    if (!rst_n || flush_ex) begin
      ex_valid <= 1'b0;
    end else if (ex_stall) begin
      ex_a <= fwd_a;                  // keep forwarded values: their producers move on
      ex_b <= fwd_b;
    end else if (id_fire) begin
      ex_valid      <= 1'b1;
      ex_pc         <= id_pc;
      ex_instr      <= id_instr;
      ex_ctrl       <= id_ctrl;
      ex_imm        <= id_imm;
      ex_a          <= id_rs1val;
      ex_b          <= id_rs2val;
      ex_pred_taken <= id_pred_taken;
      ex_exc        <= id_exc;
      ex_cause      <= id_cause;
      ex_tval       <= id_tval;
    end else begin
      ex_valid <= 1'b0;
    end
  end

  // ================================================================ MEM
  logic        mem_is_mem, mem_trap, csr_en, csr_illegal, csr_wr, mret_en;
  logic        irq_pending, irq_take;
  logic [11:0] csr_wr_addr;
  logic [31:0] csr_rdata, csr_wr_val, trap_vector, mepc_q, csr_src, irq_cause;

  assign mem_is_mem = mem_ctrl.is_load || mem_ctrl.is_store;

  // Interrupt: taken on the instruction in MEM unless that instruction has already sent
  // its data request (a raised request must not be withdrawn). Then the next one takes it.
  assign irq_take = mem_valid && irq_pending && !mem_d_req && !mem_d_acc;

  // Data port
  assign dmem_req_valid = mem_valid && mem_is_mem && !mem_exc && !mem_d_acc && !irq_take;
  assign dmem_req_addr  = mem_addr;
  assign dmem_req_we    = mem_ctrl.is_store;
  always_comb begin
    unique case (mem_ctrl.funct3[1:0])
      2'b00:   begin dmem_req_wdata = {4{mem_sdata[7:0]}};  dmem_req_be = 4'b0001 << mem_addr[1:0]; end
      2'b01:   begin dmem_req_wdata = {2{mem_sdata[15:0]}}; dmem_req_be = 4'b0011 << mem_addr[1:0]; end
      default: begin dmem_req_wdata = mem_sdata;            dmem_req_be = 4'b1111; end
    endcase
    if (!mem_ctrl.is_store) dmem_req_be = 4'b1111;
  end

  assign mem_stall = mem_valid && mem_is_mem && !mem_exc && !irq_take && !dmem_rsp_valid;
  assign mem_fire  = mem_valid && !mem_stall;

  // CSR file and trap unit
  assign csr_en  = mem_valid && mem_ctrl.is_csr && !mem_exc && !irq_take;
  assign csr_src = mem_ctrl.funct3[2] ? {27'b0, mem_instr[19:15]} : mem_rs1val;
  assign mem_trap = mem_valid && (irq_take || mem_exc || csr_illegal);
  assign mret_en  = mem_valid && mem_ctrl.is_mret && !mem_exc && !irq_take;

  core_csr u_csr (
    .clk, .rst_n,
    .csr_en, .csr_addr(mem_instr[31:20]), .csr_op(mem_ctrl.funct3[1:0]),
    .csr_src, .csr_src_x0(mem_instr[19:15] == 5'd0),
    .csr_rdata, .csr_illegal, .csr_wr, .csr_wr_addr, .csr_wr_val,
    .irq_software, .irq_timer, .irq_external, .irq_pending, .irq_cause,
    .trap_en(mem_trap), .trap_cause, .trap_pc(mem_pc), .trap_tval,
    .mret_en, .retire(wb_valid), .trap_vector, .mepc_o(mepc_q)
  );

  assign trap_valid = mem_trap;
  // Priority: interrupt, then the instruction's own exception, then an illegal CSR access
  assign trap_cause = irq_take ? irq_cause : {28'b0, mem_exc ? mem_cause : EXC_ILLEGAL};
  assign trap_epc   = mem_pc;
  assign trap_tval  = irq_take ? 32'd0 : mem_exc ? mem_tval : mem_instr;

  always_comb begin
    mem_redirect    = 1'b0;
    mem_redirect_pc = mem_pc + 32'd4;
    if (mem_trap) begin
      mem_redirect = 1'b1; mem_redirect_pc = trap_vector;
    end else if (mret_en) begin
      mem_redirect = 1'b1; mem_redirect_pc = mepc_q;
    end else if (csr_en || (mem_valid && mem_ctrl.is_fencei && !mem_exc)) begin   // (no irq: mem_trap)
      mem_redirect = 1'b1;            // refetch the next instruction
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mem_valid <= 1'b0;
      mem_d_acc <= 1'b0;
      mem_d_req <= 1'b0;
    end else if (mem_stall) begin
      if (dmem_req_valid) mem_d_req <= 1'b1;
      if (dmem_req_valid && dmem_req_ready) mem_d_acc <= 1'b1;
    end else begin
      mem_d_acc <= 1'b0;
      mem_d_req <= 1'b0;
      mem_valid <= ex_fire;
      if (ex_fire) begin
        mem_pc     <= ex_pc;
        mem_instr  <= ex_instr;
        mem_ctrl   <= ex_ctrl;
        mem_result <= ex_result;
        mem_addr   <= alu_y;
        mem_sdata  <= fwd_b;
        mem_rs1val <= fwd_a;
        mem_exc    <= ex_any_exc;
        mem_cause  <= ex_exc ? ex_cause : ex_cause_new;
        mem_tval   <= ex_exc ? ex_tval  : ex_tval_new;
      end
    end
  end

  // ================================================================ WB
  logic [31:0] wb_load_raw;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wb_valid <= 1'b0;
    end else begin
      wb_valid <= mem_fire && !mem_trap;     // a trapping instruction does not retire
      if (mem_fire) begin
        wb_pc        <= mem_pc;
        wb_instr     <= mem_instr;
        wb_ctrl      <= mem_ctrl;
        wb_result    <= mem_ctrl.is_csr ? csr_rdata : mem_result;
        wb_load_raw  <= dmem_rsp_rdata;
        wb_addr_lo   <= mem_addr[1:0];
        wb_st_valid  <= mem_ctrl.is_store;
        wb_st_addr   <= mem_addr;
        wb_st_data   <= (mem_ctrl.funct3[1:0] == 2'b00) ? {24'b0, mem_sdata[7:0]}  :
                        (mem_ctrl.funct3[1:0] == 2'b01) ? {16'b0, mem_sdata[15:0]} : mem_sdata;
        wb_csr_valid <= csr_wr;
        wb_csr_addr  <= csr_wr_addr;
        wb_csr_val   <= csr_wr_val;
      end
    end
  end

  // Load byte select and sign extension
  logic [31:0] ld_shift;
  assign ld_shift = wb_load_raw >> {wb_addr_lo, 3'b000};
  always_comb begin
    if (!wb_ctrl.is_load) wb_value = wb_result;
    else unique case (wb_ctrl.funct3)
      3'b000:  wb_value = {{24{ld_shift[7]}},  ld_shift[7:0]};    // LB
      3'b001:  wb_value = {{16{ld_shift[15]}}, ld_shift[15:0]};   // LH
      3'b100:  wb_value = {24'b0, ld_shift[7:0]};                 // LBU
      3'b101:  wb_value = {16'b0, ld_shift[15:0]};                // LHU
      default: wb_value = ld_shift;                               // LW
    endcase
  end

  // Trace
  assign tr_valid     = wb_valid;
  assign tr_pc        = wb_pc;
  assign tr_insn      = wb_instr;
  assign tr_rd_we     = wb_ctrl.rd_we && (wb_rd != 5'd0);
  assign tr_rd        = wb_rd;
  assign tr_rd_val    = wb_value;
  assign tr_st_valid  = wb_st_valid;
  assign tr_st_addr   = wb_st_addr;
  assign tr_st_data   = wb_st_data;
  assign tr_st_size   = wb_ctrl.funct3[1:0];
  assign tr_csr_valid = wb_csr_valid;
  assign tr_csr_addr  = wb_csr_addr;
  assign tr_csr_val   = wb_csr_val;

  // ================================================================ redirect / flush
  assign redirect_any = mem_redirect || ex_redirect || id_redirect;
  assign redirect_pc  = mem_redirect ? mem_redirect_pc : ex_redirect ? ex_redirect_pc : id_redirect_pc;
  assign flush_ex     = mem_redirect;
  assign flush_id     = mem_redirect || ex_redirect;

endmodule
