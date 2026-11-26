// Branch history table: 2-bit saturating counters, direction only.
// Read in ID with the branch PC, updated in EX with the real outcome.
// Counter: 0 strongly not taken, 1 weakly not taken, 2 weakly taken, 3 strongly taken.
module core_bht #(
  parameter int ENTRIES = 64
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] rd_pc,
  output logic [1:0]  rd_cnt,
  input  logic        upd_en,
  input  logic [31:0] upd_pc,
  input  logic        upd_taken
);
  localparam int IW = $clog2(ENTRIES);
  logic [1:0] cnt [ENTRIES];

  logic [IW-1:0] ri, ui;
  assign ri = rd_pc[IW+1:2];
  assign ui = upd_pc[IW+1:2];
  assign rd_cnt = cnt[ri];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < ENTRIES; i++) cnt[i] <= 2'b01;
    end else if (upd_en) begin
      if (upd_taken && cnt[ui] != 2'b11)       cnt[ui] <= cnt[ui] + 2'b01;
      else if (!upd_taken && cnt[ui] != 2'b00) cnt[ui] <= cnt[ui] - 2'b01;
    end
  end
endmodule
