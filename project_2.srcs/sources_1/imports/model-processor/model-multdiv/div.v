/**
 * Behavorial non-restoring divider
 *
 * @author Vincent Chen
 */

module div(
	data_operandA, data_operandB, 
	ctrl_DIV,
	clock, 
	data_result, data_exception, data_resultRDY);

    input [31:0] data_operandA, data_operandB;
    input ctrl_DIV, clock;

    output [31:0] data_result; 
    output data_exception, data_resultRDY;

    reg[31:0] pos_A = 32'b0;
    reg[31:0] pos_B = 32'b0;

    reg[63:0] result = 63'b0;
    reg[5:0] count = 6'b0;
    reg[1:0] state = 2'b00;

    // Change to output if remainder is needed
    wire[31:0] remainder = data_operandA[31] ? ~result[63:32] + 1 : result[63:32];

    assign data_resultRDY = (count == 6'd34);
    assign data_result = result[31:0];
    assign data_exception = (data_operandB == 32'd0);
    
    // Add two extra clock cycles for timing (no double-stacked additions per cycle)
    always @(posedge clock) begin
        if (ctrl_DIV) begin
            // Flip to positive for NRDI algorithm
            pos_A = data_operandA[31] ? ~data_operandA + 1 : data_operandA;
            pos_B = data_operandB[31] ? ~data_operandB + 1 : data_operandB;

            result = {32'b0, pos_A};
            count = 6'b0;
            state = 2'b00;
        end else if (count <= 6'd32) begin
            if (result[63]) begin
                result = result << 1;
                result[63:32] = result[63:32] + pos_B;
            end else begin
                result = result << 1;
                result[63:32] = result[63:32] - pos_B;
            end

            result[0] = ~result[63];
            state = 2'b01;
        end else begin
            result[31:0] = data_operandA[31] ^ data_operandB[31] ? ~result[31:0] + 1 : result[31:0];
            result[63:32] = result[63] ? result[63:32] + pos_B : result[63:32];
            state = 2'b10;
        end
        count = count + 1;
    end
endmodule