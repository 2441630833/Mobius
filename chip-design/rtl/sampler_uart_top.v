// -----------------------------------------------------------------------------
// sampler_uart_top — Arty A7-35T top level for the FPGA token sampler
//
// Standalone (no SoC) target for the F4PGA flow: UART in, UART out, TRNG and
// stochastic softmax sampler in between. The LiteX variant in
// soc/arty_a7_sampler_soc.py wraps the same sampler behind CSRs instead.
//
// WIRE PROTOCOL — keep byte-identical with mcp/custom_fpga_mcp/protocol.py
//
//   host -> fpga:  0x5A CMD LEN_LO LEN_HI payload[LEN] CRC8
//   fpga -> host:  0xA5 RSP LEN_LO LEN_HI payload[LEN] CRC8
//
//   CRC8 = CRC-8/ATM (poly 0x07, init 0x00) over CMD .. payload inclusive.
//   LEN is little-endian and counts payload bytes only.
//
//   CMD 'P' (0x50) ping,   LEN 0
//       -> 'P' LEN 6 : ver_lo ver_hi K logit_w sc_log2 flags
//   CMD 'L' (0x4C) sample, LEN 2*K, payload = K signed Q8.8 logits, LE
//       -> 'T' LEN 11: token(2 LE) u(4 LE) total(4 LE) flags(1)
//   CMD 'R' (0x52) raw entropy, LEN 2, payload = byte count (LE, capped)
//       -> 'R' LEN n : n whitened TRNG bytes
//   CMD 'S' (0x53) status, LEN 0
//       -> 'S' LEN 4 : flags last_token(2 LE) rx_errors(1)
//
//   Any framing/CRC/length/busy problem answers 'E' (0x45) LEN 1 with:
//       0x01 bad CRC   0x02 unknown command   0x03 bad length   0x04 busy
//
//   flags: bit0 fallback_argmax, bit1 entropy_fail, bit2 rx_frame_error seen
// -----------------------------------------------------------------------------
`default_nettype none

module sampler_uart_top #(
    parameter integer CLK_HZ  = 100_000_000,
    parameter integer BAUD    = 115_200,
    parameter integer K       = 32,
    parameter integer LOGIT_W = 16,
    parameter integer SC_LOG2 = 12,
    parameter integer POOL_W  = 32,
    parameter integer RAW_MAX = 256   // cap on CMD 'R' byte count
) (
    input  wire       clk_100mhz,
    input  wire       resetn,      // Arty CK_RST is active low
    input  wire       uart_rxd,    // FTDI -> FPGA
    output wire       uart_txd,    // FPGA -> FTDI
    output wire [3:0] led
);

        localparam integer IDX_W = $clog2(K);
    localparam integer ACC_W = SC_LOG2 + IDX_W + 1;

    // -------------------------------------------------------------------------
    // System clock
    //
    // The board crystal is 100 MHz, but the softmax/SC datapath has a small
    // number of long carry/mux paths (fmax ~73 MHz). This is a 115200-baud
    // UART peripheral with no need for 100 MHz, so in hardware the crystal is
    // divided by 2 and the whole design runs on a BUFG-buffered 50 MHz clock.
    // The UART baud divider is told SYS_HZ (50 MHz) so the line rate stays
    // exactly BAUD. In simulation there is no BUFG primitive and timing is
    // irrelevant, so clk_sys is just the 100 MHz input and SYS_HZ == CLK_HZ;
    // wall-clock baud timing is identical either way.
    // -------------------------------------------------------------------------
`ifdef SIMULATION
    localparam integer SYS_HZ = CLK_HZ;
    wire clk_sys = clk_100mhz;
