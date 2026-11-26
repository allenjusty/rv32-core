// Iterative divider for DIV, DIVU, REM, REMU (EX stage).
// Restoring division on the magnitudes, one quotient bit per cycle (32 cycles),
// then the signs are fixed. Divide by zero and the signed overflow case follow
// the RISC-V rules and need no special path except divide by zero.
//
//   IDLE --start--> BUSY (32 cycles) --> DONE --ack--> IDLE
// The result is held in DONE until EX moves on (ack), because EX may be stalled.
module core_div (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        flush,   // kill a divide in progress
  input  logic        start,   // pulse in IDLE
  input  logic        ack,     // EX takes the result
  input  logic [1:0]  op,      // funct3[1:0]: 00 DIV, 01 DIVU, 10 REM, 11 REMU
  input  logic [31:0] a,       // dividend
  input  logic [31:0] b,       // divisor
  output logic        busy,
  output logic        done,
  output logic [31:0] y
);
  typedef enum logic [1:0] { IDLE, BUSY, DONE } state_e;
  state_e state;

  logic [31:0] quo, rem, divisor;
  logic [5:0]  count;
  logic        neg_quo, neg_rem, is_rem, by_zero;
  logic [31:0] a_orig;

  logic        sgn;
  assign sgn = !op[0];               // DIV, REM are signed

  logic [31:0] a_mag, b_mag;
  assign a_mag = (sgn && a[31]) ? -a : a;
  assign b_mag = (sgn && b[31]) ? -b : b;

  // One restoring step: shift the next dividend bit into the partial remainder
  logic [32:0] trial;
  assign trial = {rem, quo[31]} - {1'b0, divisor};

  always_ff @(posedge clk) begin
    if (!rst_n || flush) begin
      state <= IDLE;
    end else begin
      unique case (state)
        IDLE: if (start) begin
          state   <= BUSY;
          quo     <= a_mag;          // dividend bits shift out of quo, quotient bits in
          rem     <= '0;
          divisor <= b_mag;
          count   <= 6'd32;
          is_rem  <= op[1];
          by_zero <= (b == 32'd0);
          a_orig  <= a;
          neg_quo <= sgn && (a[31] ^ b[31]) && (b != 32'd0);
          neg_rem <= sgn && a[31];
        end
        BUSY: begin
          if (trial[32]) begin       // negative: keep the old remainder
            rem <= {rem[30:0], quo[31]};
            quo <= {quo[30:0], 1'b0};
          end else begin
            rem <= trial[31:0];
            quo <= {quo[30:0], 1'b1};
          end
          count <= count - 6'd1;
          if (count == 6'd1) state <= DONE;
        end
        DONE: if (ack) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end

  assign busy = (state == BUSY);
  assign done = (state == DONE);

  always_comb begin
    if (by_zero)     y = is_rem ? a_orig : 32'hFFFF_FFFF;
    else if (is_rem) y = neg_rem ? -rem : rem;
    else             y = neg_quo ? -quo : quo;
  end
endmodule
