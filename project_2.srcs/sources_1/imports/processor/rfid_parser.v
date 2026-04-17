module rfid_parser (
    input wire clock,
    input wire reset,
    input wire [7:0] rx_byte,
    input wire rx_valid,
    output reg [39:0] tag_data,
    output reg [7:0] checksum_rx,
    output reg [7:0] checksum_calc,
    output reg [15:0] facility,
    output reg [15:0] card,
    output reg checksum_ok,
    output reg tag_valid_pulse
);

    localparam [7:0] STX = 8'h02;
    localparam [7:0] ETX = 8'h03;
    localparam [7:0] CR  = 8'h0D;
    localparam [7:0] LF  = 8'h0A;

    reg in_frame;
    reg [3:0] nibble_count;
    reg [47:0] hex_bits;
    reg [3:0] hex_val;
    reg hex_ok;

    wire [7:0] b0 = hex_bits[47:40];
    wire [7:0] b1 = hex_bits[39:32];
    wire [7:0] b2 = hex_bits[31:24];
    wire [7:0] b3 = hex_bits[23:16];
    wire [7:0] b4 = hex_bits[15:8];
    wire [7:0] b5 = hex_bits[7:0];

    always @(*) begin
        hex_ok = 1'b1;
        if (rx_byte >= 8'h30 && rx_byte <= 8'h39) begin
            hex_val = rx_byte - 8'h30;
        end else if (rx_byte >= 8'h41 && rx_byte <= 8'h46) begin
            hex_val = rx_byte - 8'h41 + 8'd10;
        end else if (rx_byte >= 8'h61 && rx_byte <= 8'h66) begin
            hex_val = rx_byte - 8'h61 + 8'd10;
        end else begin
            hex_val = 4'd0;
            hex_ok = 1'b0;
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            in_frame <= 1'b0;
            nibble_count <= 4'd0;
            hex_bits <= 48'd0;
            tag_data <= 40'd0;
            checksum_rx <= 8'd0;
            checksum_calc <= 8'd0;
            facility <= 16'd0;
            card <= 16'd0;
            checksum_ok <= 1'b0;
            tag_valid_pulse <= 1'b0;
        end else begin
            tag_valid_pulse <= 1'b0;

            if (rx_valid) begin
                if (rx_byte == STX) begin
                    in_frame <= 1'b1;
                    nibble_count <= 4'd0;
                    hex_bits <= 48'd0;
                    checksum_ok <= 1'b0;
                end else if (in_frame) begin
                    if (rx_byte == ETX) begin
                        in_frame <= 1'b0;
                        if (nibble_count == 4'd12) begin
                            checksum_calc <= b0 ^ b1 ^ b2 ^ b3 ^ b4;
                            checksum_rx <= b5;
                            checksum_ok <= ((b0 ^ b1 ^ b2 ^ b3 ^ b4) == b5);
                            if ((b0 ^ b1 ^ b2 ^ b3 ^ b4) == b5) begin
                                // b0 = first byte on wire (often XOR checksum), then b1..b4 payload,
                                // b5 = last byte. For HID-style tags: facility = {b1,b2}, card = {b3,b4}.
                                tag_data <= {b0, b1, b2, b3, b4};
                                facility <= {b1, b2};
                                card <= {b3, b4};
                                tag_valid_pulse <= 1'b1;
                            end
                        end else begin
                            checksum_ok <= 1'b0;
                        end 
                    end else if (rx_byte == CR || rx_byte == LF) begin
                        // Allowed trailing separators between payload and ETX.
                    end else if (hex_ok && nibble_count < 4'd12) begin
                        hex_bits <= {hex_bits[43:0], hex_val};
                        nibble_count <= nibble_count + 4'd1;
                    end else begin 
                        // Invalid frame content; reset parser until next STX.
                        in_frame <= 1'b0;
                        nibble_count <= 4'd0;
                        hex_bits <= 48'd0;
                        checksum_ok <= 1'b0;
                    end 
                end
            end 
        end
    end

endmodule
