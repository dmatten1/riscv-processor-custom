module rfid_mmio (
    input wire clock,
    input wire reset,
    input wire clear_tag,
    input wire tag_valid_pulse,
    input wire parser_checksum_ok,
    input wire [7:0] parser_checksum_rx,
    input wire [15:0] parser_facility,
    input wire [15:0] parser_card,
    input wire [39:0] parser_tag_data,
    output reg tag_ready,
    output reg checksum_ok,
    output reg overflow,
    output reg [15:0] facility,
    output reg [15:0] card,
    output reg [39:0] raw_data,
    output reg [47:0] raw_hex,
    output wire [31:0] status_reg,
    output wire [31:0] facility_reg,
    output wire [31:0] card_reg
);

    assign status_reg = {29'd0, overflow, checksum_ok, tag_ready};
    assign facility_reg = {16'd0, facility};
    assign card_reg = {16'd0, card};

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            tag_ready <= 1'b0;
            checksum_ok <= 1'b0;
            overflow <= 1'b0;
            facility <= 16'd0;
            card <= 16'd0;
            raw_data <= 40'd0;
            raw_hex <= 48'd0;
        end else begin
            // New frame latches data; CPU clear is mutually exclusive so we never
            // fight two nonblocking assigns to tag_ready in one cycle (sim/synth safe).
            if (tag_valid_pulse) begin
                if (tag_ready) begin
                    overflow <= 1'b1;
                end

                tag_ready <= 1'b1;
                checksum_ok <= parser_checksum_ok;
                facility <= parser_facility;
                card <= parser_card;
                raw_data <= parser_tag_data;
                raw_hex <= {parser_tag_data[39:32], parser_tag_data[31:24], parser_tag_data[23:16],
                            parser_tag_data[15:8], parser_tag_data[7:0], parser_checksum_rx};
            end else if (clear_tag) begin
                tag_ready <= 1'b0;
                overflow <= 1'b0;
            end
        end
    end

endmodule
