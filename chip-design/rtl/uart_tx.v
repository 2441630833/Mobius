// -----------------------------------------------------------------------------
// uart_tx — 8N1 transmitter
//
// Assert `send` for one cycle while `ready` is high to queue a byte. `ready`
// drops for the duration of the frame (start + 8 data + stop).
// -----------------------------------------------------------------------------
`default_nettype none

module uart_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       send,
    output reg        tx,
    output wire       ready
);

    localparam integer DIV   = CLK_HZ / BAUD;
    localparam integer DIV_W = $clog2(DIV + 1);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]       state;
    reg [DIV_W-1:0] tick;
    reg [2:0]       bit_idx;
    reg [7:0]       shifter;

    assign ready = (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            tick    <= {DIV_W{1'b0}};
            bit_idx <= 3'd0;
            shifter <= 8'd0;
            tx      <= 1'b1;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (send) begin
                        shifter <= data;
                        tick    <= DIV[DIV_W-1:0] - 1'b1;
                        state   <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;
                    if (tick == 0) begin
                        tick    <= DIV[DIV_W-1:0] - 1'b1;
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else begin
                        tick <= tick - 1'b1;
                    end
                end

                S_DATA: begin
                    tx <= shifter[0];
                    if (tick == 0) begin
                        tick    <= DIV[DIV_W-1:0] - 1'b1;
                        shifter <= {1'b0, shifter[7:1]};
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        tick <= tick - 1'b1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;
                    if (tick == 0) begin
                        state <= S_IDLE;
                    end else begin
                        tick <= tick - 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
