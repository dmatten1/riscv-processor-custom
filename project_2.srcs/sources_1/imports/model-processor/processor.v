/**
 * Behavorial processor module following spec outlined in the processor checkpoint document
 */
module processor(
    // Control signals
    clock,                          // I: The master clock
    reset,                          // I: A reset signal

    // Imem
    address_imem,                   // O: The address of the data to get from imem
    q_imem,                         // I: The data from imem

    // Dmem
    address_dmem,                   // O: The address of the data to get or put from/to dmem
    data,                           // O: The data to write to dmem
    wren,                           // O: Write enable for dmem
    q_dmem,                         // I: The data from dmem

    // Regfile
    ctrl_writeEnable,               // O: Write enable for RegFile
    ctrl_writeReg,                  // O: Register to write to in RegFile
    ctrl_readRegA,                  // O: Register to read from port A of RegFile
    ctrl_readRegB,                  // O: Register to read from port B of RegFile
    data_writeReg,                  // O: Data to write to for RegFile
    data_readRegA,                  // I: Data from port A of RegFile
    data_readRegB                   // I: Data from port B of RegFile
        
        );

        // Control signals
        input clock, reset;
       
        // Imem
    output [31:0] address_imem;
        input [31:0] q_imem;

        // Dmem
        output [31:0] address_dmem, data;
        output wren;
        input [31:0] q_dmem;

        // Regfile
        output ctrl_writeEnable;
        output [4:0] ctrl_writeReg, ctrl_readRegA, ctrl_readRegB;
        output [31:0] data_writeReg;
        input [31:0] data_readRegA, data_readRegB;

    // [START] Useful opcodes
    localparam ALU_OP = 5'b00000;
    localparam ADDI = 5'b00101;
    localparam SW = 5'b00111;
    localparam LW = 5'b01000;
    localparam J = 5'b00001;
    localparam BNE = 5'b00010;
    localparam JAL = 5'b00011;
    localparam JR = 5'b00100;
    localparam BLT = 5'b00110;
    localparam BEX = 5'b10110;
    localparam SETX = 5'b10101;
    localparam EVAL5 = 5'b11100;
    localparam EVAL7 = 5'b11111;

    // ALU opcodes below
    localparam ADD = 5'b00000;
    localparam SUB = 5'b00001;
    localparam MULT = 5'b00110;
    localparam DIV = 5'b00111;
    // [END] Useful opcodes

        // ------------------------------ FETCH STAGE ------------------------------ //
    wire[31:0] FD_PC, FD_IR, branch_target;
    wire flush, branch_flush, stall, md_stall, lw_stall, double_md_stall, eval_stall;
    assign stall = md_stall || lw_stall || double_md_stall || eval_stall;
    assign flush = branch_flush || lw_stall || double_md_stall || eval_stall;

    assign address_imem = branch_target;

    register FD_PC_latch(.clock(~clock), .we(~stall), .reset(reset), .dataWrite(branch_target + 1), .dataRead(FD_PC));
    register FD_IR_latch(.clock(~clock), .we(~stall), .reset(reset), .dataWrite(q_imem), .dataRead(FD_IR));

    // ------------------------------ DECODE STAGE ------------------------------ //
    wire[31:0] DX_A, DX_B, DX_IMMED, DX_BRANCH_TARGET;
    wire[4:0] DX_OP, DX_RD, DX_RS1, DX_RS2, DX_ALU_OP, DX_SHAMT;
    wire[4:0] FD_RD, FD_RS1, FD_RS2, FD_OP, FD_ALU_OP;

    // [START] Stall, flush logic
    assign lw_stall = (DX_OP == LW) && (DX_RD != 5'b0) && (DX_RD == FD_RS1 || (DX_RD == FD_RS2 && FD_OP != SW)); // load to use stall
    assign double_md_stall = (DX_OP == ALU_OP && FD_OP == ALU_OP) && ((DX_ALU_OP == MULT && FD_ALU_OP == MULT) || (DX_ALU_OP == DIV && FD_ALU_OP == DIV));  // stall if two mults/divs in a row for simpler ctrl_MULT/ctrl_DIV logic
    // [END] Stall, flush logic

    // [START] Consistent decode table
    assign FD_OP = FD_IR[31:27];
    assign FD_RD = (FD_OP == ALU_OP || FD_OP == ADDI || FD_OP == LW) ? FD_IR[26:22] :
                (FD_OP == SW || FD_OP == J || FD_OP == BNE || FD_OP == JR || FD_OP == BLT || FD_OP == BEX || FD_OP == EVAL5 || FD_OP == EVAL7) ? 5'b0 :
                (FD_OP == JAL) ? 5'b11111 :
                (FD_OP == SETX) ? 5'b11110 :
                5'b0; 
    assign FD_RS1 = (FD_OP == ALU_OP || FD_OP == ADDI || FD_OP == LW || FD_OP == SW) ? FD_IR[21:17] :
                (FD_OP == J || FD_OP == JAL || FD_OP == SETX) ? 5'b0 :
                (FD_OP == BNE || FD_OP == BLT || FD_OP == JR) ? FD_IR[26:22] :
                (FD_OP == BEX) ? 5'b11110 :
                5'b0;
    assign FD_RS2 = (FD_OP == ALU_OP) ? FD_IR[16:12] :
                (FD_OP == ADDI || FD_OP == LW || FD_OP == J || FD_OP == JAL || FD_OP == JR || FD_OP == BEX || FD_OP == SETX) ? 5'b0 :
                (FD_OP == BNE || FD_OP == BLT) ? FD_IR[21:17] :
                (FD_OP == SW) ? FD_IR[26:22] :
                5'b0;
    assign FD_ALU_OP = (FD_OP == ALU_OP) ? FD_IR[6:2] :
                    (FD_OP == ADDI || FD_OP == LW || FD_OP == SW) ? 5'b00000 :
                    (FD_OP == BNE || FD_OP == BLT) ? 5'b00001 :
                    5'b0;
    // [END] Consistent decode table

    // [START] Calculate immediate and branch target - done in decode stage to meet timing for branch resolution
    wire[31:0] FD_IMMED, FD_BRANCH_TARGET;
    assign FD_IMMED = (FD_OP == JAL) ? FD_PC : {{15{FD_IR[16]}}, FD_IR[16:0]};  // sign extend immediate, or pick PC for jal
    assign FD_BRANCH_TARGET = (FD_OP == J || FD_OP == JAL || FD_OP == BEX) ? {5'b0, FD_IR[26:0]} : FD_PC + FD_IMMED;
    // [END] Calculate immediate and branch target
                   
    // [START] Eval5 / Eval7 integration
    wire        eval_read_override;
    wire [4:0]  eval_ctrl_readRegA, eval_ctrl_readRegB;
    wire        eval_wb_we;
    wire [4:0]  eval_wb_rd;
    wire [31:0] eval_wb_data;

    processor_eval_integration eval_inst(
        .clock(clock),
        .reset(reset),
        .d_op(FD_OP),
        .data_readRegA(data_readRegA),
        .data_readRegB(data_readRegB),
        .ctrl_readRegA_ovr(eval_ctrl_readRegA),
        .ctrl_readRegB_ovr(eval_ctrl_readRegB),
        .read_override(eval_read_override),
        .eval_stall(eval_stall),
        .eval_wb_we(eval_wb_we),
        .eval_wb_rd(eval_wb_rd),
        .eval_wb_data(eval_wb_data)
    );
    // [END] Eval5 / Eval7 integration

    assign ctrl_readRegA = eval_read_override ? eval_ctrl_readRegA : FD_RS1;
    assign ctrl_readRegB = eval_read_override ? eval_ctrl_readRegB : FD_RS2;
   
    register DX_A_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(data_readRegA), .dataRead(DX_A));
    register DX_B_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(data_readRegB), .dataRead(DX_B));
    register DX_IMMED_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(FD_IMMED), .dataRead(DX_IMMED));
    register DX_BRANCH_TARGET_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(FD_BRANCH_TARGET), .dataRead(DX_BRANCH_TARGET));
    // An eval insn is fully handled in the decode stage, so never let one
    // leak into the execute stage.
    wire fd_is_eval = (FD_OP == EVAL5) || (FD_OP == EVAL7);
    register #(.WIDTH(5)) DX_OP_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite((flush || fd_is_eval) ? 5'b0 : FD_OP), .dataRead(DX_OP));
    register #(.WIDTH(5)) DX_RD_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite((flush || fd_is_eval) ? 5'b0 : FD_RD), .dataRead(DX_RD));
    register #(.WIDTH(5)) DX_RS1_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(FD_RS1), .dataRead(DX_RS1));
    register #(.WIDTH(5)) DX_RS2_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(FD_RS2), .dataRead(DX_RS2));
    register #(.WIDTH(5)) DX_SHAMT_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(FD_IR[11:7]), .dataRead(DX_SHAMT));
    register #(.WIDTH(5)) DX_ALU_OP_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite((flush || fd_is_eval) ? 5'b0 : FD_ALU_OP), .dataRead(DX_ALU_OP));

    // ------------------------------ EXECUTE STAGE ------------------------------ //
    wire[31:0] XM_O, XM_B, XM_O_IN;
    wire[4:0] XM_RD, XM_RS2, XM_RD_IN, XM_OP;
    wire[31:0] alu_a, alu_b, alu_result, multdiv_result;
    wire uses_immed, isNotEqual, isLessThan, exception, ctrl_MULT, ctrl_DIV, dm_out, dd_out,multdiv_resultRDY, alu_exception,multdiv_exception, doing_mult, doing_div;

    // [START] bypassing logic
    wire MX_A, WX_A, MX_B, WX_B;
    wire[4:0] MW_RD; // pulled up from memory stage to use for bypass logic

    assign MX_A = (XM_RD != 5'b0) && (XM_RD == DX_RS1);
    assign WX_A = (MW_RD != 5'b0) && (MW_RD == DX_RS1);
    assign MX_B = (XM_RD != 5'b0) && (XM_RD == DX_RS2);
    assign WX_B = (MW_RD != 5'b0) && (MW_RD == DX_RS2);

    assign alu_a = MX_A ? XM_O : WX_A ? data_writeReg : DX_A;
    assign alu_b = MX_B ? XM_O : WX_B ? data_writeReg : DX_B;
    // [END] bypassing logic

    assign XM_RD_IN = exception && (DX_OP == ALU_OP || DX_OP == ADDI) ? 5'b11110 : DX_RD; // per spec, ignore overflow on non-R-type instructions
    assign XM_O_IN = (exception && DX_OP == ALU_OP) ? (
        DX_ALU_OP == ADD ? 32'd1 :
        DX_ALU_OP == SUB ? 32'd3 :
        DX_ALU_OP == MULT ? 32'd4 :
        DX_ALU_OP == DIV ? 32'd5 :
        32'd0
    ) : (exception && DX_OP == ADDI) ? 32'd2 :
    (doing_mult || doing_div) ? multdiv_result : alu_result;  // select exception, multdiv result, or alu result

    assign uses_immed = (DX_OP == ADDI || DX_OP == LW || DX_OP == SW || DX_OP == JAL || DX_OP == SETX);  // Note: top few bits of setx target are chopped off to make this code cleaner, but they are likely not used.
    assign exception = (doing_mult || doing_div) ? multdiv_exception : alu_exception;

    alu alu_module(.data_operandA(alu_a), .data_operandB(uses_immed ? DX_IMMED : alu_b), .ctrl_ALUopcode(DX_ALU_OP), .ctrl_shiftamt(DX_SHAMT), .data_result(alu_result), .isNotEqual(isNotEqual), .isLessThan(isLessThan), .overflow(alu_exception));

    // [START] Multdiv
    assign doing_mult = (DX_OP == ALU_OP && DX_ALU_OP == MULT);
    assign doing_div = (DX_OP == ALU_OP && DX_ALU_OP == DIV);
    assign md_stall = (doing_mult || doing_div) && ~multdiv_resultRDY;
    assign ctrl_MULT = ~dm_out & doing_mult; // asserts high for one clock cycle
    assign ctrl_DIV = ~dd_out & doing_div; // asserts high for one clock cycle

    dffe_ref ctrl_MULT_latch(.q(dm_out), .d(doing_mult), .clk(clock), .en(1'b1), .clr(reset));
    dffe_ref ctrl_DIV_latch(.q(dd_out), .d(doing_div), .clk(clock), .en(1'b1), .clr(reset));
   
    multdiv multdiv_module(.data_operandA(alu_a), .data_operandB(alu_b), .ctrl_MULT(ctrl_MULT), .ctrl_DIV(ctrl_DIV), .clock(clock), .data_result(multdiv_result), .data_exception(multdiv_exception), .data_resultRDY(multdiv_resultRDY));
    // [END] Multdiv

    register XM_O_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(XM_O_IN), .dataRead(XM_O));
    register XM_B_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(alu_b), .dataRead(XM_B));
    register #(.WIDTH(5)) XM_OP_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(DX_OP), .dataRead(XM_OP));
    register #(.WIDTH(5)) XM_RD_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(XM_RD_IN), .dataRead(XM_RD));
    register #(.WIDTH(5)) XM_RS2_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(DX_RS2), .dataRead(XM_RS2));

    // [START] Branch resolution
    wire comp_branch_taken, bex_taken;

    assign branch_flush = comp_branch_taken || bex_taken || branch_target != FD_PC;
    assign comp_branch_taken = (DX_OP == BNE && isNotEqual) || (DX_OP == BLT && isLessThan);
    assign bex_taken = (DX_OP == BEX && isNotEqual);
    assign branch_target = (DX_OP == J || DX_OP == JAL || bex_taken || comp_branch_taken) ? DX_BRANCH_TARGET :
                            (DX_OP == JR) ? alu_a :
                            FD_PC;
    // [END] Branch resolution

    // ------------------------------ MEMORY STAGE ------------------------------ //
    wire [31:0] MW_O, MW_D;
    wire [4:0] MW_OP;
    assign address_dmem = XM_O;
    assign wren = (XM_OP == SW);

    // [START] bypassing logic
    wire WM_B;
    assign WM_B = (MW_RD != 5'b0) && (MW_RD == XM_RS2);
    assign data = WM_B ? data_writeReg : XM_B;
    // [END] bypassing logic
   
    register MW_O_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(XM_O), .dataRead(MW_O));
    register MW_D_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(q_dmem), .dataRead(MW_D));
    register #(.WIDTH(5)) MW_OP_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(XM_OP), .dataRead(MW_OP));
    register #(.WIDTH(5)) MW_RD_latch(.clock(~clock), .we(~md_stall), .reset(reset), .dataWrite(XM_RD), .dataRead(MW_RD));

    // ------------------------------ WRITEBACK STAGE ------------------------------ //
    // Eval7 commits directly from the decode stage when its FSM completes,
    // bypassing the normal W-stage path. eval_wb_we only pulses on the cycle
    // the result is produced, so it cannot collide with the normal pipeline.
    assign data_writeReg = eval_wb_we ? eval_wb_data :
                           (MW_OP == LW) ? MW_D : MW_O;
    assign ctrl_writeEnable = eval_wb_we ||
                              (MW_OP == ALU_OP || MW_OP == ADDI || MW_OP == LW || MW_OP == JAL || MW_OP == JR || MW_OP == SETX);
    assign ctrl_writeReg = eval_wb_we ? eval_wb_rd : MW_RD;

endmodule
