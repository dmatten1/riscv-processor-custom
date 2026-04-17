/**
 * Behavorial multdiv module following spec outlined in the multdiv checkpoint document
 *
 * @author Vincent Chen
 */
module multdiv(
	data_operandA, data_operandB, 
	ctrl_MULT, ctrl_DIV, 
	clock, 
	data_result, data_exception, data_resultRDY);

    input [31:0] data_operandA, data_operandB;
    input ctrl_MULT, ctrl_DIV, clock;

    output [31:0] data_result;
    output data_exception, data_resultRDY;

    wire [31:0] data_result_mult, data_result_div;
    wire data_exception_mult, data_exception_div;
    wire data_resultRDY_mult, data_resultRDY_div;

    reg current_op = 1'b0;  // 0 for mult, 1 for div
    always @(posedge clock) begin
        if (ctrl_MULT) begin
            current_op <= 1'b0;
        end else if (ctrl_DIV) begin
            current_op <= 1'b1;
        end
    end

    mult mult_module(
        .data_operandA(data_operandA),
        .data_operandB(data_operandB),
        .ctrl_MULT(ctrl_MULT),
        .clock(clock),
        .data_result(data_result_mult),
        .data_exception(data_exception_mult),
        .data_resultRDY(data_resultRDY_mult)
    );

    div div_module(
        .data_operandA(data_operandA),
        .data_operandB(data_operandB),
        .ctrl_DIV(ctrl_DIV),
        .clock(clock),
        .data_result(data_result_div),
        .data_exception(data_exception_div),
        .data_resultRDY(data_resultRDY_div)
    );

    assign data_result = current_op ? data_result_div : data_result_mult;
    assign data_exception = current_op ? data_exception_div : data_exception_mult;
    assign data_resultRDY = current_op ? data_resultRDY_div : data_resultRDY_mult;

endmodule