// Instruction decoder (ID stage). Pure combinational.
// Any encoding not listed in the spec sets `illegal`.
module core_decode
  import core_pkg::*;
(
  input  logic [31:0] instr,
  output ctrl_t       ctrl,
  output logic [31:0] imm
);
  logic [6:0] opcode, funct7;
  logic [2:0] funct3;
  assign opcode = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];

  // Immediates
  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{20{instr[31]}}, instr[31:20]};
  assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  assign imm_u = {instr[31:12], 12'b0};
  assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

  always_comb begin
    ctrl        = '0;
    ctrl.alu_op = ALU_ADD;
    ctrl.a_sel  = A_RS1;
    ctrl.funct3 = funct3;
    imm         = imm_i;

    unique case (opcode)
      OP_LUI: begin
        ctrl.a_sel = A_ZERO; ctrl.b_imm = 1'b1; ctrl.rd_we = 1'b1; imm = imm_u;
      end
      OP_AUIPC: begin
        ctrl.a_sel = A_PC; ctrl.b_imm = 1'b1; ctrl.rd_we = 1'b1; imm = imm_u;
      end
      OP_JAL: begin
        ctrl.is_jal = 1'b1; ctrl.rd_we = 1'b1; imm = imm_j;
      end
      OP_JALR: begin
        ctrl.is_jalr = 1'b1; ctrl.use_rs1 = 1'b1; ctrl.rd_we = 1'b1; ctrl.b_imm = 1'b1;
        ctrl.illegal = (funct3 != 3'b000);
      end
      OP_BRANCH: begin
        ctrl.is_branch = 1'b1; ctrl.use_rs1 = 1'b1; ctrl.use_rs2 = 1'b1; imm = imm_b;
        ctrl.illegal = (funct3 == 3'b010) || (funct3 == 3'b011);
      end
      OP_LOAD: begin
        ctrl.is_load = 1'b1; ctrl.use_rs1 = 1'b1; ctrl.rd_we = 1'b1; ctrl.b_imm = 1'b1;
        // LB LH LW LBU LHU
        ctrl.illegal = (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111);
      end
      OP_STORE: begin
        ctrl.is_store = 1'b1; ctrl.use_rs1 = 1'b1; ctrl.use_rs2 = 1'b1; ctrl.b_imm = 1'b1;
        imm = imm_s;
        ctrl.illegal = (funct3[2] == 1'b1) || (funct3 == 3'b011);
      end
      OP_IMM: begin
        ctrl.use_rs1 = 1'b1; ctrl.rd_we = 1'b1; ctrl.b_imm = 1'b1;
        unique case (funct3)
          3'b000: ctrl.alu_op = ALU_ADD;
          3'b010: ctrl.alu_op = ALU_SLT;
          3'b011: ctrl.alu_op = ALU_SLTU;
          3'b100: ctrl.alu_op = ALU_XOR;
          3'b110: ctrl.alu_op = ALU_OR;
          3'b111: ctrl.alu_op = ALU_AND;
          3'b001: begin
            ctrl.alu_op  = ALU_SLL;
            ctrl.illegal = (funct7 != 7'b0000000);
          end
          3'b101: begin
            ctrl.alu_op  = (funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
            ctrl.illegal = (funct7 != 7'b0000000) && (funct7 != 7'b0100000);
          end
          default: ;
        endcase
      end
      OP_OP: begin
        ctrl.use_rs1 = 1'b1; ctrl.use_rs2 = 1'b1; ctrl.rd_we = 1'b1;
        if (funct7 == 7'b0000001) begin
          ctrl.is_mul = !funct3[2];   // 000-011
          ctrl.is_div =  funct3[2];   // 100-111
        end else if (funct7 == 7'b0000000) begin
          unique case (funct3)
            3'b000: ctrl.alu_op = ALU_ADD;
            3'b001: ctrl.alu_op = ALU_SLL;
            3'b010: ctrl.alu_op = ALU_SLT;
            3'b011: ctrl.alu_op = ALU_SLTU;
            3'b100: ctrl.alu_op = ALU_XOR;
            3'b101: ctrl.alu_op = ALU_SRL;
            3'b110: ctrl.alu_op = ALU_OR;
            3'b111: ctrl.alu_op = ALU_AND;
            default: ;
          endcase
        end else if (funct7 == 7'b0100000 && funct3 == 3'b000) begin
          ctrl.alu_op = ALU_SUB;
        end else if (funct7 == 7'b0100000 && funct3 == 3'b101) begin
          ctrl.alu_op = ALU_SRA;
        end else begin
          ctrl.illegal = 1'b1;
        end
      end
      OP_FENCE: begin
        if (funct3 == 3'b000)      ;                      // FENCE: no-op
        else if (funct3 == 3'b001) ctrl.is_fencei = 1'b1; // FENCE.I: refetch
        else                       ctrl.illegal = 1'b1;
      end
      OP_SYSTEM: begin
        if (funct3 == 3'b000) begin
          unique case (instr)
            32'h0000_0073: ctrl.ecall   = 1'b1;
            32'h0010_0073: ctrl.ebreak  = 1'b1;
            32'h3020_0073: ctrl.is_mret = 1'b1;
            32'h1050_0073: ;                              // WFI: no-op
            default:       ctrl.illegal = 1'b1;
          endcase
        end else if (funct3 == 3'b100) begin
          ctrl.illegal = 1'b1;
        end else begin
          // CSR access. Register forms read rs1; immediate forms use the rs1 field as uimm.
          ctrl.is_csr  = 1'b1;
          ctrl.rd_we   = 1'b1;
          ctrl.use_rs1 = !funct3[2];
        end
      end
      default: ctrl.illegal = 1'b1;
    endcase

    // 16-bit encodings (low bits != 11) are not supported
    if (instr[1:0] != 2'b11) ctrl.illegal = 1'b1;

    // An illegal instruction has no other effect
    if (ctrl.illegal) begin
      ctrl.rd_we = 1'b0; ctrl.is_load = 1'b0; ctrl.is_store = 1'b0;
      ctrl.is_branch = 1'b0; ctrl.is_jal = 1'b0; ctrl.is_jalr = 1'b0;
      ctrl.is_mul = 1'b0; ctrl.is_div = 1'b0; ctrl.is_csr = 1'b0;
      ctrl.is_mret = 1'b0; ctrl.is_fencei = 1'b0; ctrl.ecall = 1'b0; ctrl.ebreak = 1'b0;
      ctrl.use_rs1 = 1'b0; ctrl.use_rs2 = 1'b0;
    end
  end
endmodule
