`timescale 1ns / 1ps
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
        //oops absolute path
        $readmemh("C:/Users/dcm92/Downloads/chart.hex", mem);
`endif
    end

    always @(posedge clock) begin
        q <= mem[addr];
    end

endmodule
