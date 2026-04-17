/**
 * Maps a full RFID 12-hex frame value to a 32-bit card representation.
 *
 * Add case rows: 48-bit key = full frame bytes b0..b5 in hex (e.g. 48'h04002DBDCF5B).
 * Unknown tags: mapped=0, card_binary=0.
 *
 * To fill the table, use scripts/gen_playing_card_map.py with your CSV:
 *   Card Real,Card Binary,Hex
 */
module playing_card_map (
    input  wire [47:0] tag_hex,
    output reg         mapped,
    output reg  [31:0] card_binary
);
    always @(*) begin
        mapped = 1'b0;
        card_binary = 32'd0;
        case (tag_hex)
            // BEGIN_CARD_CASES
            48'h04002DBDCF5B: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000000000; end
            48'h04002EB8E97B: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000000001; end
            48'h0400432FD1B9: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000000010; end
            48'h04002DE503CF: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000000011; end
            48'h04002D5B97E5: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000000100; end
            48'h04004194B766: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000000101; end
            48'h040043144516: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000000110; end
            48'h0400430C004B: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000000111; end
            48'h04002E76D78B: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000001000; end
            48'h04002EA3C841: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000001001; end
            48'h04004310A0F7: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000001010; end
            48'h04004311D385: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000001011; end
            48'h0400427ABB87: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000001100; end
            48'h04002EAA0B8B: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000001101; end
            48'h04002E4791FC: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000001110; end
            48'h0400439268BD: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000001111; end
            48'h040043BCA15A: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000010000; end
            48'h040043CCC64D: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000010001; end
            48'h04004332A1D4: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000010010; end
            48'h04002E9F7FCA: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000010011; end
            48'h0400434BA9A5: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000010100; end
            48'h04002B6C7330: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000010101; end
            48'h04002E58FB89: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000010110; end
            48'h04002D61B9F1: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000010111; end
            48'h04002DF14199: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000011000; end
            48'h04002A9FC574: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000011001; end
            48'h04002D7A4615: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000011010; end
            48'h04002ADC07F5: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000011011; end
            48'h04003F72FAB3: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000011100; end
            48'h04003FD10CE6: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000011101; end
            48'h0400404FD3D8: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000011110; end
            48'h04003E4D1562: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000011111; end
            48'h040043A7EC0C: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000100000; end
            48'h04002BCA24C1: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000100001; end
            48'h04003EDE8266: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000100010; end
            48'h04003EE0E43E: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000100011; end
            48'h04003CDEEF09: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000100100; end
            48'h04003D80843D: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000100101; end
            48'h04003CFC4783: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000100110; end
            48'h04003BC2768B: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000100111; end
            48'h0400410385C3: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000101000; end
            48'h04003CBF8B0C: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000101001; end
            48'h04003E7182C9: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000101010; end
            48'h04003F77CC80: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000101011; end
            48'h040040D7EE7D: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000101100; end
            48'h040040875F9C: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000101101; end
            48'h04003EE0EA30: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000101110; end
            48'h0400413E99E2: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000101111; end
            48'h04003B1A5075: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000110000; end
            48'h040043BBB945: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000110001; end
            48'h04003DF405C8: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000110010; end
            48'h04003D47631D: begin mapped = 1'b1; card_binary = 32'b00000000000000000000000000110011; end
            // END_CARD_CASES
            default: begin mapped = 1'b0; card_binary = 32'd0; end
        endcase
    end
endmodule
