module eval5_init_unit(
    input clock,
    input reset,
    input start,
    input [31:0] regA,
    input [31:0] regB,
    output reg busy,
    output reg done,
    output reg [4:0] next_regA,
    output reg [4:0] next_regB,
    output reg [38:0] base_rank_count_flat,
    output reg [11:0] base_suit_count_flat,
    output reg [12:0] base_rank_mask,
    output reg [51:0] base_suit_rank_mask_flat
);

reg [2:0] state;
reg [2:0] load_count;

reg [5:0] cards [4:0];

// registered state
reg [2:0] base_rank_count [12:0];
reg [2:0] base_suit_count [3:0];
reg [12:0] base_suit_mask [3:0];

// combinational build
reg [2:0] rank_count_next [12:0];
reg [2:0] suit_count_next [3:0];
reg [12:0] suit_mask_next [3:0];
reg [12:0] rank_mask_next;

integer i, k;


reg start_d;
wire start_pulse;

always @(posedge clock or posedge reset) begin
    if (reset) start_d <= 0;
    else       start_d <= start;
end

assign start_pulse = start & ~start_d;

always @(posedge clock or posedge reset) begin
    if (reset) begin
        busy <= 0;
        done <= 0;
        state <= 0;
        load_count <= 0;

        base_rank_count_flat <= 0;
        base_suit_count_flat <= 0;
        base_rank_mask <= 0;
        base_suit_rank_mask_flat <= 0;

        for (i = 0; i < 13; i = i + 1)
            base_rank_count[i] <= 0;

        for (i = 0; i < 4; i = i + 1) begin
            base_suit_count[i] <= 0;
            base_suit_mask[i] <= 0;
        end
    end else begin

        
        if (start_pulse) begin
            busy <= 1;
            done <= 0;
            state <= 1;
            load_count <= 0;

            base_rank_count_flat <= 0;
            base_suit_count_flat <= 0;
            base_rank_mask <= 0;
            base_suit_rank_mask_flat <= 0;

            for (i = 0; i < 13; i = i + 1)
                base_rank_count[i] <= 0;

            for (i = 0; i < 4; i = i + 1) begin
                base_suit_count[i] <= 0;
                base_suit_mask[i] <= 0;
            end

            next_regA <= 5'd1;
            next_regB <= 5'd2;
        end else begin
            case (state)

            0: begin
                busy <= 0;
                done <= 0;
            end

            1: begin
                cards[load_count] <= regA[5:0];
                if (load_count <= 2)
                    cards[load_count+1] <= regB[5:0];

                load_count <= load_count + 2;

                if (load_count == 0) begin
                    next_regA <= 5'd3;
                    next_regB <= 5'd4;
                end else if (load_count == 2) begin
                    next_regA <= 5'd5;
                    next_regB <= 5'd0;
                end else begin
                    next_regA <= 5'd6;
                    next_regB <= 5'd7;
                    state <= 2;
                end
            end

            2: begin
                for (i = 0; i < 13; i = i + 1)
                    rank_count_next[i] = 0;

                for (i = 0; i < 4; i = i + 1) begin
                    suit_count_next[i] = 0;
                    suit_mask_next[i] = 13'b0;
                end

                rank_mask_next = 0;

                for (i = 0; i < 5; i = i + 1) begin
                    rank_count_next[cards[i][5:2]] =
                        rank_count_next[cards[i][5:2]] + 1;

                    suit_count_next[cards[i][1:0]] =
                        suit_count_next[cards[i][1:0]] + 1;

                    suit_mask_next[cards[i][1:0]][cards[i][5:2]] = 1'b1;

                    rank_mask_next[cards[i][5:2]] = 1'b1;
                end

                state <= 3;
            end

            3: begin
                for (k = 0; k < 13; k = k + 1)
                    base_rank_count[k] <= rank_count_next[k];

                for (k = 0; k < 4; k = k + 1) begin
                    base_suit_count[k] <= suit_count_next[k];
                    base_suit_mask[k] <= suit_mask_next[k];
                end

                base_rank_mask <= rank_mask_next;
                state <= 4;
            end

            4: begin
                for (k = 0; k < 13; k = k + 1)
                    base_rank_count_flat[k*3 +: 3] <= base_rank_count[k];

                for (k = 0; k < 4; k = k + 1) begin
                    base_suit_count_flat[k*3 +: 3] <= base_suit_count[k];
                    base_suit_rank_mask_flat[k*13 +: 13] <= base_suit_mask[k];
                end

                state <= 5;
            end

            5: begin
                busy <= 0;
                done <= 1;
                state <= 6;
            end

            6: begin
                done <= 0;
                state <= 0;
            end

            endcase
        end
    end
