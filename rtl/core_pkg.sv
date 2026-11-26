// Shared types for the RV32IM core
package core_pkg;

  localparam logic [31:0] RESET_PC = 32'h8000_0000;

  // Major opcodes (instr[6:0])
  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_IMM    = 7'b0010011;
  localparam logic [6:0] OP_OP     = 7'b0110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;

  // Exception codes (mcause)
  localparam logic [3:0] EXC_IADDR_MISALIGN = 4'd0;
  localparam logic [3:0] EXC_ILLEGAL        = 4'd2;
  localparam logic [3:0] EXC_BREAKPOINT     = 4'd3;
  localparam logic [3:0] EXC_LADDR_MISALIGN = 4'd4;
  localparam logic [3:0] EXC_SADDR_MISALIGN = 4'd6;
  localparam logic [3:0] EXC_ECALL_M        = 4'd11;

  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND
  } alu_op_e;

  typedef enum logic [1:0] { A_RS1, A_PC, A_ZERO } op_a_e;

  // Everything ID decides about one instruction
  typedef struct packed {
    alu_op_e     alu_op;
    op_a_e       a_sel;
    logic        b_imm;      // operand B = immediate (else rs2)
    logic        use_rs1;
    logic        use_rs2;
    logic        rd_we;      // writes rd (rd may still be x0)
    logic        is_load;
    logic        is_store;
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    logic        is_mul;     // MUL, MULH, MULHSU, MULHU
    logic        is_div;     // DIV, DIVU, REM, REMU
    logic        is_csr;
    logic        is_mret;
    logic        is_fencei;
    logic [2:0]  funct3;     // load/store size, branch type, M op, CSR op
    logic        illegal;
    logic        ecall;
    logic        ebreak;
  } ctrl_t;

endpackage