`else
    localparam integer CLK_DIV = 2;
    localparam integer SYS_HZ  = CLK_HZ / CLK_DIV;

    reg clk_div;
    always @(posedge clk_100mhz or negedge resetn) begin
        if (!resetn) begin
            clk_div <= 1'b0;
        end else begin
            clk_div <= ~clk_div;
        end
    end

    wire clk_sys;
    BUFG u_clk_sys (.I(clk_div), .O(clk_sys));
`endif

    localparam [15:0] VERSION = 16'h0100;

    // Truncated copies so the response builder never bit-selects an `integer`.
        // Explicit slices: the integer parameters are intentionally truncated.
    localparam [7:0]  K_BYTE       = K[7:0];
    localparam [7:0]  LOGIT_W_BYTE = LOGIT_W[7:0];
    localparam [7:0]  SC_LOG2_BYTE = SC_LOG2[7:0];
    localparam [15:0] RAW_MAX_W    = RAW_MAX[15:0];
    localparam [15:0] SAMPLE_LEN   = 16'd2 * K[7:0];

    localparam [7:0] SOF_RX = 8'h5A,
                     SOF_TX = 8'hA5;

    localparam [7:0] CMD_PING   = 8'h50,
                     CMD_SAMPLE = 8'h4C,
                     CMD_RAW    = 8'h52,
                     CMD_STATUS = 8'h53,
                     RSP_TOKEN  = 8'h54,
                     RSP_ERROR  = 8'h45;

    localparam [7:0] ERR_CRC     = 8'h01,
                     ERR_UNKNOWN = 8'h02,
                     ERR_LENGTH  = 8'h03,
                     ERR_BUSY    = 8'h04;

    // -------------------------------------------------------------------------
    // Reset synchroniser
    // -------------------------------------------------------------------------
        reg [1:0] rst_sync;
    wire      rst_n = rst_sync[1];

    // Reset synchroniser: rst_n fans out as an async reset everywhere else,
    // while these two flops themselves are clocked with no reset. That mix is
    // the intended reset-synchroniser topology, so silence SYNCASYNCNET.
    /* verilator lint_off SYNCASYNCNET */
    always @(posedge clk_sys) begin
        rst_sync <= {rst_sync[0], resetn};
    end
    /* verilator lint_on SYNCASYNCNET */

    // -------------------------------------------------------------------------
    // CRC-8/ATM, one byte per call
    // -------------------------------------------------------------------------
    function [7:0] crc8_step;
        input [7:0] crc_in;
        input [7:0] byte_in;
        integer     b;
        reg [7:0]   c;
        begin
            c = crc_in ^ byte_in;
            for (b = 0; b < 8; b = b + 1) begin
                c = c[7] ? ((c << 1) ^ 8'h07) : (c << 1);
            end
            crc8_step = c;
        end
    endfunction

    // -------------------------------------------------------------------------
    // UART
    // -------------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_frame_err;

    reg  [7:0] tx_data;
    reg        tx_send;
    wire       tx_ready;

        uart_rx #(.CLK_HZ(SYS_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk_sys), .rst_n(rst_n), .rx(uart_rxd),
        .data(rx_data), .valid(rx_valid), .frame_error(rx_frame_err)
    );

        uart_tx #(.CLK_HZ(SYS_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk_sys), .rst_n(rst_n),
        .data(tx_data), .send(tx_send), .tx(uart_txd), .ready(tx_ready)
    );

    // `ready` is still high during the cycle our registered `send` pulse is
    // being consumed, so gating on `ready` alone would queue a second byte the
    // transmitter is about to ignore. Wait for the pulse to clear too.
    wire tx_free = tx_ready && !tx_send;

    // -------------------------------------------------------------------------
    // TRNG + sampler
    // -------------------------------------------------------------------------
    wire              rnd_bit, rnd_bit_valid;
    wire [POOL_W-1:0] rnd_word;
    wire              rnd_word_valid;
    wire              entropy_fail;

        trng_ring_osc #(.POOL_W(POOL_W)) u_trng (
        .clk(clk_sys), .rst_n(rst_n),
        .rand_bit(rnd_bit), .rand_valid(rnd_bit_valid),
        .rand_word(rnd_word), .word_valid(rnd_word_valid),
        .entropy_fail(entropy_fail)
    );

    reg              logit_we;
    reg  [IDX_W-1:0] logit_addr;
    reg  [LOGIT_W-1:0] logit_wdata;
    reg              sample_start;

    wire              smp_busy, smp_done, smp_fallback;
    wire [IDX_W-1:0]  smp_token;
    wire [ACC_W-1:0]  smp_u, smp_total;

    // Zero-extend once so the wire format is a fixed 4-byte little-endian
    // field regardless of how SC_LOG2 / K change ACC_W.
    wire [31:0] smp_u32     = {{(32-ACC_W){1'b0}}, smp_u};
    wire [31:0] smp_total32 = {{(32-ACC_W){1'b0}}, smp_total};

    sc_softmax_sampler #(
        .K(K), .LOGIT_W(LOGIT_W), .SC_LOG2(SC_LOG2), .POOL_W(POOL_W)
        ) u_sampler (
        .clk(clk_sys), .rst_n(rst_n),
        .logit_we(logit_we), .logit_addr(logit_addr), .logit_wdata(logit_wdata),
        .rand_word(rnd_word), .rand_word_valid(rnd_word_valid),
        .rand_bit(rnd_bit), .rand_bit_valid(rnd_bit_valid),
        .start(sample_start),
        .busy(smp_busy), .done(smp_done),
        .token_id(smp_token), .draw_u(smp_u), .total_weight(smp_total),
        .fallback_argmax(smp_fallback)
    );

    // -------------------------------------------------------------------------
    // Whitened TRNG byte source for CMD 'R'
    // -------------------------------------------------------------------------
    reg [7:0] raw_sh;
    reg [3:0] raw_fill;
    reg [7:0] raw_byte;
    reg       raw_byte_valid;   // level: a fresh byte is waiting
    reg       raw_byte_take;

        always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            raw_sh         <= 8'd0;
            raw_fill       <= 4'd0;
            raw_byte       <= 8'd0;
            raw_byte_valid <= 1'b0;
        end else begin
            if (raw_byte_take) begin
                raw_byte_valid <= 1'b0;
            end
            if (rnd_bit_valid) begin
                raw_sh <= {raw_sh[6:0], rnd_bit};
                if (raw_fill == 4'd7) begin
                    raw_fill       <= 4'd0;
                    raw_byte       <= {raw_sh[6:0], rnd_bit};
                    raw_byte_valid <= 1'b1;
                end else begin
                    raw_fill <= raw_fill + 4'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Receive / dispatch
    // -------------------------------------------------------------------------
    localparam [2:0] R_SOF     = 3'd0,
                     R_CMD     = 3'd1,
                     R_LEN0    = 3'd2,
                     R_LEN1    = 3'd3,
                     R_PAYLOAD = 3'd4,
                     R_CRC     = 3'd5,
                     R_WAIT    = 3'd6;

    reg [2:0]  rstate;
    reg [7:0]  cmd;
    reg [15:0] len;
    reg [15:0] rx_count;
    reg [7:0]  rx_crc;
    reg        payload_lo;      // next logit byte is the low half
    reg [7:0]  logit_lo_byte;
    reg [15:0] raw_req;
    reg [7:0]  rx_errors;
    reg        saw_frame_err;

    // -------------------------------------------------------------------------
    // Transmit
    // -------------------------------------------------------------------------
    localparam [2:0] T_IDLE    = 3'd0,
                     T_HEADER  = 3'd1,
                     T_PAYLOAD = 3'd2,
                     T_RAW     = 3'd3,
                     T_CRC     = 3'd4;

    reg [2:0]  tstate;
    reg [7:0]  resp_buf [0:15];
    reg [7:0]  resp_cmd;
    reg [15:0] resp_len;
    reg [15:0] tx_count;
    reg [1:0]  hdr_idx;
    reg [7:0]  tx_crc;
    reg        resp_is_raw;
    reg        resp_pending;

    reg [IDX_W-1:0] last_token;

    wire [7:0] status_flags = {5'b0, saw_frame_err, entropy_fail, smp_fallback};

    integer q;

        always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            rstate        <= R_SOF;
            cmd           <= 8'd0;
            len           <= 16'd0;
            rx_count      <= 16'd0;
            rx_crc        <= 8'd0;
            payload_lo    <= 1'b1;
            logit_lo_byte <= 8'd0;
            raw_req       <= 16'd0;
            rx_errors     <= 8'd0;
            saw_frame_err <= 1'b0;
            logit_we      <= 1'b0;
            logit_addr    <= {IDX_W{1'b0}};
            logit_wdata   <= {LOGIT_W{1'b0}};
            sample_start  <= 1'b0;
            resp_cmd      <= 8'd0;
            resp_len      <= 16'd0;
            resp_is_raw   <= 1'b0;
            resp_pending  <= 1'b0;
            last_token    <= {IDX_W{1'b0}};
            for (q = 0; q < 16; q = q + 1) begin
                resp_buf[q] <= 8'd0;
            end
        end else begin
            logit_we     <= 1'b0;
            sample_start <= 1'b0;

            if (rx_frame_err && rx_valid) begin
                saw_frame_err <= 1'b1;
                if (rx_errors != 8'hFF) begin
                    rx_errors <= rx_errors + 8'd1;
                end
            end

            case (rstate)
                R_SOF: begin
                    if (rx_valid && (rx_data == SOF_RX)) begin
                        rx_crc <= 8'd0;
                        rstate <= R_CMD;
                    end
                end

                R_CMD: begin
                    if (rx_valid) begin
                        cmd    <= rx_data;
                        rx_crc <= crc8_step(rx_crc, rx_data);
                        rstate <= R_LEN0;
                    end
                end

                R_LEN0: begin
                    if (rx_valid) begin
                        len[7:0] <= rx_data;
                        rx_crc   <= crc8_step(rx_crc, rx_data);
                        rstate   <= R_LEN1;
                    end
                end

                R_LEN1: begin
                    if (rx_valid) begin
                        len[15:8]  <= rx_data;
                        rx_crc     <= crc8_step(rx_crc, rx_data);
                        rx_count   <= 16'd0;
                        payload_lo <= 1'b1;
                        // {rx_data, len[7:0]} is the full length this cycle.
                        rstate     <= ({rx_data, len[7:0]} == 16'd0) ? R_CRC : R_PAYLOAD;
                    end
                end

                R_PAYLOAD: begin
                    if (rx_valid) begin
                        rx_crc   <= crc8_step(rx_crc, rx_data);
                        rx_count <= rx_count + 16'd1;

                        if (cmd == CMD_SAMPLE) begin
                            // Little-endian int16 per candidate.
                            if (payload_lo) begin
                                logit_lo_byte <= rx_data;
                                payload_lo    <= 1'b0;
                            end else begin
                                // High byte arrives at rx_count = 2*i + 1,
                                // so the candidate index is rx_count >> 1.
                                logit_we    <= 1'b1;
                                logit_addr  <= rx_count[IDX_W:1];
                                logit_wdata <= {rx_data, logit_lo_byte};
                                payload_lo  <= 1'b1;
                            end
                        end else if (cmd == CMD_RAW) begin
                            if (rx_count == 16'd0) begin
                                raw_req[7:0] <= rx_data;
                            end else begin
                                raw_req[15:8] <= rx_data;
                            end
                        end

                        if (rx_count + 16'd1 == len) begin
                            rstate <= R_CRC;
                        end
                    end
                end

                R_CRC: begin
                    if (rx_valid) begin
                        if (rx_data != rx_crc) begin
                            resp_cmd    <= RSP_ERROR;
                            resp_buf[0] <= ERR_CRC;
                            resp_len    <= 16'd1;
                            resp_is_raw <= 1'b0;
                            resp_pending<= 1'b1;
                            rstate      <= R_SOF;
                        end else begin
                            case (cmd)
                                CMD_PING: begin
                                    if (len != 16'd0) begin
                                        resp_cmd    <= RSP_ERROR;
                                        resp_buf[0] <= ERR_LENGTH;
                                        resp_len    <= 16'd1;
                                    end else begin
                                        resp_cmd    <= CMD_PING;
                                        resp_buf[0] <= VERSION[7:0];
                                        resp_buf[1] <= VERSION[15:8];
                                        resp_buf[2] <= K_BYTE;
                                        resp_buf[3] <= LOGIT_W_BYTE;
                                        resp_buf[4] <= SC_LOG2_BYTE;
                                        resp_buf[5] <= status_flags;
                                        resp_len    <= 16'd6;
                                    end
                                    resp_is_raw  <= 1'b0;
                                    resp_pending <= 1'b1;
                                    rstate       <= R_SOF;
                                end

                                CMD_STATUS: begin
                                    resp_cmd    <= CMD_STATUS;
                                    resp_buf[0] <= status_flags;
                                    resp_buf[1] <= {{(8-IDX_W){1'b0}}, last_token};
                                    resp_buf[2] <= 8'd0;
                                    resp_buf[3] <= rx_errors;
                                    resp_len    <= 16'd4;
                                    resp_is_raw <= 1'b0;
                                    resp_pending<= 1'b1;
                                    rstate      <= R_SOF;
                                end

                                CMD_RAW: begin
                                    if (len != 16'd2) begin
                                        resp_cmd    <= RSP_ERROR;
                                        resp_buf[0] <= ERR_LENGTH;
                                        resp_len    <= 16'd1;
                                        resp_is_raw <= 1'b0;
                                    end else begin
                                        resp_cmd    <= CMD_RAW;
                                        resp_len    <= (raw_req > RAW_MAX_W)
                                                       ? RAW_MAX_W : raw_req;
                                        resp_is_raw <= 1'b1;
                                    end
                                    resp_pending <= 1'b1;
                                    rstate       <= R_SOF;
                                end

                                CMD_SAMPLE: begin
                                    if (len != SAMPLE_LEN) begin
                                        resp_cmd    <= RSP_ERROR;
                                        resp_buf[0] <= ERR_LENGTH;
                                        resp_len    <= 16'd1;
                                        resp_is_raw <= 1'b0;
                                        resp_pending<= 1'b1;
                                        rstate      <= R_SOF;
                                    end else if (smp_busy) begin
                                        resp_cmd    <= RSP_ERROR;
                                        resp_buf[0] <= ERR_BUSY;
                                        resp_len    <= 16'd1;
                                        resp_is_raw <= 1'b0;
                                        resp_pending<= 1'b1;
                                        rstate      <= R_SOF;
                                    end else begin
                                        sample_start <= 1'b1;
                                        rstate       <= R_WAIT;
                                    end
                                end

                                default: begin
                                    resp_cmd    <= RSP_ERROR;
                                    resp_buf[0] <= ERR_UNKNOWN;
                                    resp_len    <= 16'd1;
                                    resp_is_raw <= 1'b0;
                                    resp_pending<= 1'b1;
                                    rstate      <= R_SOF;
                                end
                            endcase
                        end
                    end
                end

                // Sampling takes ~2^SC_LOG2 cycles plus the entropy wait.
                R_WAIT: begin
                    if (smp_done) begin
                        resp_cmd    <= RSP_TOKEN;
                        resp_buf[0] <= {{(8-IDX_W){1'b0}}, smp_token};
                        resp_buf[1] <= 8'd0;
                        resp_buf[2] <= smp_u32[7:0];
                        resp_buf[3] <= smp_u32[15:8];
                        resp_buf[4] <= smp_u32[23:16];
                        resp_buf[5] <= smp_u32[31:24];
                        resp_buf[6] <= smp_total32[7:0];
                        resp_buf[7] <= smp_total32[15:8];
                        resp_buf[8] <= smp_total32[23:16];
                        resp_buf[9] <= smp_total32[31:24];
                        resp_buf[10]<= status_flags;
                        resp_len    <= 16'd11;
                        resp_is_raw <= 1'b0;
                        resp_pending<= 1'b1;
                        last_token  <= smp_token;
                        rstate      <= R_SOF;
                    end
                end

                default: rstate <= R_SOF;
            endcase

            // The TX side clears the request once it has latched it.
            if (resp_pending && (tstate == T_HEADER)) begin
                resp_pending <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Response streamer
    // -------------------------------------------------------------------------
        always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            tstate        <= T_IDLE;
            tx_data       <= 8'd0;
            tx_send       <= 1'b0;
            tx_count      <= 16'd0;
            hdr_idx       <= 2'd0;
            tx_crc        <= 8'd0;
            raw_byte_take <= 1'b0;
        end else begin
            tx_send       <= 1'b0;
            raw_byte_take <= 1'b0;

            case (tstate)
                T_IDLE: begin
                    if (resp_pending && tx_free) begin
                        tx_data  <= SOF_TX;
                        tx_send  <= 1'b1;
                        tx_crc   <= 8'd0;
                        hdr_idx  <= 2'd0;
                        tx_count <= 16'd0;
                        tstate   <= T_HEADER;
                    end
                end

                // cmd, len_lo, len_hi — all CRC'd, unlike the SOF.
                T_HEADER: begin
                    if (tx_free) begin
                        case (hdr_idx)
                            2'd0: begin
                                tx_data <= resp_cmd;
                                tx_crc  <= crc8_step(tx_crc, resp_cmd);
                            end
                            2'd1: begin
                                tx_data <= resp_len[7:0];
                                tx_crc  <= crc8_step(tx_crc, resp_len[7:0]);
                            end
                            default: begin
                                tx_data <= resp_len[15:8];
                                tx_crc  <= crc8_step(tx_crc, resp_len[15:8]);
                            end
                        endcase
                        tx_send <= 1'b1;
                        if (hdr_idx == 2'd2) begin
                            if (resp_len == 16'd0) begin
                                tstate <= T_CRC;
                            end else begin
                                tstate <= resp_is_raw ? T_RAW : T_PAYLOAD;
                            end
                        end else begin
                            hdr_idx <= hdr_idx + 2'd1;
                        end
                    end
                end

                T_PAYLOAD: begin
                    if (tx_free) begin
                        tx_data  <= resp_buf[tx_count[3:0]];
                        tx_crc   <= crc8_step(tx_crc, resp_buf[tx_count[3:0]]);
                        tx_send  <= 1'b1;
                        tx_count <= tx_count + 16'd1;
                        if (tx_count + 16'd1 == resp_len) begin
                            tstate <= T_CRC;
                        end
                    end
                end

                // Stream straight from the entropy source; stalls until the
                // von Neumann extractor has produced another byte.
                T_RAW: begin
                    if (tx_free && raw_byte_valid) begin
                        tx_data       <= raw_byte;
                        tx_crc        <= crc8_step(tx_crc, raw_byte);
                        tx_send       <= 1'b1;
                        raw_byte_take <= 1'b1;
                        tx_count      <= tx_count + 16'd1;
                        if (tx_count + 16'd1 == resp_len) begin
                            tstate <= T_CRC;
                        end
                    end
                end

                T_CRC: begin
                    if (tx_free) begin
                        tx_data <= tx_crc;
                        tx_send <= 1'b1;
                        tstate  <= T_IDLE;
                    end
                end

                default: tstate <= T_IDLE;
            endcase
        end
    end

    // led[0] heartbeat, led[1] sampling, led[2] entropy health, led[3] rx error
        reg [24:0] beat;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            beat <= 25'd0;
        end else begin
            beat <= beat + 25'd1;
        end
    end

    assign led = {saw_frame_err, entropy_fail, smp_busy, beat[24]};

endmodule

`default_nettype wire