end

endmodule

module eval7_run_unit(
    input clock,
    input reset,
    input start,
    input [31:0] regA,
    input [31:0] regB,
    input [38:0] base_rank_count_flat,
    input [11:0] base_suit_count_flat,
    input [12:0] base_rank_mask,
    output reg busy,
    output reg done,
    output reg [3:0] result
);

reg [1:0] state;

reg [3:0] pair_count;
reg [3:0] trip_count;
reg has_four;

reg has_flush;
reg has_straight;

integer i;
reg [2:0] count;
reg [2:0] straight_count;

wire [3:0] r6 = regA[5:2];
wire [1:0] s6 = regA[1:0];
wire [3:0] r7 = regB[5:2];
wire [1:0] s7 = regB[1:0];

reg start_d;
wire start_pulse;

always @(posedge clock or posedge reset) begin
    if (reset) start_d <= 0;
    else       start_d <= start;
end

assign start_pulse = start & ~start_d;


always @(*) begin
    pair_count = 0;
    trip_count = 0;
    has_four = 0;
    has_flush = 0;
    has_straight = 0;

    for (i = 0; i < 13; i = i + 1) begin
        count = base_rank_count_flat[i*3 +: 3]
              + (r6 == i)
              + (r7 == i);

        if (count == 4)
            has_four = 1;
        else if (count == 3)
            trip_count = trip_count + 1;
        else if (count == 2)
            pair_count = pair_count + 1;
    end

    for (i = 0; i < 4; i = i + 1) begin
        if ((base_suit_count_flat[i*3 +: 3]
            + (s6 == i)
            + (s7 == i)) >= 5)
            has_flush = 1;
    end

    for (i = 0; i < 9; i = i + 1) begin
        straight_count = 0;

        if (base_rank_count_flat[(i+0)*3 +: 3] + (r6 == i+0) + (r7 == i+0)) straight_count=straight_count+1;
        if (base_rank_count_flat[(i+1)*3 +: 3] + (r6 == i+1) + (r7 == i+1)) straight_count=straight_count+1;
        if (base_rank_count_flat[(i+2)*3 +: 3] + (r6 == i+2) + (r7 == i+2)) straight_count=straight_count+1;
        if (base_rank_count_flat[(i+3)*3 +: 3] + (r6 == i+3) + (r7 == i+3)) straight_count=straight_count+1;
        if (base_rank_count_flat[(i+4)*3 +: 3] + (r6 == i+4) + (r7 == i+4)) straight_count=straight_count+1;

        if (straight_count == 5)
            has_straight = 1;
    end

    if ((base_rank_count_flat[12*3 +:3] + (r6==12) + (r7==12)) &&
        (base_rank_count_flat[0*3 +:3]  + (r6==0)  + (r7==0))  &&
        (base_rank_count_flat[1*3 +:3]  + (r6==1)  + (r7==1))  &&
        (base_rank_count_flat[2*3 +:3]  + (r6==2)  + (r7==2))  &&
        (base_rank_count_flat[3*3 +:3]  + (r6==3)  + (r7==3)))
        has_straight = 1;
end

// FSM
always @(posedge clock or posedge reset) begin
    if (reset) begin
        busy <= 0;
        done <= 0;
        state <= 0;
        result <= 0;
    end else begin

        if (start_pulse) begin
            busy <= 1;
            done <= 0;
            state <= 1;
            result <= 0;
        end else begin
            case (state)

            0: begin
                busy <= 0;
                done <= 0;
            end

            1: state <= 2;

            2: begin
                if (has_four) result <= 7;
                else if (trip_count >=1 && pair_count>=1) result <= 6;
                else if (trip_count >=2) result <= 6;
                else if (has_flush) result <= 5;
                else if (has_straight) result <= 4;
                else if (trip_count >=1) result <= 3;
                else if (pair_count >=2) result <= 2;
                else if (pair_count ==1) result <= 1;
                else result <= 0;

                state <= 3;
            end

            3: begin
                busy <= 0;
                done <= 1;
                state <= 0;
            end

            endcase
        end
    end
end

endmodule