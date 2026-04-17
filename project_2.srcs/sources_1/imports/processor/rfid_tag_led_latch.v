/**
 * Latches LED intent from valid RFID parses: one cycle after tag_valid+checksum_ok,
 * compares (facility, card) to a golden pair (default: facility 0x002E "046", card 0xB8E9 "47337").
 */
module rfid_tag_led_latch #(
    parameter [15:0] GOLDEN_FACILITY = 16'h002E,
    parameter [15:0] GOLDEN_CARD     = 16'hB8E9
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        tag_valid_pulse,
    input  wire        checksum_ok,
    input  wire [15:0] facility,
    input  wire [15:0] card,
    output reg         led_golden,
    output reg         led_other
);

    wire ev = tag_valid_pulse & checksum_ok;
    reg  ev_d;

    always @(posedge clock or posedge reset) begin
        if (reset)
            ev_d <= 1'b0;
        else
            ev_d <= ev;
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            led_golden <= 1'b0;
            led_other  <= 1'b0;
        end else if (ev_d) begin
            if (facility == GOLDEN_FACILITY && card == GOLDEN_CARD) begin
                led_golden <= 1'b1;
                led_other  <= 1'b0;
            end else begin
                led_golden <= 1'b0;
                led_other  <= 1'b1;
            end
        end
    end

endmodule
