// -----------------------------------------------------------------------------
// sc_core — stochastic-computing primitives
//
// In stochastic computing a real number p in [0,1] is carried as a Bernoulli
// bitstream whose time-average is p. Multiplication of two *independent*
// streams is a single AND gate, which is what makes the exponential in
// sc_softmax_sampler cheap enough to fit alongside a SoC on an Arty A7-35T.
//
//   sc_lfsr  — decorrelated pseudo-random word, continuously reseeded from the
//              physical TRNG so each stream carries real entropy.
//   sc_sng   — stochastic number generator: word < threshold => Bernoulli bit.
// -----------------------------------------------------------------------------
`default_nettype none

// Galois LFSR with an XOR reseed port.
//
// `reseed_bit` is folded into the feedback tap whenever `reseed_en` is high,
// which lets the ring-oscillator TRNG inject physical entropy without ever
// stalling the stream. TAPS is the polynomial mask; SEED must be non-zero
// (an all-zero Galois LFSR is a fixed point).
module sc_lfsr #(
    parameter integer W    = 16,
    parameter [15:0]  TAPS = 16'hB400,
    parameter [15:0]  SEED = 16'hACE1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         en,
    input  wire         reseed_en,
    input  wire         reseed_bit,
    output wire [W-1:0] value
);

    reg [W-1:0] state;

    wire feedback = state[0] ^ (reseed_en & reseed_bit);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= SEED[W-1:0];
        end else if (en) begin
            state <= feedback ? ((state >> 1) ^ TAPS[W-1:0])
                              :  (state >> 1);
        end
    end

    assign value = state;

endmodule


// Stochastic number generator: emits 1 with probability threshold / 2^W.
//
// `threshold` is unsigned Q0.W, so 0 means "never fire" and 2^W-1 means
// "fire on all but one code". The comparison is strict-less-than so that a
// threshold of 0 is exactly probability 0.
module sc_sng #(
    parameter integer W = 16
) (
    input  wire [W-1:0] rnd,
    input  wire [W-1:0] threshold,
    output wire         bit_out
);

    assign bit_out = (rnd < threshold);

endmodule

`default_nettype wire
