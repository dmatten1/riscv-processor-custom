/**
 * Behavorial ALU following spec outlined in the ALU checkpoint document
 *
 * @author Vincent Chen
 */
module alu(data_operandA, data_operandB, ctrl_ALUopcode, ctrl_shiftamt, data_result, isNotEqual, isLessThan, overflow);
        
    input [31:0] data_operandA, data_operandB;
    input [4:0] ctrl_ALUopcode, ctrl_shiftamt;

    output [31:0] data_result;
    output isNotEqual, isLessThan, overflow;

    wire opB_sign;
    wire [31:0] sra_result, sub_result;

    assign opB_sign = ctrl_ALUopcode[0] ? ~data_operandB[31] : data_operandB[31];
    assign sra_result = $signed(data_operandA) >>> ctrl_shiftamt;
    assign sub_result = data_operandA - data_operandB;
    assign data_result = (ctrl_ALUopcode == 5'b00000) ? data_operandA + data_operandB :
                         (ctrl_ALUopcode == 5'b00001) ? sub_result :
                         (ctrl_ALUopcode == 5'b00010) ? data_operandA & data_operandB :
                         (ctrl_ALUopcode == 5'b00011) ? data_operandA | data_operandB :
                         (ctrl_ALUopcode == 5'b00100) ? data_operandA << ctrl_shiftamt :
                         (ctrl_ALUopcode == 5'b00101) ? sra_result :
                         32'b0;

    assign isNotEqual = |sub_result;
    assign isLessThan = sub_result[31] ^ overflow;
    assign overflow = (ctrl_ALUopcode == 5'b00000 || ctrl_ALUopcode == 5'b00001) &&
                      ((data_operandA[31] != opB_sign) ? 1'b0 : data_operandA[31] ^ data_result[31]);

endmodule