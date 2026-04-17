module uart_rx #(
    parameter integer CLK_HZ = 25000000,
    parameter integer BAUD = 9600
) (
    input wire clock,
    input wire reset,
    input wire rx,
    output reg [7:0] data_out,
    output reg data_valid
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam integer HALF_CLKS_PER_BIT = CLKS_PER_BIT / 2;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0] state;
    reg [15:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] rx_shift;

    // Two-stage synchronizer to safely sample asynchronous UART input.
    reg rx_meta;
    reg rx_sync;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state <= ST_IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            rx_shift <= 8'd0;
            data_out <= 8'd0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (rx_sync == 1'b0) begin
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    if (clk_count == HALF_CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        if (rx_sync == 1'b0) begin
                            state <= ST_DATA;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                ST_DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        rx_shift[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state <= ST_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                ST_STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        state <= ST_IDLE;
                        if (rx_sync == 1'b1) begin
                            data_out <= rx_shift;
                            data_valid <= 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
