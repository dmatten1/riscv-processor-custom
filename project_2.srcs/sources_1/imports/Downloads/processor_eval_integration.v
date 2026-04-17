/**
 * Integration wrapper for eval5 and eval7 poker-hand evaluators.
 *
 * Design:
 *   - While an eval5/eval7 instruction sits in the decode stage, this module
 *     takes over the two regfile read-address ports and asserts eval_stall to
 *     freeze the rest of the pipeline.
 *   - eval5 sweeps r1-r5, latching rank/suit counts and masks for the base
 *     five cards (held inside eval5_init_unit).
 *   - eval7 then reads r6 and r7 and finishes the bit masking to produce the
 *     final hand category.
 *   - When eval7 finishes, eval_wb_we pulses so the processor can write the
 *     result back into the destination register (FD_RD of the eval7 insn).
 *
 * Note: straight flush / royal flush are intentionally not detected; the
 * wheel straight (A-2-3-4-5) is handled by the eval7 unit.
 */
module processor_eval_integration(
    input         clock,
    input         reset,

    input  [4:0]  d_op,            // decode-stage opcode
    input  [31:0] data_readRegA,
    input  [31:0] data_readRegB,

    output [4:0]  ctrl_readRegA_ovr,
    output [4:0]  ctrl_readRegB_ovr,
    output        read_override,   // high while we own the read ports

    output        eval_stall,      // high while an eval insn is executing

    output        eval_wb_we,      // 1-cycle pulse when eval7 result is ready
    output [4:0]  eval_wb_rd,
    output [31:0] eval_wb_data
);

    localparam EVAL5 = 5'b11100;
    localparam EVAL7 = 5'b11111;

    wire is_eval5 = (d_op == EVAL5);
    wire is_eval7 = (d_op == EVAL7);

    // Sub-unit status / handshake wires
    wire        eval5_busy, eval5_done;
    wire        eval7_busy, eval7_done;
    wire [4:0]  eval5_nextA, eval5_nextB;
    wire [3:0]  eval7_result;

    // Shared base-state wires produced by eval5 and consumed by eval7
    wire [38:0] base_rank_count_flat;
    wire [11:0] base_suit_count_flat;
    wire [12:0] base_rank_mask;
    wire [51:0] base_suit_rank_mask_flat;

    // Per-instruction handshake tracking. `fired` remembers that we have
    // already driven a start pulse for the current insn; `done_sticky`
    // remembers that the sub-unit has produced its result.
    reg eval5_fired, eval5_done_sticky;
    reg eval7_fired, eval7_done_sticky;

    wire eval5_start = is_eval5 && !eval5_fired && !eval5_done_sticky;
    wire eval7_start = is_eval7 && !eval7_fired && !eval7_done_sticky;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            eval5_fired       <= 1'b0;
            eval5_done_sticky <= 1'b0;
            eval7_fired       <= 1'b0;
            eval7_done_sticky <= 1'b0;
        end else begin
            // eval5 bookkeeping
            if (!is_eval5) begin
                eval5_fired       <= 1'b0;
                eval5_done_sticky <= 1'b0;
            end else if (eval5_done_sticky) begin
                // release cycle - clear so a back-to-back eval5 starts fresh
                eval5_fired       <= 1'b0;
                eval5_done_sticky <= 1'b0;
            end else begin
                if (eval5_start) eval5_fired       <= 1'b1;
                if (eval5_done)  eval5_done_sticky <= 1'b1;
            end

            // eval7 bookkeeping
            if (!is_eval7) begin
                eval7_fired       <= 1'b0;
                eval7_done_sticky <= 1'b0;
            end else if (eval7_done_sticky) begin
                eval7_fired       <= 1'b0;
                eval7_done_sticky <= 1'b0;
            end else begin
                if (eval7_start) eval7_fired       <= 1'b1;
                if (eval7_done)  eval7_done_sticky <= 1'b1;
            end
        end
    end

    // Drive regfile read addresses while an eval insn owns the decode stage.
    assign ctrl_readRegA_ovr = is_eval5 ? eval5_nextA :
                               is_eval7 ? 5'd6       :
                                          5'd0;
    assign ctrl_readRegB_ovr = is_eval5 ? eval5_nextB :
                               is_eval7 ? 5'd7       :
                                          5'd0;
    assign read_override     = is_eval5 || is_eval7;

    // Stall the rest of the pipeline until the sub-unit has finished.
    assign eval_stall = (is_eval5 && !eval5_done_sticky)
                     || (is_eval7 && !eval7_done_sticky);

    // Writeback pulse on the cycle that eval7 completes. d_rd still holds
    // the eval7 insn's destination because the pipeline is stalled.
    assign eval_wb_we   = is_eval7 && eval7_done;
    assign eval_wb_rd   = 5'd8;
    assign eval_wb_data = {28'b0, eval7_result};

    eval5_init_unit eval5_unit(
        .clock(clock),
        .reset(reset),
        .start(eval5_start),
        .regA(data_readRegA),
        .regB(data_readRegB),
        .busy(eval5_busy),
        .done(eval5_done),
        .next_regA(eval5_nextA),
        .next_regB(eval5_nextB),
        .base_rank_count_flat(base_rank_count_flat),
        .base_suit_count_flat(base_suit_count_flat),
        .base_rank_mask(base_rank_mask),
        .base_suit_rank_mask_flat(base_suit_rank_mask_flat)
    );

    eval7_run_unit eval7_unit(
        .clock(clock),
        .reset(reset),
        .start(eval7_start),
        .regA(data_readRegA),
        .regB(data_readRegB),
        .base_rank_count_flat(base_rank_count_flat),
        .base_suit_count_flat(base_suit_count_flat),
        .base_rank_mask(base_rank_mask),
        .busy(eval7_busy),
        .done(eval7_done),
        .result(eval7_result)
    );

endmodule
