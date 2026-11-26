// Testbench memory: 1 MiB at 0x8000_0000 with an instruction port and a data port.
// Random wait states on both ports (0 = no waits), set by the testbench:
//   iready_pct  chance (0-100) that the instruction port is NOT ready in a cycle
//   ilat_max    extra response latency 0..n cycles (on top of the minimum 1)
//   dready_pct, dlat_max   the same for the data port (minimum latency 0)
// The program is loaded from +HEX=<file> (objcopy -O verilog, addresses relative to the base).
// A store to +TOHOST=<hex addr> ends the test: tohost_done / tohost_value.
//
// Interrupt devices on the data port:
//   0x0200_0000  MSIP: bit 0 drives irq_software (same address as Spike's CLINT, so tests
//                that use it can still be compared with Spike)
//   0x0201_0000  random interrupt generator: raises irq_external / irq_timer at random
//                (irq_ext_pm / irq_tmr_pm = chance per cycle, per mille, 0 = never).
//                A line stays high until software writes 1 to its bit here (bit 0 external,
//                bit 1 timer). Reading returns {timer, external}. Not present in Spike.
module tb_mem #(
  parameter logic [31:0] BASE = 32'h8000_0000,
  parameter int          SIZE = 1 << 20
) (
  input  logic        clk,
  input  logic        rst_n,
  // instruction port
  input  logic        i_req_valid,
  output logic        i_req_ready,
  input  logic [31:0] i_req_addr,
  output logic        i_rsp_valid,
  output logic [31:0] i_rsp_rdata,
  // data port
  input  logic        d_req_valid,
  output logic        d_req_ready,
  input  logic [31:0] d_req_addr,
  input  logic        d_req_we,
  input  logic [3:0]  d_req_be,
  input  logic [31:0] d_req_wdata,
  output logic        d_rsp_valid,
  output logic [31:0] d_rsp_rdata,
  // test end
  output logic        tohost_done,
  output logic [31:0] tohost_value,
  // wait-state knobs
  input  int          iready_pct,
  input  int          ilat_max,
  input  int          dready_pct,
  input  int          dlat_max,
  // interrupts
  input  int          irq_ext_pm,
  input  int          irq_tmr_pm,
  output logic        irq_software,
  output logic        irq_timer,
  output logic        irq_external
);
  localparam logic [31:0] MSIP_ADDR   = 32'h0200_0000;
  localparam logic [31:0] IRQGEN_ADDR = 32'h0201_0000;
  logic [7:0] mem [SIZE];
  logic [31:0] tohost_addr;

  initial begin
    string hex;
    for (int i = 0; i < SIZE; i++) mem[i] = 8'h00;
    if ($value$plusargs("HEX=%s", hex)) $readmemh(hex, mem);
    else $display("tb_mem: no +HEX=<file> given, memory is empty");
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) tohost_addr = 32'hFFFF_FFFF;
  end

  function automatic logic [31:0] rd32(logic [31:0] addr);
    logic [31:0] o = addr - BASE;
    if (addr == MSIP_ADDR)   return {31'b0, irq_software};
    if (addr == IRQGEN_ADDR) return {30'b0, irq_timer, irq_external};
    o[1:0] = 2'b00;
    if (o >= SIZE) return 32'hDEAD_BEEF;      // outside RAM (tests must not do this)
    return {mem[o+3], mem[o+2], mem[o+1], mem[o]};
  endfunction

  // ---------------------------------------------------------- instruction port
  // ready is random each cycle and never depends on req_valid. The response comes
  // 1 + (0..ILAT_MAX) cycles after the request is accepted.
  int          i_wait;       // cycles left until the response; 0 = idle
  logic [31:0] i_addr_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      i_req_ready <= 1'b0;
      i_rsp_valid <= 1'b0;
      i_wait      <= 0;
    end else begin
      i_req_ready <= ($urandom_range(99) >= iready_pct);
      i_rsp_valid <= 1'b0;
      if (i_req_valid && i_req_ready) begin
        int lat;
        lat = $urandom_range(ilat_max);
        if (lat == 0) begin
          i_rsp_valid <= 1'b1;
          i_rsp_rdata <= rd32(i_req_addr);
        end else begin
          i_wait   <= lat;
          i_addr_q <= i_req_addr;
        end
      end else if (i_wait == 1) begin
        i_rsp_valid <= 1'b1;
        i_rsp_rdata <= rd32(i_addr_q);
        i_wait      <= 0;
      end else if (i_wait > 1) begin
        i_wait <= i_wait - 1;
      end
    end
  end

  // ---------------------------------------------------------- data port
  // latency 0 answers in the same cycle (combinational read)
  int          d_lat_next;   // latency for the next accepted request
  int          d_wait;       // -1 idle
  logic [31:0] d_rdata_q;
  logic        d_acc;
  assign d_acc = d_req_valid && d_req_ready;

  always_comb begin
    d_rsp_valid = 1'b0;
    d_rsp_rdata = d_rdata_q;
    if (d_acc && d_lat_next == 0) begin
      d_rsp_valid = 1'b1;
      d_rsp_rdata = rd32(d_req_addr);
    end else if (d_wait == 0) begin
      d_rsp_valid = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      d_req_ready  <= 1'b0;
      d_wait       <= -1;
      d_lat_next   <= 0;
      tohost_done  <= 1'b0;
      tohost_value <= '0;
      irq_software <= 1'b0;
      irq_timer    <= 1'b0;
      irq_external <= 1'b0;
    end else begin
      // random interrupt generator
      if (!irq_external && irq_ext_pm > 0 && $urandom_range(999) < irq_ext_pm) irq_external <= 1'b1;
      if (!irq_timer    && irq_tmr_pm > 0 && $urandom_range(999) < irq_tmr_pm) irq_timer    <= 1'b1;
      d_req_ready <= ($urandom_range(99) >= dready_pct);
      if (d_wait == 0) d_wait <= -1;
      else if (d_wait > 0) d_wait <= d_wait - 1;
      if (d_acc) begin
        if (d_lat_next != 0) begin
          d_wait    <= d_lat_next - 1;
          d_rdata_q <= rd32(d_req_addr);
        end
        d_lat_next <= $urandom_range(dlat_max);
        if (d_req_we) begin
          logic [31:0] o;
          o = d_req_addr - BASE;
          o[1:0] = 2'b00;
          if (o < SIZE)
            for (int b = 0; b < 4; b++)
              if (d_req_be[b]) mem[o+b] <= d_req_wdata[8*b +: 8];
          if (d_req_addr == MSIP_ADDR && d_req_be[0]) irq_software <= d_req_wdata[0];
          if (d_req_addr == IRQGEN_ADDR) begin
            if (d_req_wdata[0]) irq_external <= 1'b0;
            if (d_req_wdata[1]) irq_timer    <= 1'b0;
          end
          if (d_req_addr == tohost_addr) begin
            tohost_done  <= 1'b1;
            tohost_value <= d_req_wdata;
          end
        end
      end
    end
  end
endmodule
