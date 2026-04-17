/**
 * Behavorial modified Booth's multiplier with bonus bit
 *
 * @author Vincent Chen
 */

module mult(
	data_operandA, data_operandB, 
	ctrl_MULT,
	clock, 
	data_result, data_exception, data_resultRDY);

    input [31:0] data_operandA, data_operandB;
    input ctrl_MULT, clock;

    output [31:0] data_result;
    output data_exception, data_resultRDY;

    // 64 bit result, extra Booth bit and extra bonus bit
    reg[65:0] result = 66'd0;
    reg[4:0] count = 5'd0;

    assign data_resultRDY = (count == 5'd16);
    assign data_result = result[32:1];
    assign data_exception = (|result[64:32]) & ~(&result[64:32]);
    
    always @(posedge clock) begin
        if (ctrl_MULT) begin
            result = {33'b0, data_operandB, 1'b0};
            count = 5'd0;
        end
        case (result[2:0])
            3'b000: result[65:33] = result[65:33];
            3'b001: result[65:33] = result[65:33] + {data_operandA[31], data_operandA};
            3'b010: result[65:33] = result[65:33] + {data_operandA[31], data_operandA};
            3'b011: result[65:33] = result[65:33] + {data_operandA[31:0], 1'b0};  // same as multiply by 2
            3'b100: result[65:33] = result[65:33] - {data_operandA[31:0], 1'b0};
            3'b101: result[65:33] = result[65:33] - {data_operandA[31], data_operandA};
            3'b110: result[65:33] = result[65:33] - {data_operandA[31], data_operandA};
            default: result[65:33] = result[65:33];
        endcase

        result = $signed(result) >>> 2;
        count = count + 1;
    end
endmodule