// Machine-mode CSR file and trap unit (MEM stage).
// CSR instructions, traps, interrupts and MRET all take effect here, in MEM.
// Interrupts: software (MSIP, bit 3), timer (MTIP, bit 7), external (MEIP, bit 11).
// The pending bits in mip come straight from the input lines (level-sensitive); software
// clears them at the source. Priority when several are pending: external, software, timer.
module core_csr
  import core_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // CSR instruction in MEM
  input  logic        csr_en,       // a CSR instruction with no earlier exception is in MEM
  input  logic [11:0] csr_addr,
  input  logic [1:0]  csr_op,       // funct3[1:0]: 01 RW, 10 RS, 11 RC
  input  logic [31:0] csr_src,      // rs1 value, or the zero-extended uimm
  input  logic        csr_src_x0,   // rs1 field (or uimm) is 0: RS/RC do not write
  output logic [31:0] csr_rdata,    // old value, goes to rd
  output logic        csr_illegal,  // unknown CSR, or a write to a read-only CSR
  output logic        csr_wr,       // a CSR is written (for the trace): CSR instruction or MRET
  output logic [11:0] csr_wr_addr,  // which one (MRET writes mstatus)
  output logic [31:0] csr_wr_val,   // its new value

  // Interrupt lines and the interrupt request to the pipeline
  input  logic        irq_software,
  input  logic        irq_timer,
  input  logic        irq_external,
  output logic        irq_pending,  // an enabled interrupt is pending and mstatus.MIE = 1
  output logic [31:0] irq_cause,    // its mcause value (bit 31 set)

  // Trap (exception or interrupt) and MRET
  input  logic        trap_en,
  input  logic [31:0] trap_cause,
  input  logic [31:0] trap_pc,
  input  logic [31:0] trap_tval,
  input  logic        mret_en,

  input  logic        retire,       // an instruction retires in WB this cycle

  output logic [31:0] trap_vector,  // where the trap in MEM goes
  output logic [31:0] mepc_o
);
  // State
  logic        mstatus_mie, mstatus_mpie;
  logic [11:0] mie_q;               // only bits 3, 7, 11 are kept
  logic [31:0] mtvec_q, mscratch_q, mepc_q, mcause_q, mtval_q;
  logic [63:0] mcycle_q, minstret_q;

  localparam logic [31:0] MISA = 32'h4000_1100;   // MXL = 1 (32-bit), I, M

  // Pending and enabled interrupts
  logic [31:0] mip, irq_en_bits;
  assign mip         = {20'b0, irq_external, 3'b0, irq_timer, 3'b0, irq_software, 3'b0};
  assign irq_en_bits = mip & {20'b0, mie_q};
  assign irq_pending = mstatus_mie && (irq_en_bits != 32'd0);
  always_comb begin
    if (irq_en_bits[11])     irq_cause = 32'h8000_000B;   // machine external
    else if (irq_en_bits[3]) irq_cause = 32'h8000_0003;   // machine software
    else                     irq_cause = 32'h8000_0007;   // machine timer
  end

  // Read mux; `known` = the CSR exists
  logic known;
  always_comb begin
    known     = 1'b1;
    csr_rdata = '0;
    unique case (csr_addr)
      12'h300: csr_rdata = {19'b0, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
      12'h310: csr_rdata = '0;                          // mstatush
      12'h301: csr_rdata = MISA;
      12'h304: csr_rdata = {20'b0, mie_q};
      12'h344: csr_rdata = mip;                         // read-only: set by the lines
      12'h305: csr_rdata = mtvec_q;
      12'h340: csr_rdata = mscratch_q;
      12'h341: csr_rdata = mepc_q;
      12'h342: csr_rdata = mcause_q;
      12'h343: csr_rdata = mtval_q;
      12'hB00: csr_rdata = mcycle_q[31:0];
      12'hB80: csr_rdata = mcycle_q[63:32];
      12'hB02: csr_rdata = minstret_q[31:0];
      12'hB82: csr_rdata = minstret_q[63:32];
      12'hF11, 12'hF12, 12'hF13, 12'hF14, 12'hF15: csr_rdata = '0;
      default: known = 1'b0;
    endcase
  end

  // Value to write
  logic        writes;
  logic [31:0] wval;
  assign writes = (csr_op == 2'b01) || !csr_src_x0;
  always_comb begin
    unique case (csr_op)
      2'b01:   wval = csr_src;
      2'b10:   wval = csr_rdata | csr_src;
      2'b11:   wval = csr_rdata & ~csr_src;
      default: wval = csr_rdata;
    endcase
  end

  assign csr_illegal = csr_en && (!known || (writes && csr_addr[11:10] == 2'b11));
  logic do_write;
  assign do_write = csr_en && !csr_illegal && writes;
  assign csr_wr      = do_write || mret_en;
  assign csr_wr_addr = mret_en ? 12'h300 : csr_addr;

  // The value the CSR holds after the write (same masks as the write logic below)
  always_comb begin
    if (mret_en) csr_wr_val = {19'b0, 2'b11, 3'b0, 1'b1, 3'b0, mstatus_mpie, 3'b0};   // MIE = MPIE, MPIE = 1
    else unique case (csr_addr)
      12'h300: csr_wr_val = {19'b0, 2'b11, 3'b0, wval[7], 3'b0, wval[3], 3'b0};
      12'h304: csr_wr_val = wval & 32'h0000_0888;
      12'h305: csr_wr_val = {wval[31:2], 1'b0, wval[0]};
      12'h341: csr_wr_val = {wval[31:2], 2'b00};
      12'h340, 12'h342, 12'h343,
      12'hB00, 12'hB80, 12'hB02, 12'hB82: csr_wr_val = wval;
      default: csr_wr_val = csr_rdata;                  // read-only-zero CSRs ignore writes
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mstatus_mie  <= 1'b0;
      mstatus_mpie <= 1'b0;
      mie_q        <= '0;
      mtvec_q      <= '0;
      mscratch_q   <= '0;
      mepc_q       <= '0;
      mcause_q     <= '0;
      mtval_q      <= '0;
      mcycle_q     <= '0;
      minstret_q   <= '0;
    end else begin
      // Counters (a software write in the same cycle wins)
      mcycle_q   <= mcycle_q + 64'd1;
      if (retire) minstret_q <= minstret_q + 64'd1;

      if (trap_en) begin
        mepc_q       <= {trap_pc[31:2], 2'b00};
        mcause_q     <= trap_cause;
        mtval_q      <= trap_tval;
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;
      end else if (mret_en) begin
        mstatus_mie  <= mstatus_mpie;
        mstatus_mpie <= 1'b1;
      end else if (do_write) begin
        unique case (csr_addr)
          12'h300: begin mstatus_mie <= wval[3]; mstatus_mpie <= wval[7]; end
          12'h304: mie_q      <= wval[11:0] & 12'h888;
          12'h305: mtvec_q    <= {wval[31:2], 1'b0, wval[0]};
          12'h340: mscratch_q <= wval;
          12'h341: mepc_q     <= {wval[31:2], 2'b00};
          12'h342: mcause_q   <= wval;
          12'h343: mtval_q    <= wval;
          12'hB00: mcycle_q[31:0]    <= wval;
          12'hB80: mcycle_q[63:32]   <= wval;
          12'hB02: minstret_q[31:0]  <= wval;
          12'hB82: minstret_q[63:32] <= wval;
          default: ;                                     // read-only-zero CSRs
        endcase
      end
    end
  end

  // Direct mode: every trap goes to BASE. Vectored mode (mtvec[0] = 1): interrupts go to
  // BASE + 4 x cause, exceptions still to BASE.
  assign trap_vector = (trap_cause[31] && mtvec_q[0]) ? {mtvec_q[31:2], 2'b00} + {26'b0, trap_cause[3:0], 2'b00}
                                                      : {mtvec_q[31:2], 2'b00};
  assign mepc_o     = mepc_q;
endmodule
