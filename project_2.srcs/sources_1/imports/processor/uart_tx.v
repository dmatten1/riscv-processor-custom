// Synthesizable UART transmitter, 8N1. Idle high, LSB first.
module uart_tx #(
    parameter integer CLK_HZ = 25000000,
    parameter integer BAUD = 9600
) (
    input  wire       clock,
    input  wire       reset,
    input  wire [7:0] data,
    input  wire       wr,
    output reg        busy,
    output reg        tx
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_START = 3'd1;
    localparam [2:0] ST_DATA  = 3'd2;
    localparam [2:0] ST_STOP  = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_idx;
    reg [7:0]  data_hold;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state      <= ST_IDLE;
            clk_count  <= 16'd0;
            bit_idx    <= 3'd0;
            data_hold  <= 8'd0;
            busy       <= 1'b0;
            tx         <= 1'b1;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx <= 1'b1;
                    if (wr && !busy) begin
                        data_hold <= data;
                        busy      <= 1'b1;
                        state     <= ST_START;
                        clk_count <= 16'd0;
                        tx        <= 1'b0;
                    end
                end

                ST_START: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        state     <= ST_DATA;
                        bit_idx   <= 3'd0;
                        tx        <= data_hold[0];
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                ST_DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            state     <= ST_STOP;
                            tx        <= 1'b1;
                            clk_count <= 16'd0;
                        end else begin
                            bit_idx   <= bit_idx + 3'd1;
                            tx        <= data_hold[bit_idx + 3'd1];
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                ST_STOP: begin
                    tx <= 1'b1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        state     <= ST_IDLE;
                        busy      <= 1'b0;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                    tx    <= 1'b1;
                end
            endcase
        end
    end
endmodule
