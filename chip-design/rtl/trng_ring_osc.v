// -----------------------------------------------------------------------------
// trng_ring_osc — ring-oscillator thermal-noise TRNG
//
// Entropy source: NUM_RINGS free-running inverter loops. Their oscillation
// period is modulated by thermal (Johnson-Nyquist) noise in the fabric, so
// sampling them with the system clock captures true jitter, not a PRNG.
//
// Pipeline:  rings -> XOR tree -> sysclk sample -> von Neumann debias
//            -> 32-bit whitening pool -> rand_bit / rand_word
//
// The von Neumann extractor discards correlated pairs, which removes the
// static duty-cycle bias of the ring array at the cost of <1/4 throughput.
// The pool exists only to spread that unbiased-but-slow bit over a wide word;
// it is reseeded continuously so it can never free-run as a plain LFSR.
//
// SYNTHESIS NOTE: the ring loops must survive logic optimisation. The `keep`
// attributes below are honoured by Yosys and Vivado. Combinational loops are
// intentional here — see constraints/arty_a7_35t.xdc for the matching
// set_disable_timing / ALLOW_COMBINATORIAL_LOOPS waivers.
//
// SIMULATION: an event-driven simulator cannot run a zero-delay combinational
// loop, so `SIMULATION` swaps the rings for a jitter-modelling LFSR. The
// digital pipeline after the sampler is identical in both builds.
// -----------------------------------------------------------------------------
`default_nettype none

module trng_ring_osc #(
    parameter integer NUM_RINGS  = 8,   // independent oscillators
    parameter integer RING_LEN   = 5,   // inverters per loop (must be odd)
    parameter integer POOL_W     = 32,  // whitening pool width
    parameter integer STUCK_LIMIT = 64  // identical raw bits => health failure
) (
    input  wire              clk,
    input  wire              rst_n,

    output wire              rand_bit,     // unbiased bit, qualified by rand_valid
    output wire              rand_valid,
    output reg  [POOL_W-1:0] rand_word,    // whitened pool, refreshed continuously
    output reg               word_valid,   // pulses once per POOL_W accepted bits
    output reg               entropy_fail  // sticky: raw source looks dead
);

    // -------------------------------------------------------------------------
    // Raw entropy
    // -------------------------------------------------------------------------
    wire raw_xor;

`ifdef SIMULATION
    // Jitter model: a maximal-length LFSR whose tap is perturbed by a second
    // counter, giving a non-periodic-looking bit for regression tests. This is
    // NOT an entropy source and is never synthesised.
    reg [30:0] sim_lfsr;
    reg [4:0]  sim_phase;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sim_lfsr  <= 31'h2A5F_1C3B;
            sim_phase <= 5'd0;
        end else begin
            sim_lfsr  <= {sim_lfsr[29:0], sim_lfsr[30] ^ sim_lfsr[27] ^ sim_phase[4]};
            sim_phase <= sim_phase + 5'd1;
        end
    end
    assign raw_xor = sim_lfsr[30] ^ sim_lfsr[11] ^ sim_phase[0];
`else
    // Real fabric: NUM_RINGS combinational loops, XOR-combined.
    (* keep = "true" *) wire [NUM_RINGS-1:0] osc_out;

    genvar r, s;
    generate
        for (r = 0; r < NUM_RINGS; r = r + 1) begin : g_ring
            (* keep = "true" *) wire [RING_LEN-1:0] stage;
            for (s = 0; s < RING_LEN; s = s + 1) begin : g_stage
                if (s == 0) begin : g_head
                    // Gate the loop with rst_n so the ring is quiet in reset.
                    (* keep = "true" *) LUT2 #(.INIT(4'b0001)) u_inv (
                        .O(stage[0]), .I0(stage[RING_LEN-1]), .I1(!rst_n)
                    );
                end else begin : g_tail
                    (* keep = "true" *) LUT1 #(.INIT(2'b01)) u_inv (
                        .O(stage[s]), .I0(stage[s-1])
                    );
                end
            end
            assign osc_out[r] = stage[RING_LEN-1];
        end
    endgenerate

    // Two-stage synchroniser: the ring taps are asynchronous to clk.
    reg [NUM_RINGS-1:0] sync0, sync1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync0 <= {NUM_RINGS{1'b0}};
            sync1 <= {NUM_RINGS{1'b0}};
        end else begin
            sync0 <= osc_out;
            sync1 <= sync0;
        end
    end
    assign raw_xor = ^sync1;
`endif

    // -------------------------------------------------------------------------
    // Von Neumann debias: consume raw bits in pairs, emit only on 01 / 10.
    // -------------------------------------------------------------------------
    reg       have_first;
    reg       first_bit;
    reg       vn_bit;
    reg       vn_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_first <= 1'b0;
            first_bit  <= 1'b0;
            vn_bit     <= 1'b0;
            vn_valid   <= 1'b0;
        end else begin
            vn_valid <= 1'b0;
            if (!have_first) begin
                first_bit  <= raw_xor;
                have_first <= 1'b1;
            end else begin
                have_first <= 1'b0;
                if (first_bit != raw_xor) begin
                    vn_bit   <= first_bit;
                    vn_valid <= 1'b1;
                end
            end
        end
    end

    assign rand_bit   = vn_bit;
    assign rand_valid = vn_valid;

    // -------------------------------------------------------------------------
    // Health test: a stuck ring array produces a long run of identical raw
    // bits. Sticky so the host always sees that the sample was untrustworthy.
    // -------------------------------------------------------------------------
    localparam integer               RUN_W     = $clog2(STUCK_LIMIT + 1);
    localparam [RUN_W-1:0]           RUN_LIMIT = STUCK_LIMIT[RUN_W-1:0];
    localparam [RUN_W-1:0]           RUN_ONE   = {{(RUN_W-1){1'b0}}, 1'b1};

    reg             last_raw;
    reg [RUN_W-1:0] run_len;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_raw     <= 1'b0;
            run_len      <= {RUN_W{1'b0}};
            entropy_fail <= 1'b0;
        end else begin
            if (raw_xor == last_raw) begin
                if (run_len == RUN_LIMIT) begin
                    entropy_fail <= 1'b1;
                end else begin
                    run_len <= run_len + RUN_ONE;
                end
            end else begin
                run_len <= {RUN_W{1'b0}};
            end
            last_raw <= raw_xor;
        end
    end

    // -------------------------------------------------------------------------
    // Whitening pool: shift in each accepted bit and fold it across the word.
    // Reseeded every accepted bit, so it never runs as a standalone PRNG.
    // -------------------------------------------------------------------------
    localparam integer     CNT_W    = $clog2(POOL_W);
    localparam [CNT_W-1:0] FILL_TOP = POOL_W[CNT_W-1:0] - {{(CNT_W-1){1'b0}}, 1'b1};
    localparam [CNT_W-1:0] FILL_ONE = {{(CNT_W-1){1'b0}}, 1'b1};

    reg [CNT_W-1:0] fill;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rand_word  <= {POOL_W{1'b0}};
            fill       <= {CNT_W{1'b0}};
            word_valid <= 1'b0;
        end else begin
            word_valid <= 1'b0;
            if (vn_valid) begin
                rand_word <= {rand_word[POOL_W-2:0],
                              vn_bit ^ rand_word[POOL_W-1] ^ rand_word[POOL_W/2]};
                if (fill == FILL_TOP) begin
                    fill       <= {CNT_W{1'b0}};
                    word_valid <= 1'b1;
                end else begin
                    fill <= fill + FILL_ONE;
                end
            end
        end
    end

endmodule

`default_nettype wire
