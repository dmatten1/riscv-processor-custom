`timescale 1ns / 1ps
/**
 * Preflop chart ROM.
 *
 * 65536 x 32-bit entries. Address layout (from build_chart_rom.py):
 *   addr[15:13] = hero position (0..5)
 *   addr[12:10] = villain position (0..5)
 *   addr[9:8]   = facing action (0..2)
 *   addr[7:0]   = hand_class index (0..168, natural ordering)
 *
 * Data layout:
 *   q[31]    = valid
 *   q[30:24] = raise_size_tens (0/22/25/30/40/50, i.e. BB*10)
 *   q[23:16] = raise_freq (0..100)
 *   q[15:8]  = call_freq  (0..100)
 *   q[7:0]   = fold_freq  (0..100)
 *
 * Initial content is loaded from charts/chart.hex. Nexys A7 synthesis requires
 * an absolute path inside $readmemh, so the Vivado .xdc flow should keep the
 * file alongside this module or the path below should be adjusted.
 */
module chart_rom (
    input  wire         clock,
    input  wire [15:0]  addr,
    output reg  [31:0]  q
);

    reg [31:0] mem [0:65535];

    initial begin
`ifdef SIMULATION
        $readmemh("C:/Users/dcm92/Downloads/chart.hex", mem);
`else
        // Vivado absolute-path convention (same as font_rom). Adjust if your
        // project tree moves the file.
        $readmemh("C:/Users/dcm92/Downloads/chart.hex", mem);
`endif
    end

    always @(posedge clock) begin
        q <= mem[addr];
    end

endmodule
