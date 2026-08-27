// -----------------------------------------------------------------------------
// uart_rx — 8N1 receiver with mid-bit sampling
//
// CLK_HZ / BAUD gives the cycles per bit. The start bit is detected on a
// falling edge, then the counter is preset to one and a half bit times so the
// first data sample lands in the middle of bit 0 (a half-bit preset would land
// in the middle of the start bit and shift every sample by one position).
// -----------------------------------------------------------------------------
`default_nettype none

module uart_rx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,      // 1-cycle pulse
    output reg        frame_error // stop bit was not high
);

    localparam integer DIV      = CLK_HZ / BAUD;
    localparam integer HALF_DIV = DIV / 2;
    // Wide enough for the 1.5-bit start preset, not just one bit time.
    localparam integer FIRST    = DIV + HALF_DIV - 1;
    localparam integer DIV_W    = $clog2(FIRST + 1);

    localparam [1:0] S_IDLE = 2'd0,
                     S_DATA = 2'd1,
                     S_STOP = 2'd2;

    reg [1:0]       state;
    reg [DIV_W-1:0] tick;
    reg [2:0]       bit_idx;
    reg [7:0]       shifter;

    // Synchronise the async input before edge-detecting it.
    reg rx_meta, rx_sync, rx_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            tick        <= {DIV_W{1'b0}};
            bit_idx     <= 3'd0;
            shifter     <= 8'd0;
            data        <= 8'd0;
            valid       <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    // Falling edge = start bit. Skip the rest of the start bit
                    // plus half of bit 0 before the first sample.
                    if (rx_prev && !rx_sync) begin
                        tick    <= FIRST[DIV_W-1:0];
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end
                end

                S_DATA: begin
                    if (tick == 0) begin
                        tick <= DIV[DIV_W-1:0] - 1'b1;
                        // LSB first.
                        shifter <= {rx_sync, shifter[7:1]};
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
                    if (tick == 0) begin
                        data        <= shifter;
                        valid       <= 1'b1;
                        frame_error <= !rx_sync;
                        state       <= S_IDLE;
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
