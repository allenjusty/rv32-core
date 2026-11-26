// Plain SystemVerilog bring-up bench: core + memory, no UVM.
// Writes the retirement trace to +TRACE=<file> (same format as the Spike trace) and
// ends at the tohost write. Also used for CPI runs (+CPI prints cycle counts).
module core_smoke_tb #(parameter bit BHT_EN = 1'b1);
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic        imem_req_valid, imem_req_ready, imem_rsp_valid;
  logic [31:0] imem_req_addr, imem_rsp_rdata;
  logic        dmem_req_valid, dmem_req_ready, dmem_req_we, dmem_rsp_valid;
  logic [31:0] dmem_req_addr, dmem_req_wdata, dmem_rsp_rdata;
  logic [3:0]  dmem_req_be;
  logic        tr_valid, tr_rd_we, tr_st_valid, tr_csr_valid, trap_valid;
  logic [31:0] tr_pc, tr_insn, tr_rd_val, tr_st_addr, tr_st_data, tr_csr_val;
  logic [31:0] trap_cause, trap_epc, trap_tval;
  logic [4:0]  tr_rd;
  logic [1:0]  tr_st_size;
  logic [11:0] tr_csr_addr;
  logic        tohost_done;
  logic        irq_software, irq_timer, irq_external;
  logic [31:0] tohost_value;

  core_top #(.BHT_EN(BHT_EN)) dut (.*);

  tb_mem u_mem (
    .clk, .rst_n,
    .i_req_valid(imem_req_valid), .i_req_ready(imem_req_ready), .i_req_addr(imem_req_addr),
    .i_rsp_valid(imem_rsp_valid), .i_rsp_rdata(imem_rsp_rdata),
    .d_req_valid(dmem_req_valid), .d_req_ready(dmem_req_ready), .d_req_addr(dmem_req_addr),
    .d_req_we(dmem_req_we), .d_req_be(dmem_req_be), .d_req_wdata(dmem_req_wdata),
    .d_rsp_valid(dmem_rsp_valid), .d_rsp_rdata(dmem_rsp_rdata),
    .tohost_done, .tohost_value,
    .iready_pct, .ilat_max, .dready_pct, .dlat_max,
    .irq_ext_pm, .irq_tmr_pm, .irq_software, .irq_timer, .irq_external
  );
  // wait-state knobs: +IREADY_PCT=n +ILAT_MAX=n +DREADY_PCT=n +DLAT_MAX=n (0 by default)
  int iready_pct = 0, ilat_max = 0, dready_pct = 0, dlat_max = 0;
  // random interrupts: +IRQ_EXT_PM=n +IRQ_TMR_PM=n (chance per cycle, per mille)
  int irq_ext_pm = 0, irq_tmr_pm = 0;
  initial begin
    void'($value$plusargs("IRQ_EXT_PM=%d", irq_ext_pm));
    void'($value$plusargs("IRQ_TMR_PM=%d", irq_tmr_pm));
    void'($value$plusargs("IREADY_PCT=%d", iready_pct));
    void'($value$plusargs("ILAT_MAX=%d",   ilat_max));
    void'($value$plusargs("DREADY_PCT=%d", dready_pct));
    void'($value$plusargs("DLAT_MAX=%d",   dlat_max));
  end

  int    fd = 0;
  string trace_file;
  longint cycles = 0, retired = 0, max_cycles;
  int    idle = 0;
  logic [31:0] tohost_addr;
  logic  done_seen = 1'b0;

  initial begin
    if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 2_000_000;
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) tohost_addr = 32'hFFFF_FFFF;
    if ($value$plusargs("TRACE=%s", trace_file)) fd = $fopen(trace_file, "w");
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
  end

  function automatic string h(logic [31:0] v); return $sformatf("%08x", v); endfunction

  // Character output for the CPI runs: a store to 0x4000_0000 prints its low byte
  always @(posedge clk)
    if (rst_n && dmem_req_valid && dmem_req_ready && dmem_req_we && dmem_req_addr == 32'h4000_0000)
      $write("%c", dmem_req_wdata[7:0]);

  // Branch statistics for the CPI runs (whole run)
  longint n_branch = 0, n_mispredict = 0, n_jal = 0, n_jalr = 0;
  always @(posedge clk) if (rst_n && dut.ex_fire && !dut.ex_any_exc) begin
    if (dut.ex_ctrl.is_branch) n_branch++;
    if (dut.ex_ctrl.is_branch && dut.ex_redirect) n_mispredict++;
    if (dut.ex_ctrl.is_jal)  n_jal++;
    if (dut.ex_ctrl.is_jalr) n_jalr++;
  end

  always @(posedge clk) if (rst_n) begin
    cycles++;
    // WB record first: it is older than a trap in MEM in the same cycle
    if (tr_valid) begin
      retired++;
      if (fd != 0)
        $fdisplay(fd, "R %s %s %s %s %s",
          h(tr_pc), h(tr_insn),
          tr_rd_we     ? $sformatf("%0d:%s", tr_rd, h(tr_rd_val)) : "-",
          tr_st_valid  ? $sformatf("%s:%s:%0d", h(tr_st_addr), h(tr_st_data), tr_st_size) : "-",
          tr_csr_valid ? $sformatf("%03x:%s", tr_csr_addr, h(tr_csr_val)) : "-");
    end
    if (trap_valid && fd != 0)
      $fdisplay(fd, "T %0d %s %s", trap_cause, h(trap_epc), h(trap_tval));

    idle = tr_valid ? 0 : idle + 1;
    // The memory sees the tohost store when it accepts it; the store retires (and is
    // traced) only when its response comes back. End the test at its retirement.
    if (tr_valid && tr_st_valid && tr_st_addr == tohost_addr) done_seen = 1'b1;
    if (done_seen) begin
      if ($test$plusargs("CPI"))
        $display("CPI bht=%0d cycles=%0d retired=%0d cpi=%0.4f branches=%0d mispredicts=%0d jal=%0d jalr=%0d",
                 BHT_EN, cycles, retired, real'(cycles) / real'(retired), n_branch, n_mispredict, n_jal, n_jalr);
      if (tohost_value == 32'd1) $display("TEST PASSED (%0d instructions, %0d cycles)", retired, cycles);
      else begin
        $display("TEST FAILED: tohost = %0d (code %0d)", tohost_value, tohost_value >> 1);
        if (fd != 0) $fclose(fd);
        $fatal(1, "tohost fail");
      end
      if (fd != 0) $fclose(fd);
      $finish;
    end
    if (idle > 2000 || cycles > max_cycles) begin
      if (fd != 0) $fclose(fd);
      $fatal(1, "TEST FAILED: %s at cycle %0d, pc of last fetch %h",
             idle > 2000 ? "no instruction retired for 2000 cycles" : "MAX_CYCLES reached",
             cycles, imem_req_addr);
    end
  end
endmodule
