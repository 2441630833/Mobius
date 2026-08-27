// -----------------------------------------------------------------------------
// sc_softmax_sampler — hardware categorical sampler over K logits
//
// Samples token_id ~ softmax(logits) using stochastic computing for the
// exponential and physical thermal noise for the draw itself.
//
// HOW THE EXPONENTIAL IS FREE
// ---------------------------
// softmax is shift-invariant, so we work with the non-negative deficit
//
//     d_i = l_max - l_i      (Q8.8, nats)
//
// and need a Bernoulli stream of probability exp(-d_i). Decompose d_i by bit:
//
//     exp(-d_i) = product over set bits j of  exp(-2^(j-8))
//
// Every factor is a *constant*, so a single shared bank of 16 SNGs driving
// 16 constants covers all K candidates. Per candidate the product of
// independent streams is one AND-reduce:
//
//     fire_i = &( cbit | ~d_i )
//
// i.e. "AND in the constant stream for each set deficit bit, ignore the rest".
// Cost is ~5 LUTs per candidate instead of a multiplier or an exp LUT.
//
// Constants for j >= 12 round to zero in Q0.16 (exp(-16) ~ 1.1e-7), so any
// candidate more than ~16 nats below the max is sampled with probability 0.
// That is the intended behaviour for top-K sampling.
//
// The 16 constant streams are shared across candidates, so candidates are
// mutually correlated even though each candidate's own marginal probability is
// exact. Marginal counts -- which is all the CDF uses -- are unbiased.
//
// HOW THE DRAW IS PHYSICAL
// ------------------------
// Counting fires for N = 2^SC_LOG2 cycles gives cnt_i ~ N * exp(-d_i), an
// unnormalised softmax weight. Sampling is then inverse-CDF against a uniform
// draw taken from the ring-oscillator TRNG:
//
//   - mask the TRNG word down to the bit width of `total` (smear-right),
//   - reject and redraw while u >= total  =>  exactly uniform on [0, total),
//   - walk the prefix sum, first index with acc > u wins.
//
// No arithmetic on the entropy is needed, so the sampled token is a direct
// function of fabric thermal noise.
//
// Degenerate case: if every candidate is far enough below the max that
// total == 0, the sampler returns argmax and raises `fallback_argmax` rather
// than hanging or emitting an out-of-range index.
// -----------------------------------------------------------------------------
`default_nettype none

// LOGIT_W is fixed at 16 (signed Q8.8): the exp_const table below encodes that
// exact scaling, so changing the width without regenerating the table would
// silently change the temperature. POOL_W must be >= ACC_W so a single TRNG
// word can supply the whole uniform draw.
module sc_softmax_sampler #(
    parameter integer K        = 32,  // candidate logits (top-K window)
    parameter integer LOGIT_W  = 16,  // signed Q8.8 — see note above
    parameter integer SC_LOG2  = 12,  // stochastic stream length = 2^SC_LOG2
    parameter integer POOL_W   = 32,  // TRNG word width
    // Derived widths. Declared as parameters so the port list can use them;
    // never override at instantiation.
    parameter integer IDX_W    = $clog2(K),
    parameter integer CNT_W    = SC_LOG2 + 1,
    parameter integer ACC_W    = SC_LOG2 + IDX_W + 1
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // Logit register file (written by the host interface).
    input  wire                  logit_we,
    input  wire [IDX_W-1:0]      logit_addr,
    input  wire [LOGIT_W-1:0]    logit_wdata,

    // Physical entropy.
    input  wire [POOL_W-1:0]     rand_word,
    input  wire                  rand_word_valid,
    input  wire                  rand_bit,
    input  wire                  rand_bit_valid,

    input  wire                  start,
    output reg                   busy,
    output reg                   done,           // 1-cycle pulse
    output reg  [IDX_W-1:0]      token_id,
    output reg  [ACC_W-1:0]      draw_u,         // the uniform actually used
    output reg  [ACC_W-1:0]      total_weight,   // sum of stochastic counts
    output reg                   fallback_argmax
);

    localparam [SC_LOG2:0] SC_LAST = {1'b1, {SC_LOG2{1'b0}}} - 1'b1;
    // Last valid candidate index, in the (IDX_W+1)-bit counter width.
    localparam [IDX_W:0]   IDX_LAST = K[IDX_W:0] - {{IDX_W{1'b0}}, 1'b1};

    // -------------------------------------------------------------------------
    // exp(-2^(j-8)) in Q0.16, j = 0..15. Entries 12..15 are 0 by rounding.
    // -------------------------------------------------------------------------
    function [15:0] exp_const;
        input integer j;
        begin
            case (j)
                0:  exp_const = 16'd65280; // exp(-1/256)
                1:  exp_const = 16'd65030; // exp(-1/128)
                2:  exp_const = 16'd64524; // exp(-1/64)
                3:  exp_const = 16'd63524; // exp(-1/32)
                4:  exp_const = 16'd61569; // exp(-1/16)
                5:  exp_const = 16'd57841; // exp(-1/8)
                6:  exp_const = 16'd51035; // exp(-1/4)
                7:  exp_const = 16'd39749; // exp(-1/2)
                8:  exp_const = 16'd24109; // exp(-1)
                9:  exp_const = 16'd8869;  // exp(-2)
                10: exp_const = 16'd1200;  // exp(-4)
                11: exp_const = 16'd22;    // exp(-8)
                default: exp_const = 16'd0;
            endcase
        end
    endfunction

    // Distinct polynomials/seeds keep the 16 constant streams decorrelated.
    function [15:0] lfsr_taps;
        input integer j;
        begin
            case (j % 4)
                0: lfsr_taps = 16'hB400;
                1: lfsr_taps = 16'hA3BA;
                2: lfsr_taps = 16'hD295;
                default: lfsr_taps = 16'h8016;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Logit register file
    // -------------------------------------------------------------------------
    reg [LOGIT_W-1:0] logits [0:K-1];

    always @(posedge clk) begin
        if (logit_we) begin
            logits[logit_addr] <= logit_wdata;
        end
    end

    // -------------------------------------------------------------------------
    // Shared constant-stream bank, reseeded from the TRNG round-robin so no
    // single LFSR is ever fully deterministic.
    // -------------------------------------------------------------------------
    wire [15:0] cbit_rnd [0:15];
    wire [15:0] cbit;
    reg  [3:0]  reseed_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reseed_sel <= 4'd0;
        end else if (rand_bit_valid) begin
            reseed_sel <= reseed_sel + 4'd1;
        end
    end

    genvar j;
    generate
        for (j = 0; j < 16; j = j + 1) begin : g_stream
            sc_lfsr #(
                .W    (16),
                .TAPS (lfsr_taps(j)),
                .SEED (16'hACE1 + j[15:0] * 16'd2531)
            ) u_lfsr (
                .clk        (clk),
                .rst_n      (rst_n),
                .en         (1'b1),
                .reseed_en  (rand_bit_valid && (reseed_sel == j[3:0])),
                .reseed_bit (rand_bit),
                .value      (cbit_rnd[j])
            );

            sc_sng #(.W(16)) u_sng (
                .rnd       (cbit_rnd[j]),
                .threshold (exp_const(j)),
                .bit_out   (cbit[j])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Per-candidate deficit and fire term
    // -------------------------------------------------------------------------
    reg  [LOGIT_W-1:0] lmax;
    reg  [IDX_W-1:0]   amax;

    wire [15:0]        deficit [0:K-1];
    wire [K-1:0]       fire;

    genvar c;
    generate
        for (c = 0; c < K; c = c + 1) begin : g_cand
            // Both operands are 16-bit signed, so the sign-extended difference
            // is exactly 17 bits and cannot overflow. lmax is the running
            // maximum, so bit 16 (the sign) should never be set; guarding it
            // keeps a mid-scan read from producing a bogus huge deficit.
            wire signed [16:0] diff = $signed({lmax[15], lmax}) -
                                      $signed({logits[c][15], logits[c]});

            assign deficit[c] = diff[16] ? 16'h0000 : diff[15:0];

            assign fire[c] = &(cbit | ~deficit[c]);
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Control
    // -------------------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0,
                     S_MAX  = 3'd1,
                     S_SC   = 3'd2,
                     S_SUM  = 3'd3,
                     S_DRAW = 3'd4,
                     S_SCAN = 3'd5,
                     S_DONE = 3'd6;

    reg [2:0]         state;
    reg [IDX_W:0]     idx;
    reg [SC_LOG2:0]   sc_cycle;
    reg [CNT_W-1:0]   cnt [0:K-1];
    reg [ACC_W-1:0]   acc;
    reg               found;

    // 2^m - 1 for m = MSB position of total_weight, via right-smear.
    reg [ACC_W-1:0] smear;
    always @* begin
        smear = total_weight;
        smear = smear | (smear >> 1);
        smear = smear | (smear >> 2);
        smear = smear | (smear >> 4);
        smear = smear | (smear >> 8);
        smear = smear | (smear >> 16);
    end

    wire [ACC_W-1:0] draw_candidate = rand_word[ACC_W-1:0] & smear;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            busy            <= 1'b0;
            done            <= 1'b0;
            token_id        <= {IDX_W{1'b0}};
            draw_u          <= {ACC_W{1'b0}};
            total_weight    <= {ACC_W{1'b0}};
            fallback_argmax <= 1'b0;
            idx             <= {(IDX_W+1){1'b0}};
            sc_cycle        <= {(SC_LOG2+1){1'b0}};
            acc             <= {ACC_W{1'b0}};
            found           <= 1'b0;
            lmax            <= {LOGIT_W{1'b0}};
            amax            <= {IDX_W{1'b0}};
            for (i = 0; i < K; i = i + 1) begin
                cnt[i] <= {CNT_W{1'b0}};
            end
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        busy            <= 1'b1;
                        fallback_argmax <= 1'b0;
                        total_weight    <= {ACC_W{1'b0}};
                        idx             <= {(IDX_W+1){1'b0}};
                        // Smallest signed value so the first candidate wins.
                        lmax            <= {1'b1, {(LOGIT_W-1){1'b0}}};
                        amax            <= {IDX_W{1'b0}};
                        for (i = 0; i < K; i = i + 1) begin
                            cnt[i] <= {CNT_W{1'b0}};
                        end
                        state <= S_MAX;
                    end
                end

                // Find l_max so every deficit is non-negative.
                S_MAX: begin
                    if ($signed(logits[idx[IDX_W-1:0]]) > $signed(lmax)) begin
                        lmax <= logits[idx[IDX_W-1:0]];
                        amax <= idx[IDX_W-1:0];
                    end
                    if (idx == IDX_LAST) begin
                        idx      <= {(IDX_W+1){1'b0}};
                        sc_cycle <= {(SC_LOG2+1){1'b0}};
                        state    <= S_SC;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                // Accumulate stochastic weights for 2^SC_LOG2 cycles.
                S_SC: begin
                    for (i = 0; i < K; i = i + 1) begin
                        if (fire[i]) begin
                            cnt[i] <= cnt[i] + {{(CNT_W-1){1'b0}}, 1'b1};
                        end
                    end
                    if (sc_cycle == SC_LAST) begin
                        idx   <= {(IDX_W+1){1'b0}};
                        state <= S_SUM;
                    end else begin
                        sc_cycle <= sc_cycle + 1'b1;
                    end
                end

                S_SUM: begin
                    total_weight <= total_weight +
                                    {{(ACC_W-CNT_W){1'b0}}, cnt[idx[IDX_W-1:0]]};
                    if (idx == IDX_LAST) begin
                        idx   <= {(IDX_W+1){1'b0}};
                        state <= S_DRAW;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                // Rejection-sample a uniform on [0, total_weight).
                S_DRAW: begin
                    if (total_weight == {ACC_W{1'b0}}) begin
                        // Every candidate underflowed: fall back to argmax.
                        token_id        <= amax;
                        draw_u          <= {ACC_W{1'b0}};
                        fallback_argmax <= 1'b1;
                        state           <= S_DONE;
                    end else if (rand_word_valid && (draw_candidate < total_weight)) begin
                        draw_u   <= draw_candidate;
                        acc      <= {ACC_W{1'b0}};
                        found    <= 1'b0;
                        idx      <= {(IDX_W+1){1'b0}};
                        // Safe default: the scan below always overwrites this
                        // because draw_u < total_weight.
                        token_id <= amax;
                        state    <= S_SCAN;
                    end
                end

                // Inverse CDF: first prefix sum strictly greater than u wins.
                S_SCAN: begin
                    if (!found) begin
                        if ((acc + {{(ACC_W-CNT_W){1'b0}}, cnt[idx[IDX_W-1:0]]}) > draw_u) begin
                            token_id <= idx[IDX_W-1:0];
                            found    <= 1'b1;
                        end else begin
                            acc <= acc + {{(ACC_W-CNT_W){1'b0}}, cnt[idx[IDX_W-1:0]]};
                        end
                    end
                    if (idx == IDX_LAST) begin
                        state <= S_DONE;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
