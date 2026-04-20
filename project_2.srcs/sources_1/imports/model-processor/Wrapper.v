`timescale 1ns / 1ps
/**
 * FPGA wrapper: processor + memories + MMIO + VGA.
 * MMIO 4411..4418 (0x1133..0x113A): each address is one VGA "line slot".
 *   sw $rN, (4411 + i)($0)   stores $rN as a raw 32-bit value into slot i.
 *   The VGA renderer draws each slot as a 3-digit decimal (0..999), each on
 *   its own row, top-left, using vga_digit_font.mem.
 * (Add the .mem file + VGA pins to the Vivado project; see lab7-8_kit constraints.)
 **/
module Wrapper (
    input clk_100mhz,
    input BTNU,
    input BTNR,              // Nexys A7 pin M17: "simulate / run" button
    input rfid_rx,
    input [15:0] SW,
    output [15:0] LED,

    output VGA_HS,
    output VGA_VS,
    output [3:0] VGA_R,
    output [3:0] VGA_G,
    output [3:0] VGA_B,

    output host_uart_tx
);
    wire clk, reset;
    assign clk = clk_100mhz;
    assign reset = BTNU;

    wire rwe, mwe;
    wire [4:0] rd, rs1, rs2;
    wire [31:0] instAddr, instData,
        rData, regA, regB,
        memAddr, memDataIn, memDataOut, q_dmem, data;

    reg [15:0] SW_Q, SW_M;

    wire io_sw_read;
    wire io_rfid_status_read;
    wire io_rfid_facility_read;
    wire io_rfid_card_read;
    wire io_rfid_ctrl_write;
    wire io_uart_stat_read;
    wire io_uart_tx_write;
    wire io_playing_card_read;
    wire io_playing_card_status_read;

    wire [7:0] uart_byte;
    wire uart_byte_valid;
    wire [39:0] rfid_tag_data;
    wire [7:0] rfid_checksum_rx, rfid_checksum_calc;
    wire [15:0] rfid_facility, rfid_card;
    wire rfid_parser_checksum_ok, rfid_tag_valid_pulse;
    wire rfid_tag_ready, rfid_checksum_ok, rfid_overflow;
    wire [15:0] rfid_facility_latched, rfid_card_latched;
    wire [39:0] rfid_raw_data;
    wire [47:0] rfid_raw_hex;
    wire [31:0] rfid_status_reg, rfid_facility_reg, rfid_card_reg;

    wire        deck_mapped;
    wire [31:0] card_binary;
    wire [31:0] playing_card_reg;
    wire [31:0] playing_card_status_reg;

    wire uart_tx_busy;
    wire [31:0] mmio_read_data;

    wire clock;
    wire locked;
    wire sys_reset;
    reg locked_meta, locked_sync;
    reg pll_lock_seen;

    clk_wiz_0 pll (.clk_out1(clock), .reset(reset), .locked(locked), .clk_in1(clk));

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            locked_meta   <= 1'b0;
            locked_sync   <= 1'b0;
            pll_lock_seen <= 1'b0;
        end else begin
            locked_meta <= locked;
            locked_sync <= locked_meta;
            if (locked_sync)
                pll_lock_seen <= 1'b1;
        end
    end

    assign sys_reset = reset | ~pll_lock_seen;

    // --- MMIO ADDRESS MAP ---
    assign io_sw_read                  = (memAddr == 32'd4096);
    assign io_rfid_status_read         = (memAddr == 32'd4098);
    assign io_rfid_facility_read       = (memAddr == 32'd4099);
    assign io_rfid_card_read           = (memAddr == 32'd4100);
    assign io_rfid_ctrl_write          = (memAddr == 32'd4101) && mwe && memDataIn[0];
    assign io_uart_stat_read           = (memAddr == 32'd4106);
    assign io_uart_tx_write            = (memAddr == 32'd4107) && mwe;
    assign io_playing_card_read        = (memAddr == 32'd4108);
    assign io_playing_card_status_read = (memAddr == 32'd4109);
    // Push buttons MMIO: bit0 = BTNR (simulate/run). Address 0x1006 (4102).
    wire io_btn_read                   = (memAddr == 32'd4102);
    // VGA display occupies a contiguous range so each address is its own line.
    //   4411..4418 (VGA_PROB_BASE..+7): 8 hand-probability percentages.
    //   4419..4425 (VGA_CARD_BASE..+6): 7 raw card indices ($1..$7, 0..51
    //                                    or -1 if unscanned). Rendered as
    //                                    2-char rank+suit on the BOARD/HOLE
    //                                    rows by the renderer.
    localparam [31:0] VGA_BASE = 32'd4411;
    localparam        VGA_PROB_SLOTS = 8;
    localparam        VGA_CARD_SLOTS = 7;
    localparam        VGA_SLOTS = VGA_PROB_SLOTS + VGA_CARD_SLOTS;  // 15
    wire io_vga_display_read           = (memAddr >= VGA_BASE) && (memAddr < VGA_BASE + VGA_SLOTS);
    // PIPELINE-ALIGNED SIGNALS
    reg [31:0] memAddr_d;
    reg [31:0] memDataIn_d;
    reg        mwe_d;
 
    always @(posedge clock) begin
        memAddr_d   <= memAddr;
        memDataIn_d <= memDataIn;
        mwe_d       <= mwe;
    end

    // VGA display latch: same-cycle MEM store (addr + wren + wrdata).
    wire        io_vga_display_hit = io_vga_display_read && mwe;
    wire [3:0]  io_vga_slot        = memAddr[3:0] - VGA_BASE[3:0];

    // Match LED: drive LED register from the same delayed MEM bus so data
    // lines up with the address that triggered the store.
    wire io_led_write_sync;
    assign io_led_write_sync = (memAddr_d == 32'd4097) && mwe_d;

    always @(negedge clock) begin
        SW_M <= SW;
        SW_Q <= SW_M;
    end

    // Double-flop synchronizer for BTNR (asynchronous input).
    reg btnr_meta, btnr_sync;
    always @(posedge clock) begin
        btnr_meta <= BTNR;
        btnr_sync <= btnr_meta;
    end
    wire [31:0] btn_status_reg = {31'd0, btnr_sync};

    reg [15:0] led_regs;

    // Raw VGA values - one slot per memory address (4411..4418).
    reg [31:0] vga_display_value [0:VGA_SLOTS-1];
    reg [VGA_SLOTS-1:0] vga_display_valid;
    // Flatten the slot array so we can pass it as one bus to the renderer.
    wire [VGA_SLOTS*32-1:0] vga_display_flat;
    genvar gi;
    generate
        for (gi = 0; gi < VGA_SLOTS; gi = gi + 1) begin: g_vga_pack
            assign vga_display_flat[gi*32 +: 32] = vga_display_value[gi];
        end
    endgenerate

    wire       vga_active;
    wire       vga_screen_end;
    wire [9:0] vga_x;
    wire [8:0] vga_y;
    wire [11:0] vga_rgb;

    VGATimingGenerator #(
        .HEIGHT(480),
        .WIDTH(640)
    ) u_vga_timing (
        .clk25(clock),
        .reset(sys_reset),
        .screenEnd(vga_screen_end),
        .active(vga_active),
        .hSync(VGA_HS),
        .vSync(VGA_VS),
        .x(vga_x),
        .y(vga_y)
    );

    //----------------------------------------------------------------------
    // Preflop chart lookup (auto-displayed below the HOLE row).
    //
    // Inputs (all combinational):
    //   hole1_raw / hole2_raw : raw 6-bit deck index stored in
    //     vga_display_value[8] / vga_display_value[9] (i.e. $1 / $2).
    //   SW_Q[15:13] : hero position,     encoded as 1..6 (UTG..BB).
    //   SW_Q[2:0]   : villain position,  encoded as 1..6 (UTG..BB).
    //   SW_Q[8:7]   : facing action,     0=UNOPENED, 1=ONE_RAISE, 2=THREE_BET.
    //
    // The ROM is addressed by {pos[2:0], villain[2:0], action[1:0], hand[7:0]}.
    // `hand_idx` is computed from the two hole cards using a 169-entry
    // "natural" ordering (pairs | suited | offsuit) - same order
    // build_chart_rom.py produces. Result is latched into a small 4-entry
    // "preflop" bus that feeds 3 additional rows in the VGA renderer.
    //----------------------------------------------------------------------
    wire [5:0] hole1_raw = vga_display_value[VGA_PROB_SLOTS + 0][5:0];
    wire [5:0] hole2_raw = vga_display_value[VGA_PROB_SLOTS + 1][5:0];
    wire       hole1_vld = vga_display_valid[VGA_PROB_SLOTS + 0];
    wire       hole2_vld = vga_display_valid[VGA_PROB_SLOTS + 1];

    wire [3:0] h1_rank = hole1_raw[5:2];
    wire [1:0] h1_suit = hole1_raw[1:0];
    wire [3:0] h2_rank = hole2_raw[5:2];
    wire [1:0] h2_suit = hole2_raw[1:0];

    wire       is_pair = (h1_rank == h2_rank);
    wire       is_suited = (h1_suit == h2_suit);
    wire [3:0] hi_rank = (h1_rank > h2_rank) ? h1_rank : h2_rank;
    wire [3:0] lo_rank = (h1_rank > h2_rank) ? h2_rank : h1_rank;

    // block_start table: 78 - hi*(hi+1)/2 for the "natural" non-pair ordering.
    reg [7:0] nonpair_block_start;
    always @(*) begin
        case (hi_rank)
            4'd12: nonpair_block_start = 8'd0;
            4'd11: nonpair_block_start = 8'd12;
            4'd10: nonpair_block_start = 8'd23;
            4'd9:  nonpair_block_start = 8'd33;
            4'd8:  nonpair_block_start = 8'd42;
            4'd7:  nonpair_block_start = 8'd50;
            4'd6:  nonpair_block_start = 8'd57;
            4'd5:  nonpair_block_start = 8'd63;
            4'd4:  nonpair_block_start = 8'd68;
            4'd3:  nonpair_block_start = 8'd72;
            4'd2:  nonpair_block_start = 8'd75;
            4'd1:  nonpair_block_start = 8'd77;
            default: nonpair_block_start = 8'd0;
        endcase
    end

    wire [7:0] nonpair_idx = nonpair_block_start + ({4'b0, hi_rank} - 8'd1) - {4'b0, lo_rank};
    wire [7:0] suited_idx  = 8'd13  + nonpair_idx;         // 13..90
    wire [7:0] offsuit_idx = 8'd91  + nonpair_idx;         // 91..168
    wire [7:0] pair_idx    = 8'd12  - {4'b0, h1_rank};     // AA=0 (rank 12), 22=12 (rank 0)
    wire [7:0] hand_idx    = is_pair   ? pair_idx   :
                             is_suited ? suited_idx :
                                         offsuit_idx;

    // Switches (one-hot, left-most switch in each field is UTG / RFI):
    //   Hero position field:    SW[15:10]  one-hot, SW[15]=UTG .. SW[10]=BB
    //   Villain position field: SW[5:0]    one-hot, SW[5]=UTG  .. SW[0]=BB
    //   Action field:           SW[8:6]    one-hot, SW[8]=RFI, SW[7]=OPEN,
    //                                      SW[6]=3BET
    // Exactly one bit per field must be set. Anything else (zero or
    // multiple bits on) drives switches_ok=0 and the POS row prints
    // "INVALID" / preflop rows stay hidden.
    wire [5:0] hero_oh    = SW_Q[15:10];
    wire [5:0] villain_oh = SW_Q[5:0];
    wire [2:0] action_oh  = SW_Q[8:6];

    reg [2:0] hero_pos;
    reg       hero_pos_vld;
    always @(*) begin
        case (hero_oh)
            6'b100000: begin hero_pos = 3'd0; hero_pos_vld = 1'b1; end  // UTG
            6'b010000: begin hero_pos = 3'd1; hero_pos_vld = 1'b1; end  // HJ
            6'b001000: begin hero_pos = 3'd2; hero_pos_vld = 1'b1; end  // CO
            6'b000100: begin hero_pos = 3'd3; hero_pos_vld = 1'b1; end  // BTN
            6'b000010: begin hero_pos = 3'd4; hero_pos_vld = 1'b1; end  // SB
            6'b000001: begin hero_pos = 3'd5; hero_pos_vld = 1'b1; end  // BB
            default:   begin hero_pos = 3'd0; hero_pos_vld = 1'b0; end
        endcase
    end

    reg [2:0] villain_pos;
    reg       villain_pos_vld;
    always @(*) begin
        case (villain_oh)
            6'b100000: begin villain_pos = 3'd0; villain_pos_vld = 1'b1; end  // UTG
            6'b010000: begin villain_pos = 3'd1; villain_pos_vld = 1'b1; end  // HJ
            6'b001000: begin villain_pos = 3'd2; villain_pos_vld = 1'b1; end  // CO
            6'b000100: begin villain_pos = 3'd3; villain_pos_vld = 1'b1; end  // BTN
            6'b000010: begin villain_pos = 3'd4; villain_pos_vld = 1'b1; end  // SB
            6'b000001: begin villain_pos = 3'd5; villain_pos_vld = 1'b1; end  // BB
            default:   begin villain_pos = 3'd0; villain_pos_vld = 1'b0; end
        endcase
    end

    reg [1:0] facing_action_sw;
    reg       action_sw_vld;
    always @(*) begin
        case (action_oh)
            3'b100: begin facing_action_sw = 2'd0; action_sw_vld = 1'b1; end  // RFI (UNOPENED)
            3'b010: begin facing_action_sw = 2'd1; action_sw_vld = 1'b1; end  // OPEN (ONE_RAISE)
            3'b001: begin facing_action_sw = 2'd2; action_sw_vld = 1'b1; end  // 3BET (THREE_BET)
            default: begin facing_action_sw = 2'd0; action_sw_vld = 1'b0; end
        endcase
    end

    wire switches_ok = hero_pos_vld && villain_pos_vld && action_sw_vld;

    wire [15:0] chart_addr = {hero_pos, villain_pos, facing_action_sw, hand_idx};
    wire [31:0] chart_word;
    chart_rom u_chart_rom (
        .clock(clock),
        .addr(chart_addr),
        .q(chart_word)
    );

    // Unpack ROM word.
    wire        chart_entry_valid = chart_word[31];
    wire [6:0]  preflop_size      = chart_word[30:24];
    wire [7:0]  preflop_raise     = chart_word[23:16];
    wire [7:0]  preflop_call      = chart_word[15:8];
    wire [7:0]  preflop_fold      = chart_word[7:0];
    // Rows only show up once both hole cards are scanned, the switches are
    // in range, and the ROM entry itself is marked valid.
    wire        preflop_valid = hole1_vld && hole2_vld && switches_ok && chart_entry_valid;

    vga_decimal_text_multi #(
        .PROB_SLOTS(VGA_PROB_SLOTS),
        .CARD_SLOTS(VGA_CARD_SLOTS)
    ) u_vga_text (
        .active(vga_active),
        .px(vga_x),
        .py(vga_y),
        .values_flat(vga_display_flat[VGA_PROB_SLOTS*32-1:0]),
        .valid_mask(vga_display_valid[VGA_PROB_SLOTS-1:0]),
        .card_values_flat(vga_display_flat[VGA_SLOTS*32-1 -: VGA_CARD_SLOTS*32]),
        .card_valid_mask(vga_display_valid[VGA_SLOTS-1 -: VGA_CARD_SLOTS]),
        .preflop_fold(preflop_fold),
        .preflop_call(preflop_call),
        .preflop_raise(preflop_raise),
        .preflop_size_tens(preflop_size),
        .preflop_valid(preflop_valid),
        .pos_hero(hero_pos),
        .pos_villain(villain_pos),
        .pos_action(facing_action_sw),
        .pos_switches_ok(switches_ok),
        .rgb12(vga_rgb)
    );

    assign VGA_R = vga_rgb[11:8];
    assign VGA_G = vga_rgb[7:4];
    assign VGA_B = vga_rgb[3:0];

    reg [22:0] rfid_read_pulse_cnt;
    wire rfid_read_glow = (rfid_read_pulse_cnt != 23'd0);

    uart_rx #(
        .CLK_HZ(25000000),
        .BAUD(9600)
    ) rfid_uart_rx (
        .clock(clock),
        .reset(sys_reset),
        .rx(rfid_rx),
        .data_out(uart_byte),
        .data_valid(uart_byte_valid)
    );

    always @(posedge clock or posedge sys_reset) begin
        if (sys_reset)
            rfid_read_pulse_cnt <= 23'd0;
        else begin
            if (uart_byte_valid)
                rfid_read_pulse_cnt <= 23'd5_000_000;
            else if (rfid_read_pulse_cnt != 23'd0)
                rfid_read_pulse_cnt <= rfid_read_pulse_cnt - 23'd1;
        end
    end

    // --- HARDWARE WRITE LOGIC ---
    integer vi;
    always @(posedge clock or posedge sys_reset) begin
        if (sys_reset) begin
            led_regs          <= 16'd0;
            vga_display_valid <= {VGA_SLOTS{1'b0}};
            for (vi = 0; vi < VGA_SLOTS; vi = vi + 1)
                vga_display_value[vi] <= 32'd0;
        end else begin
            if (io_led_write_sync)
                led_regs <= memDataIn_d[15:0];

            if (io_vga_display_hit) begin
                vga_display_value[io_vga_slot] <= memDataIn;
                vga_display_valid[io_vga_slot] <= 1'b1;
            end
        end
    end

    // LED layout now mirrors the three one-hot switch fields so the LEDs
    // over each field light in a dedicated color (wired up on the board,
    // not in Verilog - Nexys A7 LD0..LD15 are single-color, so the color
    // comes from whatever LED bank / filter is physically above each
    // group of switches):
    //
    //   LED[15:10] = SW[15:10]  (hero position   - green over the hero
    //                            switch field)
    //   LED[9]     = 0          (unused gap; SW[9] is not part of any
    //                            field and has no chart meaning)
    //   LED[8:6]   = SW[8:6]    (facing action   - blue over the action
    //                            switch field)
    //   LED[5:0]   = SW[5:0]    (villain position - red over the villain
    //                            switch field)
    //
    // Each field is one-hot, so under normal use exactly one LED lights
    // per field. Zero or multiple LEDs on in a field means switches_ok
    // is false and the POS: row on the VGA will print "INVALID".
    assign LED = {SW_Q[15:10], 1'b0, SW_Q[8:6], SW_Q[5:0]};

    uart_tx #(
        .CLK_HZ(25000000),
        .BAUD(9600)
    ) host_uart (
        .clock(clock),
        .reset(sys_reset),
        .data(memDataIn[7:0]),
        .wr(io_uart_tx_write),
        .busy(uart_tx_busy),
        .tx(host_uart_tx)
    );

    rfid_parser rfid_ascii_parser (
        .clock(clock),
        .reset(sys_reset),
        .rx_byte(uart_byte),
        .rx_valid(uart_byte_valid),
        .tag_data(rfid_tag_data),
        .checksum_rx(rfid_checksum_rx),
        .checksum_calc(rfid_checksum_calc),
        .facility(rfid_facility),
        .card(rfid_card),
        .checksum_ok(rfid_parser_checksum_ok),
        .tag_valid_pulse(rfid_tag_valid_pulse)
    );

    rfid_mmio rfid_regs (
        .clock(clock),
        .reset(sys_reset),
        .clear_tag(io_rfid_ctrl_write),
        .tag_valid_pulse(rfid_tag_valid_pulse),
        .parser_checksum_ok(rfid_parser_checksum_ok),
        .parser_checksum_rx(rfid_checksum_rx),
        .parser_facility(rfid_facility),
        .parser_card(rfid_card),
        .parser_tag_data(rfid_tag_data),
        .tag_ready(rfid_tag_ready),
        .checksum_ok(rfid_checksum_ok),
        .overflow(rfid_overflow),
        .facility(rfid_facility_latched),
        .card(rfid_card_latched),
        .raw_data(rfid_raw_data),
        .raw_hex(rfid_raw_hex),
        .status_reg(rfid_status_reg),
        .facility_reg(rfid_facility_reg),
        .card_reg(rfid_card_reg)
    );

    playing_card_map deck_lookup (
        .tag_hex(rfid_raw_hex),
        .mapped(deck_mapped),
        .card_binary(card_binary)
    );

    assign playing_card_reg = card_binary;
    assign playing_card_status_reg = {31'd0, deck_mapped};

    assign mmio_read_data =
        io_sw_read ? {16'd0, SW_Q} :
        io_rfid_status_read ? rfid_status_reg :
        io_rfid_facility_read ? rfid_facility_reg :
        io_rfid_card_read ? rfid_card_reg :
        io_btn_read ? btn_status_reg :
        io_uart_stat_read ? {31'd0, uart_tx_busy} :
        io_playing_card_read ? playing_card_reg :
        io_playing_card_status_read ? playing_card_status_reg :
        io_vga_display_read ? vga_display_value[io_vga_slot] :
        32'd0;

    assign q_dmem = (io_sw_read | io_rfid_status_read | io_rfid_facility_read |
                     io_rfid_card_read | io_btn_read | io_uart_stat_read |
                     io_playing_card_read | io_playing_card_status_read |
                     io_vga_display_read) ? mmio_read_data : memDataOut;

    localparam INSTR_FILE = "mctest"; 

    processor CPU (
        .clock(clock),
        .reset(sys_reset),
        .address_imem(instAddr),
        .q_imem(instData),
        .ctrl_writeEnable(rwe),
        .ctrl_writeReg(rd),
        .ctrl_readRegA(rs1),
        .ctrl_readRegB(rs2),
        .data_writeReg(rData),
        .data_readRegA(regA),
        .data_readRegB(regB),
        .wren(mwe),
        .address_dmem(memAddr),
        .data(memDataIn),
        .q_dmem(q_dmem)
    );

    ROM #(.MEMFILE({INSTR_FILE, ".mem"})) InstMem (
        .clk(clock),
        .addr(instAddr[11:0]),
        .dataOut(instData)
    );

    regfile RegisterFile (
        .clock(clock),
        .ctrl_writeEnable(rwe),
        .ctrl_reset(sys_reset),
        .ctrl_writeReg(rd),
        .ctrl_readRegA(rs1),
        .ctrl_readRegB(rs2),
        .data_writeReg(rData),
        .data_readRegA(regA),
        .data_readRegB(regB)
    );

    RAM ProcMem (
        .clk(clock),
        .wEn(mwe && (memAddr < 32'd4096)), // FIX: Only allow RAM writes for standard memory addresses
        .addr(memAddr[11:0]),
        .dataIn(memDataIn),
        .dataOut(memDataOut)
    );

endmodule

//--------------------------------------------------------------------------------------------------
// Lab kit: 640x480 @25MHz pixel clock (inlined from lab7-8_kit/VGATimingGenerator.v)
//--------------------------------------------------------------------------------------------------
module VGATimingGenerator #(
    parameter integer HEIGHT = 480,
    parameter integer WIDTH  = 640
) (
    input  wire       clk25,
    input  wire       reset,
    output wire       active,
    output wire       screenEnd,
    output wire       hSync,
    output wire       vSync,
    output wire [9:0] x,
    output wire [8:0] y
);

    localparam integer H_FRONT_PORCH = 16;
    localparam integer H_SYNC_WIDTH  = 96;
    localparam integer H_BACK_PORCH  = 48;
    localparam integer H_SYNC_START  = WIDTH + H_FRONT_PORCH;
    localparam integer H_SYNC_END    = H_SYNC_START + H_SYNC_WIDTH;
    localparam integer H_LINE        = H_SYNC_END + H_BACK_PORCH;

    localparam integer V_FRONT_PORCH = 11;
    localparam integer V_SYNC_WIDTH  = 2;
    localparam integer V_BACK_PORCH  = 31;
    localparam integer V_SYNC_START  = HEIGHT + V_FRONT_PORCH;
    localparam integer V_SYNC_END    = V_SYNC_START + V_SYNC_WIDTH;
    localparam integer V_LINE        = V_SYNC_END + V_BACK_PORCH;

    reg [9:0] hPos;
    reg [9:0] vPos;

    always @(posedge clk25 or posedge reset) begin
        if (reset) begin
            hPos <= 10'd0;
            vPos <= 10'd0;
        end else begin
            if (hPos == H_LINE - 1) begin
                hPos <= 10'd0;
                if (vPos == V_LINE - 1)
                    vPos <= 10'd0;
                else
                    vPos <= vPos + 10'd1;
            end else begin
                hPos <= hPos + 10'd1;
            end
        end
    end

    wire activeX = (hPos < WIDTH);
    wire activeY = (vPos < HEIGHT);
    assign active    = activeX & activeY;
    assign x         = activeX ? hPos : 10'd0;
    assign y         = activeY ? vPos[8:0] : 9'd0;
    assign screenEnd = (vPos == (V_LINE - 1)) && (hPos == (H_LINE - 1));
    assign hSync     = (hPos < H_SYNC_START) | (hPos >= H_SYNC_END);
    assign vSync     = (vPos < V_SYNC_START) | (vPos >= V_SYNC_END);
endmodule

//--------------------------------------------------------------------------------------------------
// Multi-section labeled text renderer.
//
// Section 1 (rows 0..PROB_SLOTS-1): hand-probability percentages.
//   Each line is a hardcoded label ("HIGH CARD:  ", "PAIR:       ", ...)
//   followed by a 3-digit decimal (0..999) drawn from values_flat[i].
//
// Section 2 (row PROB_SLOTS  ): "BOARD:  " + 5 cards (flop, turn, river).
// Section 3 (row PROB_SLOTS+1): "HOLE:   " + 2 hole cards.
//   Card indices come from card_values_flat (slot 0..1 = hole, 2..6 = board).
//   Each card is a 6-bit deck index: rank = card[5:2] (0=2, ..., 8=T, 9=J,
//   10=Q, 11=K, 12=A), suit = card[1:0] (0=c, 1=d, 2=h, 3=s). Rendered as a
//   2-char rank+suit (e.g. "7c", "Td", "Ah") with a trailing space between.
//   Unvalidated card slots render as blanks.
//
// Font ROM layout (38 glyphs, 8x8 each; loaded from vga_digit_font.mem):
//   0..9  : digits '0'..'9'
//   10    : blank (space)
//   11    : ':'
//   12..37: 'A'..'Z'
//--------------------------------------------------------------------------------------------------
module vga_decimal_text_multi #(
    parameter integer PROB_SLOTS  = 8,
    parameter integer CARD_SLOTS  = 7,    // 0..1 = hole ($1,$2), 2..6 = board ($3..$7)
    parameter integer LABEL_CHARS = 12,   // accommodates longest prob label ("FULL HOUSE: ")
    parameter integer DIGITS      = 3,
    parameter integer BOARD_CARDS = 5,
    parameter integer HOLE_CARDS  = 2
) (
    input  wire                       active,
    input  wire [9:0]                 px,
    input  wire [8:0]                 py,
    input  wire [PROB_SLOTS*32-1:0]   values_flat,
    input  wire [PROB_SLOTS-1:0]      valid_mask,
    input  wire [CARD_SLOTS*32-1:0]   card_values_flat,
    input  wire [CARD_SLOTS-1:0]      card_valid_mask,
    // Preflop strategy (three extra rows below HOLE). Freqs are 0..100.
    // preflop_size_tens is the raise-size multiplier * 10 (e.g. 22 = 2.2x).
    input  wire [7:0]                 preflop_fold,
    input  wire [7:0]                 preflop_call,
    input  wire [7:0]                 preflop_raise,
    input  wire [6:0]                 preflop_size_tens,
    input  wire                       preflop_valid,
    // Live switch echo for the POS: row. pos_hero / pos_villain are 0..5
    // (UTG..BB), pos_action is 0..2 (UNOPENED / ONE_RAISE / THREE_BET).
    // pos_switches_ok = 0 forces the row to print "INVALID".
    input  wire [2:0]                 pos_hero,
    input  wire [2:0]                 pos_villain,
    input  wire [1:0]                 pos_action,
    input  wire                       pos_switches_ok,
    output reg  [11:0]                rgb12
);

    localparam integer CARD_CHAR_W = 3;                                          // "Xy "
    localparam integer CARD_CONTENT_CHARS = BOARD_CARDS * CARD_CHAR_W;           // 15
    // Row width must fit the wider of a prob row vs a card row.
    localparam integer LINE_CHARS  = LABEL_CHARS + CARD_CONTENT_CHARS;           // 27
    // Rows: PROB_SLOTS (8) + BOARD + HOLE + POS + FOLD + CALL + RAISE.
    localparam integer TOTAL_ROWS  = PROB_SLOTS + 6;                             // 14
    localparam [9:0]   P_TOP       = 10'd20;
    localparam [9:0]   P_LEFT      = 10'd20;
    localparam [9:0]   CHAR_W      = 10'd8;
    localparam [9:0]   CHAR_H      = 10'd8;
    localparam [9:0]   LINE_HEIGHT = 10'd16;                                     // 8 px char + 8 px gap
    localparam [9:0]   ROW_WIDTH   = CHAR_W * LINE_CHARS;                        // 216 px

    // --- Font ROM (39 glyphs * 8 rows = 312 bytes) ---------------------------
    //   0..9  : digits, 10: space, 11: ':', 12..37: 'A'..'Z', 38: '.'
    reg [7:0] font_rom[0:311];
    initial begin
        $readmemh("C:/Users/dcm92/Downloads/vga_digit_font.mem", font_rom);
    end

    // --- Label ROM: one ASCII string per line, left-aligned + space-padded ---
    // Labels MUST be exactly LABEL_CHARS bytes long. Trailing spaces pad them
    // so content (digits or cards) starts at the same X column on every row.
    reg [LABEL_CHARS*8-1:0] labels_ascii [0:TOTAL_ROWS-1];
    initial begin
        labels_ascii[0] = "HIGH CARD:  ";
        labels_ascii[1] = "PAIR:       ";
        labels_ascii[2] = "TWO PAIR:   ";
        labels_ascii[3] = "TRIPS:      ";
        labels_ascii[4] = "STRAIGHT:   ";
        labels_ascii[5] = "FLUSH:      ";
        labels_ascii[6] = "FULL HOUSE: ";
        labels_ascii[7] = "QUADS:      ";
        labels_ascii[8]  = "BOARD:      ";
        labels_ascii[9]  = "HOLE:       ";
        labels_ascii[10] = "POS:        ";
        labels_ascii[11] = "FOLD:       ";
        labels_ascii[12] = "CALL:       ";
        labels_ascii[13] = "RAISE:      ";
    end

    // --- Pixel -> (line, char-col, row, col) --------------------------------
    wire [9:0] py10     = {1'b0, py};
    wire [9:0] rely_all = (py10 >= P_TOP) ? (py10 - P_TOP) : 10'd0;
    wire [5:0] line_idx = rely_all[9:4];                    // / 16
    wire [3:0] line_rely= rely_all[3:0];                    // % 16
    wire       in_y_tot = (py10 >= P_TOP) && (line_idx < TOTAL_ROWS[5:0]);
    wire       in_y_chr = in_y_tot && (line_rely < CHAR_H[3:0]);

    wire [9:0] relx     = (px >= P_LEFT) ? (px - P_LEFT) : 10'd0;
    wire       in_x     = (px >= P_LEFT) && (px < P_LEFT + ROW_WIDTH);
    wire [6:0] char_col = relx[9:3];                        // / 8   (0..LINE_CHARS-1)
    wire [2:0] col      = relx[2:0];
    wire [2:0] row      = line_rely[2:0];

    // Which section does this row belong to?
    wire is_prob_row   = (line_idx < PROB_SLOTS[5:0]);
    wire is_board_row  = (line_idx == PROB_SLOTS[5:0]);
    wire is_hole_row   = (line_idx == (PROB_SLOTS[5:0] + 6'd1));
    wire is_pos_row    = (line_idx == (PROB_SLOTS[5:0] + 6'd2));    // NEW: switch-echo row
    wire is_fold_row   = (line_idx == (PROB_SLOTS[5:0] + 6'd3));
    wire is_call_row   = (line_idx == (PROB_SLOTS[5:0] + 6'd4));
    wire is_raise_row  = (line_idx == (PROB_SLOTS[5:0] + 6'd5));
    wire is_preflop_row = is_fold_row | is_call_row | is_raise_row;
    // Hide the BOARD/HOLE band until any card has been scanned (stops two
    // random blue bars floating at startup before anything is written).
    wire any_card_valid = |card_valid_mask;
    // POS row is always visible so the user can watch the switches take
    // effect before any card is scanned; it prints "INVALID" for an
    // out-of-range switch encoding.
    wire row_visible =
        is_prob_row                               ? 1'b1        :
        (is_board_row | is_hole_row)              ? any_card_valid :
        is_pos_row                                ? 1'b1 :
        is_preflop_row                            ? preflop_valid :
                                                    1'b0;

    // --- Per-line PROB value & decoded digits -------------------------------
    wire [31:0] cur_val   = values_flat[line_idx[2:0]*32 +: 32];
    wire        cur_valid = valid_mask[line_idx[2:0]];

    wire [31:0] v_u  = cur_val[31] ? 32'd0 : cur_val;
    wire [9:0]  cap  = (v_u > 32'd999) ? 10'd999 : v_u[9:0];
    wire [3:0]  d100 = cap / 10'd100;
    wire [3:0]  d10  = (cap % 10'd100) / 10'd10;
    wire [3:0]  d1   = cap % 10'd10;
    wire [3:0]  sym0 = (cap >= 10'd100) ? d100 : 4'd10;    // leading-zero suppress
    wire [3:0]  sym1 = (cap >= 10'd10)  ? d10  : 4'd10;
    wire [3:0]  sym2 = d1;
    wire [3:0]  digit_sym0 = cur_valid ? sym0 : 4'd10;
    wire [3:0]  digit_sym1 = cur_valid ? sym1 : 4'd10;
    wire [3:0]  digit_sym2 = cur_valid ? sym2 : 4'd10;

    // --- Which char (label vs content) is in this column? -------------------
    wire        in_label  = (char_col < LABEL_CHARS[6:0]);
    wire [6:0]  cont_col  = char_col - LABEL_CHARS[6:0];    // 0..CARD_CONTENT_CHARS-1

    // Fetch label char for this row/column. Strings in Verilog are packed
    // MSB-first, so the left-most char is at bits [(LABEL_CHARS-1)*8 +: 8].
    localparam [3:0] LAST_LABEL_COL = LABEL_CHARS[3:0] - 4'd1;
    wire [3:0] reversed_col  = LAST_LABEL_COL - char_col[3:0];
    wire [6:0] label_bit_pos = {reversed_col, 3'b000};
    wire [LABEL_CHARS*8-1:0] cur_label = labels_ascii[line_idx[3:0]];
    wire [7:0] label_char    = cur_label[label_bit_pos +: 8];

    // --- Card decoding for BOARD/HOLE rows ---------------------------------
    // Each card occupies CARD_CHAR_W=3 columns: rank, suit, space.
    wire [3:0] card_pos      = cont_col[6:0] / CARD_CHAR_W[6:0];   // 0..4
    wire [1:0] card_subchar  = cont_col[6:0] % CARD_CHAR_W[6:0];   // 0=rank, 1=suit, 2=space

    // Pick which of the 7 card slots this position maps to.
    //   BOARD row: card_pos 0..4 -> slots 2..6 ($3..$7)
    //   HOLE  row: card_pos 0..1 -> slots 0..1 ($1..$2)
    wire [3:0] card_slot_idx = is_board_row ? (4'd2 + card_pos[3:0]) : card_pos[3:0];
    wire       card_pos_valid = is_board_row ? (card_pos < BOARD_CARDS[3:0])
                                             : (card_pos < HOLE_CARDS[3:0]);
    wire [31:0] cur_card_val  = card_values_flat[card_slot_idx[2:0]*32 +: 32];
    wire        cur_card_valid= card_valid_mask[card_slot_idx[2:0]];
    wire        card_visible  = card_pos_valid && cur_card_valid && !cur_card_val[31];

    // 6-bit deck index -> rank index [0..12] (0=2) and suit index [0..3].
    wire [3:0] card_rank = cur_card_val[5:2];
    wire [1:0] card_suit = cur_card_val[1:0];

    // Rank -> glyph: 0..7 = "2".."9" (digit glyphs 2..9), 8 = 'T', 9 = 'J',
    // 10 = 'Q', 11 = 'K', 12 = 'A'. (Glyphs: digits 0..9 at 0..9; letters
    // 'A'..'Z' at 12..37.)
    function [7:0] rank_glyph(input [3:0] r);
        begin
            case (r)
                4'd0:  rank_glyph = 8'd2;                   // '2'
                4'd1:  rank_glyph = 8'd3;                   // '3'
                4'd2:  rank_glyph = 8'd4;                   // '4'
                4'd3:  rank_glyph = 8'd5;                   // '5'
                4'd4:  rank_glyph = 8'd6;                   // '6'
                4'd5:  rank_glyph = 8'd7;                   // '7'
                4'd6:  rank_glyph = 8'd8;                   // '8'
                4'd7:  rank_glyph = 8'd9;                   // '9'
                4'd8:  rank_glyph = 8'd12 + 8'd19;          // 'T'
                4'd9:  rank_glyph = 8'd12 + 8'd9;           // 'J'
                4'd10: rank_glyph = 8'd12 + 8'd16;          // 'Q'
                4'd11: rank_glyph = 8'd12 + 8'd10;          // 'K'
                4'd12: rank_glyph = 8'd12 + 8'd0;           // 'A'
                default: rank_glyph = 8'd10;                // blank
            endcase
        end
    endfunction

    // Suit -> glyph: 0=c, 1=d, 2=h, 3=s. We use lowercase-looking glyphs from
    // the uppercase font for compactness (no lowercase in font_rom).
    function [7:0] suit_glyph(input [1:0] s);
        begin
            case (s)
                2'd0: suit_glyph = 8'd12 + 8'd2;            // 'C' (clubs)
                2'd1: suit_glyph = 8'd12 + 8'd3;            // 'D' (diamonds)
                2'd2: suit_glyph = 8'd12 + 8'd7;            // 'H' (hearts)
                2'd3: suit_glyph = 8'd12 + 8'd18;           // 'S' (spades)
                default: suit_glyph = 8'd10;
            endcase
        end
    endfunction

    // ASCII -> glyph index (matches the .mem layout generated by gen_font.py).
    function [7:0] ascii_to_glyph(input [7:0] ch);
        begin
            if (ch == 8'h20)                               ascii_to_glyph = 8'd10;               // ' '
            else if (ch == 8'h2E)                          ascii_to_glyph = 8'd38;               // '.'
            else if (ch == 8'h3A)                          ascii_to_glyph = 8'd11;               // ':'
            else if (ch >= 8'h30 && ch <= 8'h39)           ascii_to_glyph = ch - 8'h30;          // '0'..'9'
            else if (ch >= 8'h41 && ch <= 8'h5A)           ascii_to_glyph = (ch - 8'h41) + 8'd12;// 'A'..'Z'
            else                                           ascii_to_glyph = 8'd10;               // unknown -> blank
        end
    endfunction

    // Content glyph for prob rows (3 digits, then blanks to fill the widened row).
    wire [3:0] cur_digit_sym = (cont_col == 7'd0) ? digit_sym0 :
                               (cont_col == 7'd1) ? digit_sym1 :
                               (cont_col == 7'd2) ? digit_sym2 : 4'd10;  // blank
    wire [7:0] prob_content_glyph = {4'b0, cur_digit_sym};

    // Content glyph for card rows.
    wire [7:0] card_content_glyph =
        !card_visible ? 8'd10 :                            // blank when slot empty
        (card_subchar == 2'd0) ? rank_glyph(card_rank) :
        (card_subchar == 2'd1) ? suit_glyph(card_suit) :
                                  8'd10;                   // trailing space

    // ----- Preflop rows ------------------------------------------------------
    // FOLD / CALL rows: 3-digit decimal (same layout as prob rows).
    // RAISE row: "NNN SIZE: MM" (content cols 0..2 = raise_freq digits,
    // col 3 = space, cols 4..8 = "SIZE:", col 9 = space,
    // cols 10..11 = two-digit raise-size tens, where 22 means 2.2x, 30 means
    // 3.0x, etc. We suppress leading zeros on the raise value but render the
    // two size digits as-is so "05" looks like "05" (size=0 is also blanked).
    function [3:0] dec100 (input [7:0] v); begin dec100 = v / 8'd100; end endfunction
    function [3:0] dec10  (input [7:0] v); begin dec10  = (v % 8'd100) / 8'd10; end endfunction
    function [3:0] dec1   (input [7:0] v); begin dec1   = v % 8'd10; end endfunction

    wire [7:0] pf_value =
        is_fold_row ? preflop_fold :
        is_call_row ? preflop_call :
                      preflop_raise;
    wire [3:0] pf_d100 = dec100(pf_value);
    wire [3:0] pf_d10  = dec10(pf_value);
    wire [3:0] pf_d1   = dec1(pf_value);
    wire [3:0] pf_sym0 = (pf_value >= 8'd100) ? pf_d100 : 4'd10;
    wire [3:0] pf_sym1 = (pf_value >= 8'd10)  ? pf_d10  : 4'd10;
    wire [3:0] pf_sym2 = pf_d1;

    // For FOLD/CALL: same format as prob rows.
    wire [7:0] pf_foldcall_glyph =
        (cont_col == 7'd0) ? {4'b0, pf_sym0} :
        (cont_col == 7'd1) ? {4'b0, pf_sym1} :
        (cont_col == 7'd2) ? {4'b0, pf_sym2} :
                             8'd10;

    // For RAISE: "<3-digit freq> SIZE: X.Y"  where X.Y is the real
    // multiplier (e.g. 22 = "2.2", 30 = "3.0"). We leave the size field
    // blank entirely if preflop_size_tens = 0 (no raise).
    wire [3:0] size_d10 = {1'b0, preflop_size_tens} / 8'd10;   // 22 -> 2
    wire [3:0] size_d1  = {1'b0, preflop_size_tens} % 8'd10;   // 22 -> 2
    wire       no_raise_size = (preflop_size_tens == 7'd0);
    wire [7:0] size_int_glyph   = no_raise_size ? 8'd10 : {4'b0, size_d10};
    wire [7:0] size_dot_glyph   = no_raise_size ? 8'd10 : 8'd38;    // '.'
    wire [7:0] size_frac_glyph  = no_raise_size ? 8'd10 : {4'b0, size_d1};

    // Content layout (label is at cols before content):
    //   0..2  raise-freq 3-digit decimal
    //   3     ' '
    //   4..8  "SIZE:"
    //   9     ' '
    //   10    size integer digit      ("2" in 2.2x)
    //   11    '.'
    //   12    size fractional digit   ("2" in 2.2x)
    wire [7:0] raise_content_glyph =
        (cont_col == 7'd0)  ? {4'b0, pf_sym0}     :
        (cont_col == 7'd1)  ? {4'b0, pf_sym1}     :
        (cont_col == 7'd2)  ? {4'b0, pf_sym2}     :
        (cont_col == 7'd3)  ? 8'd10               :    // ' '
        (cont_col == 7'd4)  ? 8'd30               :    // 'S'
        (cont_col == 7'd5)  ? 8'd20               :    // 'I'
        (cont_col == 7'd6)  ? 8'd37               :    // 'Z'
        (cont_col == 7'd7)  ? 8'd16               :    // 'E'
        (cont_col == 7'd8)  ? 8'd11               :    // ':'
        (cont_col == 7'd9)  ? 8'd10               :    // ' '
        (cont_col == 7'd10) ? size_int_glyph      :
        (cont_col == 7'd11) ? size_dot_glyph      :
        (cont_col == 7'd12) ? size_frac_glyph     :
                              8'd10;

    wire [7:0] preflop_content_glyph =
        is_raise_row ? raise_content_glyph : pf_foldcall_glyph;

    //------------------------------------------------------------------
    // POS row content. Shows "HERO v VIL ACTION" live from the switches.
    // Layout (15 content chars, blanks pad short names):
    //   0..2  hero 3-char name
    //   3     ' '
    //   4     'V'
    //   5     ' '
    //   6..8  villain 3-char name
    //   9     ' '
    //   10..14  action 5-char name
    // When the switches are out of range we render "INVALID" left-aligned.
    //------------------------------------------------------------------
    reg [7:0] pos_name_tbl_c0 [0:5];
    reg [7:0] pos_name_tbl_c1 [0:5];
    reg [7:0] pos_name_tbl_c2 [0:5];
    reg [7:0] action_tbl_c0 [0:2];
    reg [7:0] action_tbl_c1 [0:2];
    reg [7:0] action_tbl_c2 [0:2];
    reg [7:0] action_tbl_c3 [0:2];
    reg [7:0] action_tbl_c4 [0:2];
    initial begin
        // 0=UTG, 1=HJ, 2=CO, 3=BTN, 4=SB, 5=BB  (pad 2-letter to 3 with space)
        pos_name_tbl_c0[0]="U"; pos_name_tbl_c1[0]="T"; pos_name_tbl_c2[0]="G";
        pos_name_tbl_c0[1]="H"; pos_name_tbl_c1[1]="J"; pos_name_tbl_c2[1]=" ";
        pos_name_tbl_c0[2]="C"; pos_name_tbl_c1[2]="O"; pos_name_tbl_c2[2]=" ";
        pos_name_tbl_c0[3]="B"; pos_name_tbl_c1[3]="T"; pos_name_tbl_c2[3]="N";
        pos_name_tbl_c0[4]="S"; pos_name_tbl_c1[4]="B"; pos_name_tbl_c2[4]=" ";
        pos_name_tbl_c0[5]="B"; pos_name_tbl_c1[5]="B"; pos_name_tbl_c2[5]=" ";
        // 0=UNOPENED (Raise-First-In), 1=ONE_RAISE (open to face),
        // 2=THREE_BET. 5 chars, space-padded.
        action_tbl_c0[0]="R"; action_tbl_c1[0]="F"; action_tbl_c2[0]="I"; action_tbl_c3[0]=" "; action_tbl_c4[0]=" ";
        action_tbl_c0[1]="O"; action_tbl_c1[1]="P"; action_tbl_c2[1]="E"; action_tbl_c3[1]="N"; action_tbl_c4[1]=" ";
        action_tbl_c0[2]="3"; action_tbl_c1[2]="B"; action_tbl_c2[2]="E"; action_tbl_c3[2]="T"; action_tbl_c4[2]=" ";
    end

    // Cap lookup indices to valid ranges; out-of-range is rendered via
    // the pos_switches_ok gate below.
    wire [2:0] hero_ix = (pos_hero    > 3'd5) ? 3'd0 : pos_hero;
    wire [2:0] vil_ix  = (pos_villain > 3'd5) ? 3'd0 : pos_villain;
    wire [1:0] act_ix  = (pos_action  > 2'd2) ? 2'd0 : pos_action;

    // "INVALID        " (7 chars + 8 spaces). Hand-rolled because a full
    // 120-bit string literal in one place is harder to line up.
    function [7:0] invalid_char(input [3:0] col);
        begin
            case (col)
                4'd0: invalid_char = "I";
                4'd1: invalid_char = "N";
                4'd2: invalid_char = "V";
                4'd3: invalid_char = "A";
                4'd4: invalid_char = "L";
                4'd5: invalid_char = "I";
                4'd6: invalid_char = "D";
                default: invalid_char = " ";
            endcase
        end
    endfunction

    function [7:0] valid_pos_char(input [3:0] col,
                                  input [2:0] hero, input [2:0] vil, input [1:0] act);
        begin
            case (col)
                4'd0:  valid_pos_char = pos_name_tbl_c0[hero];
                4'd1:  valid_pos_char = pos_name_tbl_c1[hero];
                4'd2:  valid_pos_char = pos_name_tbl_c2[hero];
                4'd3:  valid_pos_char = " ";
                4'd4:  valid_pos_char = "V";
                4'd5:  valid_pos_char = " ";
                4'd6:  valid_pos_char = pos_name_tbl_c0[vil];
                4'd7:  valid_pos_char = pos_name_tbl_c1[vil];
                4'd8:  valid_pos_char = pos_name_tbl_c2[vil];
                4'd9:  valid_pos_char = " ";
                4'd10: valid_pos_char = action_tbl_c0[act];
                4'd11: valid_pos_char = action_tbl_c1[act];
                4'd12: valid_pos_char = action_tbl_c2[act];
                4'd13: valid_pos_char = action_tbl_c3[act];
                4'd14: valid_pos_char = action_tbl_c4[act];
                default: valid_pos_char = " ";
            endcase
        end
    endfunction

    wire [7:0] pos_char = pos_switches_ok
        ? valid_pos_char(cont_col[3:0], hero_ix, vil_ix, act_ix)
        : invalid_char(cont_col[3:0]);
    wire [7:0] pos_content_glyph =
        (cont_col < CARD_CONTENT_CHARS[6:0]) ? ascii_to_glyph(pos_char) : 8'd10;

    wire [7:0] content_glyph =
        is_prob_row    ? prob_content_glyph    :
        is_pos_row     ? pos_content_glyph     :
        is_preflop_row ? preflop_content_glyph :
                         card_content_glyph;
    wire [7:0] pick_glyph    = in_label ? ascii_to_glyph(label_char) : content_glyph;

    // --- Font lookup: glyph*8 + row -----------------------------------------
    wire [8:0] faddr   = {pick_glyph[5:0], row};          // 39 glyphs still fit in 6 bits
    wire [7:0] rowbits = font_rom[faddr];

    wire in_char_band = active && in_y_chr && in_x && row_visible;
    wire in_back_band = active && in_y_tot && in_x && row_visible;
    wire pix_on       = in_char_band && rowbits[7 - col];

    wire any_valid = (|valid_mask) || (|card_valid_mask) || preflop_valid;

    always @(*) begin
        if (!active)
            rgb12 = 12'h000;
        else if (pix_on)
            rgb12 = 12'hfff;
        else if (in_back_band)
            rgb12 = 12'h026;
        else if (any_valid)
            rgb12 = 12'h135;
        else
            rgb12 = 12'h000;
    end

endmodule