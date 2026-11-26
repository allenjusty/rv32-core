// Single-cycle multiplier for MUL, MULH, MULHSU, MULHU (EX stage).
// Both operands are extended to 33 bits (sign or zero) so one signed
// 33x33 multiply covers all four instructions.
module core_mul (
  input  logic [1:0]  op,      // funct3[1:0]: 00 MUL, 01 MULH, 10 MULHSU, 11 MULHU
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] y
);
  logic        a_signed, b_signed;
  logic signed [65:0] prod;   // 66 bits so the multiply itself is 66 bits wide
  assign a_signed = (op == 2'b01) || (op == 2'b10);
  assign b_signed = (op == 2'b01);
  assign prod = $signed({a_signed & a[31], a}) * $signed({b_signed & b[31], b});
  assign y = (op == 2'b00) ? prod[31:0] : prod[63:32];
endmodule
