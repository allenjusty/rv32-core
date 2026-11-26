// 32 x 32 register file, 2 read ports, 1 write port. x0 is always 0.
// A read in the same cycle as a write to the same register returns the new value
// (WB-to-ID bypass).
module core_regfile (
  input  logic        clk,
  input  logic [4:0]  ra1,
  input  logic [4:0]  ra2,
  output logic [31:0] rd1,
  output logic [31:0] rd2,
  input  logic        we,
  input  logic [4:0]  wa,
  input  logic [31:0] wd
);
  logic [31:0] regs [1:31];

  always_ff @(posedge clk)
    if (we && wa != 5'd0) regs[wa] <= wd;

  assign rd1 = (ra1 == 5'd0) ? 32'd0 : (we && wa == ra1) ? wd : regs[ra1];
  assign rd2 = (ra2 == 5'd0) ? 32'd0 : (we && wa == ra2) ? wd : regs[ra2];
endmodule
