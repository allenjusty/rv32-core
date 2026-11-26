// Functional coverage (plan in docs/testplan.md). Retired instructions and traps come
// from the retire monitor; pipeline events come from the probes in core_tb_if.
// Plain coverpoints with explicit bins and plain full crosses only, so Verilator keeps
// them all. Combinations that cannot all occur are written as one coverpoint with an
// explicit bin per legal combination instead of a cross.
class core_coverage extends uvm_subscriber #(core_rec);
  `uvm_component_utils(core_coverage)

  virtual core_tb_if vif;

  // Instruction ids for the "every instruction retired" coverpoint
  typedef enum int {
    I_LUI, I_AUIPC, I_JAL, I_JALR, I_BEQ, I_BNE, I_BLT, I_BGE, I_BLTU, I_BGEU,
    I_LB, I_LH, I_LW, I_LBU, I_LHU, I_SB, I_SH, I_SW,
    I_ADDI, I_SLTI, I_SLTIU, I_XORI, I_ORI, I_ANDI, I_SLLI, I_SRLI, I_SRAI,
    I_ADD, I_SUB, I_SLL, I_SLT, I_SLTU, I_XOR, I_SRL, I_SRA, I_OR, I_AND,
    I_FENCE, I_FENCE_I, I_MUL, I_MULH, I_MULHSU, I_MULHU, I_DIV, I_DIVU, I_REM, I_REMU,
    I_CSRRW, I_CSRRS, I_CSRRC, I_CSRRWI, I_CSRRSI, I_CSRRCI, I_MRET, I_WFI, I_OTHER
  } instr_e;

  // ---- sampled values
  int        c_instr;
  bit        c_rd_x0, c_rs1_x0, c_rs2_x0, c_rd_eq_rs1, c_rd_eq_rs2;
  int        c_unit, c_a_cls, c_b_cls, c_div_case;
  int        c_fwd;
  int        c_br_type;
  bit        c_br_taken, c_br_back, c_br_ok;
  int        c_bht;
  int        c_ls_op, c_ls_off;
  int        c_trap;
  bit        c_nested;
  int        c_csr, c_csr_op;
  bit        c_csr_rd_x0, c_csr_rs1_x0, c_csr_ro_write;
  bit        c_ev_load_use, c_ev_div, c_ev_fetch, c_ev_dwait;
  bit        c_ov_mispredict_dwait, c_ov_loaduse_dwait, c_ov_trap_fetch, c_ov_flush_div;
  bit        in_handler;     // between a trap and the next MRET
  int        c_irq_cause, c_irq_victim;
  bit        c_irq_vectored, c_irq_fetch_wait, c_irq_div_busy, c_irq_dwait;

  covergroup cg_instr;
    cp_instr: coverpoint c_instr { bins instr[] = {[I_LUI:I_WFI]}; }
  endgroup

  covergroup cg_regs;
    cp_rd_x0:     coverpoint c_rd_x0     { bins yes = {1}; }
    cp_rs1_x0:    coverpoint c_rs1_x0    { bins yes = {1}; }
    cp_rs2_x0:    coverpoint c_rs2_x0    { bins yes = {1}; }
    cp_rd_eq_rs1: coverpoint c_rd_eq_rs1 { bins yes = {1}; }
    cp_rd_eq_rs2: coverpoint c_rd_eq_rs2 { bins yes = {1}; }
  endgroup

  // Operand classes: 0 zero, 1 one, 2 minus one, 3 largest positive, 4 most negative, 5 other
  covergroup cg_operands;
    cp_unit:  coverpoint c_unit  { bins alu = {0}; bins mul = {1}; bins div = {2}; }
    cp_a:     coverpoint c_a_cls { bins zero = {0}; bins one = {1}; bins m1 = {2}; bins maxp = {3}; bins minn = {4}; bins other = {5}; }
    cp_b:     coverpoint c_b_cls { bins zero = {0}; bins one = {1}; bins m1 = {2}; bins maxp = {3}; bins minn = {4}; bins other = {5}; }
    x_unit_a: cross cp_unit, cp_a;
    x_unit_b: cross cp_unit, cp_b;
  endgroup

  covergroup cg_div;
    cp_case: coverpoint c_div_case { bins by_zero = {1}; bins overflow = {2}; }
  endgroup

  // Forwarding: source x operand x producer. A load can only forward from MEM/WB.
  covergroup cg_fwd;
    cp_fwd: coverpoint c_fwd {
      bins exmem_rs1_alu = {0};  bins exmem_rs1_mul = {1};  bins exmem_rs1_div = {2};
      bins exmem_rs2_alu = {3};  bins exmem_rs2_mul = {4};  bins exmem_rs2_div = {5};
      bins memwb_rs1_alu = {6};  bins memwb_rs1_mul = {7};  bins memwb_rs1_div = {8};  bins memwb_rs1_load = {9};
      bins memwb_rs2_alu = {10}; bins memwb_rs2_mul = {11}; bins memwb_rs2_div = {12}; bins memwb_rs2_load = {13};
    }
  endgroup

  covergroup cg_stall;
    cp_load_use: coverpoint c_ev_load_use { bins yes = {1}; }
    cp_div_busy: coverpoint c_ev_div      { bins yes = {1}; }
    cp_fetch:    coverpoint c_ev_fetch    { bins yes = {1}; }
    cp_dwait:    coverpoint c_ev_dwait    { bins yes = {1}; }
  endgroup

  covergroup cg_branch;
    cp_type:  coverpoint c_br_type  { bins beq = {0}; bins bne = {1}; bins blt = {4}; bins bge = {5}; bins bltu = {6}; bins bgeu = {7}; }
    cp_taken: coverpoint c_br_taken { bins no = {0}; bins yes = {1}; }
    cp_dir:   coverpoint c_br_back  { bins forward = {0}; bins backward = {1}; }
    cp_pred:  coverpoint c_br_ok    { bins wrong = {0}; bins right = {1}; }
    x_branch: cross cp_type, cp_taken, cp_dir, cp_pred;
  endgroup

  covergroup cg_bht;
    cp_cnt: coverpoint c_bht { bins strong_nt = {0}; bins weak_nt = {1}; bins weak_t = {2}; bins strong_t = {3}; }
  endgroup

  covergroup cg_ldst;
    cp_op:  coverpoint c_ls_op  { bins lb = {0}; bins lh = {1}; bins lw = {2}; bins lbu = {4}; bins lhu = {5};
                                  bins sb = {8}; bins sh = {9}; bins sw = {10}; }
    cp_off: coverpoint c_ls_off { bins off[] = {[0:3]}; }
    x_op_off: cross cp_op, cp_off;     // misaligned ones trap
  endgroup

  // mcause x the stage that found it
  covergroup cg_trap;
    cp_trap: coverpoint c_trap {
      bins iaddr_ex = {0}; bins illegal_id = {2}; bins illegal_mem = {102}; bins break_id = {3};
      bins laddr_ex = {4}; bins saddr_ex = {6}; bins ecall_id = {11};
    }
  endgroup

  // Interrupts: cause x what kind of instruction was in MEM (it is the one interrupted)
  covergroup cg_irq;
    cp_cause:  coverpoint c_irq_cause  { bins software = {3}; bins timer = {7}; bins external = {11}; }
    cp_victim: coverpoint c_irq_victim { bins alu = {0}; bins load = {1}; bins store = {2}; bins branch_jump = {3};
                                         bins mul_div = {4}; bins csr_mret_fence = {5}; bins has_exception = {6}; }
    x_cause_victim: cross cp_cause, cp_victim;
    cp_vectored:   coverpoint c_irq_vectored   { bins direct_mode = {0}; bins vectored_mode = {1}; }
    cp_fetch_wait: coverpoint c_irq_fetch_wait { bins yes = {1}; }
  endgroup

  // An interrupt that has to wait: behind a running divide, or behind a data request
  covergroup cg_irq_wait;
    cp_div_busy: coverpoint c_irq_div_busy { bins yes = {1}; }
    cp_dwait:    coverpoint c_irq_dwait    { bins yes = {1}; }
  endgroup

  covergroup cg_nested;
    cp_nested: coverpoint c_nested { bins trap_in_handler = {1}; }
  endgroup

  // CSR x instruction as one coverpoint (19 CSRs x 6 forms = 114 combinations), so that
  // the one combination that cannot be tested is left out: CSRRWI on misa (Spike would
  // switch the M extension off; spec section 8).
  localparam bit [11:0] CSR_LIST [19] = '{12'h300, 12'h301, 12'h304, 12'h305, 12'h310, 12'h340,
      12'h341, 12'h342, 12'h343, 12'h344, 12'hB00, 12'hB02, 12'hB80, 12'hB82, 12'hF11, 12'hF12,
      12'hF13, 12'hF14, 12'hF15};
  int c_csr_combo;            // csr_index * 6 + form (0 RW, 1 RS, 2 RC, 3 RWI, 4 RSI, 5 RCI)
  covergroup cg_csr;
    cp_csr: coverpoint c_csr {
      bins mstatus = {12'h300}; bins misa = {12'h301}; bins mie = {12'h304}; bins mtvec = {12'h305};
      bins mstatush = {12'h310}; bins mscratch = {12'h340}; bins mepc = {12'h341}; bins mcause = {12'h342};
      bins mtval = {12'h343}; bins mip = {12'h344}; bins mcycle = {12'hB00}; bins minstret = {12'hB02};
      bins mcycleh = {12'hB80}; bins minstreth = {12'hB82}; bins mvendorid = {12'hF11}; bins marchid = {12'hF12};
      bins mimpid = {12'hF13}; bins mhartid = {12'hF14}; bins mconfigptr = {12'hF15};
    }
    cp_op: coverpoint c_csr_op { bins rw = {1}; bins rs = {2}; bins rc = {3}; bins rwi = {5}; bins rsi = {6}; bins rci = {7}; }
    cp_csr_x_op: coverpoint c_csr_combo { bins combo[] = {[0:8], [10:113]}; }   // 9 = misa x RWI
    cp_rd_x0:    coverpoint c_csr_rd_x0    { bins yes = {1}; }
    cp_rs1_x0:   coverpoint c_csr_rs1_x0   { bins yes = {1}; }
    cp_ro_write: coverpoint c_csr_ro_write { bins yes = {1}; }
  endgroup

  covergroup cg_overlap;
    cp_mispredict_dwait: coverpoint c_ov_mispredict_dwait { bins yes = {1}; }
    cp_loaduse_dwait:    coverpoint c_ov_loaduse_dwait    { bins yes = {1}; }
    cp_trap_fetch_wait:  coverpoint c_ov_trap_fetch       { bins yes = {1}; }
    cp_flush_div_start:  coverpoint c_ov_flush_div        { bins yes = {1}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_instr = new(); cg_regs = new(); cg_operands = new(); cg_div = new(); cg_fwd = new();
    cg_stall = new(); cg_branch = new(); cg_bht = new(); cg_ldst = new(); cg_trap = new();
    cg_csr = new(); cg_overlap = new(); cg_nested = new();
    cg_irq = new(); cg_irq_wait = new();
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual core_tb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "core_tb_if not set")
  endfunction

  // ------------------------------------------------------------ helpers
  static function instr_e decode(bit [31:0] i);
    bit [2:0] f3 = i[14:12];
    bit [6:0] f7 = i[31:25];
    case (i[6:0])
      7'b0110111: return I_LUI;
      7'b0010111: return I_AUIPC;
      7'b1101111: return I_JAL;
      7'b1100111: return I_JALR;
      7'b1100011: case (f3) 0: return I_BEQ; 1: return I_BNE; 4: return I_BLT; 5: return I_BGE;
                            6: return I_BLTU; 7: return I_BGEU; default: return I_OTHER; endcase
      7'b0000011: case (f3) 0: return I_LB; 1: return I_LH; 2: return I_LW; 4: return I_LBU;
                            5: return I_LHU; default: return I_OTHER; endcase
      7'b0100011: case (f3) 0: return I_SB; 1: return I_SH; 2: return I_SW; default: return I_OTHER; endcase
      7'b0010011: case (f3) 0: return I_ADDI; 2: return I_SLTI; 3: return I_SLTIU; 4: return I_XORI;
                            6: return I_ORI; 7: return I_ANDI; 1: return I_SLLI;
                            default: return f7[5] ? I_SRAI : I_SRLI; endcase
      7'b0110011:
        if (f7 == 7'b0000001)
          case (f3) 0: return I_MUL; 1: return I_MULH; 2: return I_MULHSU; 3: return I_MULHU;
                    4: return I_DIV; 5: return I_DIVU; 6: return I_REM; default: return I_REMU; endcase
        else
          case (f3) 0: return f7[5] ? I_SUB : I_ADD; 1: return I_SLL; 2: return I_SLT; 3: return I_SLTU;
                    4: return I_XOR; 5: return f7[5] ? I_SRA : I_SRL; 6: return I_OR; default: return I_AND; endcase
      7'b0001111: return f3 == 0 ? I_FENCE : I_FENCE_I;
      7'b1110011:
        case (f3)
          1: return I_CSRRW; 2: return I_CSRRS; 3: return I_CSRRC;
          5: return I_CSRRWI; 6: return I_CSRRSI; 7: return I_CSRRCI;
          default: return (i == 32'h3020_0073) ? I_MRET : (i == 32'h1050_0073) ? I_WFI : I_OTHER;
        endcase
      default: return I_OTHER;
    endcase
  endfunction

  static function int val_class(bit [31:0] v);
    if (v == 0)            return 0;
    if (v == 1)            return 1;
    if (v == 32'hFFFF_FFFF) return 2;
    if (v == 32'h7FFF_FFFF) return 3;
    if (v == 32'h8000_0000) return 4;
    return 5;
  endfunction

  // 0 ALU, 1 MUL, 2 DIV, 3 load (producer type for forwarding)
  static function int producer(core_pkg::ctrl_t c);
    if (c.is_load) return 3;
    if (c.is_mul)  return 1;
    if (c.is_div)  return 2;
    return 0;
  endfunction

  // ------------------------------------------------------------ retired records
  function void write(core_rec t);
    if (t.is_trap) begin
      c_nested = in_handler;
      in_handler = 1;
      if (c_nested) cg_nested.sample();
      return;
    end
    c_instr = decode(t.insn);
    cg_instr.sample();
    if (c_instr == I_MRET) in_handler = 0;
  endfunction

  // ------------------------------------------------------------ pipeline events
  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (!vif.rst_n) continue;
      sample_cycle();
    end
  endtask

  function void sample_cycle();
    core_pkg::ctrl_t c = vif.ex_ctrl;
    bit [4:0] rs1 = vif.ex_instr[19:15], rs2 = vif.ex_instr[24:20], rd = vif.ex_instr[11:7];

    // stalls and overlaps (every cycle)
    c_ev_load_use = vif.load_use;
    c_ev_div      = vif.div_busy;
    c_ev_fetch    = vif.id_wait_fetch || vif.fetch_wait;
    c_ev_dwait    = vif.mem_stall;
    cg_stall.sample();
    c_ov_mispredict_dwait = vif.ex_valid && c.is_branch && (vif.br_taken != vif.ex_pred_taken) && vif.mem_stall;
    c_ov_loaduse_dwait    = vif.load_use && vif.mem_stall;
    c_ov_trap_fetch       = vif.trap_valid && vif.fetch_wait;
    c_ov_flush_div        = vif.flush_ex && vif.div_start;   // busy + flush cannot happen (see testplan)
    cg_overlap.sample();

    // BHT counter when a branch leaves ID (only meaningful with the BHT on)
    if (vif.id_fire && vif.id_ctrl.is_branch) begin
      c_bht = vif.bht_cnt;
      cg_bht.sample();
    end

    // EX: registers, operands, forwarding, branches, loads/stores
    if (vif.ex_fire) begin
      c_rd_x0     = c.rd_we && rd == 0;
      c_rs1_x0    = c.use_rs1 && rs1 == 0;
      c_rs2_x0    = c.use_rs2 && rs2 == 0;
      c_rd_eq_rs1 = c.rd_we && c.use_rs1 && rd == rs1 && rd != 0;
      c_rd_eq_rs2 = c.rd_we && c.use_rs2 && rd == rs2 && rd != 0;
      cg_regs.sample();

      if (c.use_rs1 && c.use_rs2 && !c.is_branch && !c.is_store) begin
        c_unit  = c.is_mul ? 1 : c.is_div ? 2 : 0;
        c_a_cls = val_class(vif.fwd_a);
        c_b_cls = val_class(vif.fwd_b);
        cg_operands.sample();
        if (c.is_div) begin
          c_div_case = (vif.fwd_b == 0) ? 1 :
                       (!c.funct3[0] && vif.fwd_a == 32'h8000_0000 && vif.fwd_b == 32'hFFFF_FFFF) ? 2 : 0;
          if (c_div_case != 0) cg_div.sample();
        end
      end

      sample_fwd(c, rs1, rs2);

      if (c.is_branch && !vif.ex_any_exc) begin
        c_br_type  = c.funct3;
        c_br_taken = vif.br_taken;
        c_br_back  = vif.ex_imm[31];
        c_br_ok    = (vif.br_taken == vif.ex_pred_taken);
        cg_branch.sample();
      end

      if (c.is_load || c.is_store) begin
        c_ls_op  = {c.is_store, c.funct3};
        c_ls_off = vif.alu_y[1:0];
        cg_ldst.sample();
      end
    end

    // Interrupts
    if (vif.irq_take) begin
      core_pkg::ctrl_t m = vif.mem_ctrl_irq;
      c_irq_cause = vif.trap_cause[3:0];
      c_irq_victim = vif.mem_exc ? 6 : m.is_load ? 1 : m.is_store ? 2 :
                     (m.is_branch || m.is_jal || m.is_jalr) ? 3 : (m.is_mul || m.is_div) ? 4 :
                     (m.is_csr || m.is_mret || m.is_fencei) ? 5 : 0;
      c_irq_vectored   = vif.mtvec_vectored;
      c_irq_fetch_wait = vif.fetch_wait;
      cg_irq.sample();
    end
    if (vif.irq_pending && !vif.irq_take) begin
      c_irq_div_busy = vif.div_busy;
      c_irq_dwait    = vif.mem_stall;
      cg_irq_wait.sample();
    end

    // Traps: cause x stage (illegal from MEM = a CSR access)
    if (vif.trap_valid && !vif.trap_cause[31]) begin
      c_trap   = (vif.trap_cause == 2 && !vif.mem_exc) ? 102 : int'(vif.trap_cause);
      cg_trap.sample();
    end

    // CSR instructions in MEM
    if (vif.csr_en) begin
      bit [31:0] mi = vif.mem_instr_p;
      c_csr          = mi[31:20];
      c_csr_op       = mi[14:12];
      c_csr_rd_x0    = mi[11:7] == 0;
      c_csr_rs1_x0   = mi[19:15] == 0;
      c_csr_ro_write = mi[31:30] == 2'b11 && (mi[13:12] == 2'b01 || mi[19:15] != 0);
      c_csr_combo    = -1;
      foreach (CSR_LIST[k])
        if (CSR_LIST[k] == mi[31:20]) c_csr_combo = k * 6 + (mi[14] ? 3 : 0) + int'(mi[13:12]) - 1;
      cg_csr.sample();
    end
  endfunction

  function void sample_fwd(core_pkg::ctrl_t c, bit [4:0] rs1, bit [4:0] rs2);
    bit [4:0] mrd = vif.mem_instr_p[11:7], wrd = vif.wb_instr_p[11:7];
    // rs1
    if (c.use_rs1 && rs1 != 0) begin
      if (vif.mem_fwd_ok && mrd == rs1)     begin c_fwd = 0 + producer(vif.mem_ctrl_p); cg_fwd.sample(); end
      else if (vif.wb_fwd_ok && wrd == rs1) begin c_fwd = 6 + producer(vif.wb_ctrl_p);  cg_fwd.sample(); end
    end
    // rs2
    if (c.use_rs2 && rs2 != 0) begin
      if (vif.mem_fwd_ok && mrd == rs2)     begin c_fwd = 3 + producer(vif.mem_ctrl_p);  cg_fwd.sample(); end
      else if (vif.wb_fwd_ok && wrd == rs2) begin c_fwd = 10 + producer(vif.wb_ctrl_p); cg_fwd.sample(); end
    end
  endfunction
endclass
