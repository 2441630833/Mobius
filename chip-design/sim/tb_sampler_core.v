// -----------------------------------------------------------------------------
// tb_sampler_core — fast core-level testbench (no UART)
//
// Drives trng_ring_osc -> sc_softmax_sampler directly, so it can afford a
// large Monte-Carlo run to validate the stochastic-softmax distribution.
// The UART wire protocol is covered separately by tb_sampler_iverilog.v.
//
// Checks:
//   * every draw: token in [0,K), draw_u < total_weight, no fallback
//   * uniform logits -> histogram flat within 6-sigma binomial gates
//   * weighted logits (proportional to 4,4,2,2,1,1,1,1) -> histogram matches
//     softmax probabilities within 6-sigma gates, and group ordering holds
//
// Run:
//   iverilog -g2012 -DSIMULATION -o build/iv/tb_core.vvp \
//       rtl/trng_ring_osc.v rtl/sc_core.v rtl/sc_softmax_sampler.v \
//       sim/tb_sampler_core.v
//   vvp build/iv/tb_core.vvp
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tb_sampler_core;

    localparam integer K       = 8;
    localparam integer LOGIT_W = 16;
    localparam integer SC_LOG2 = 8;    // 256-cycle stochastic streams
    localparam integer POOL_W  = 32;
    localparam integer IDX_W   = $clog2(K);
    localparam integer ACC_W   = SC_LOG2 + IDX_W + 1;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- TRNG (simulation LFSR jitter model under -DSIMULATION) ------------
    wire              rnd_bit, rnd_bit_valid, rnd_word_valid, entropy_fail;
    wire [POOL_W-1:0] rnd_word;

    trng_ring_osc #(.POOL_W(POOL_W)) u_trng (
        .clk(clk), .rst_n(rst_n),
        .rand_bit(rnd_bit), .rand_valid(rnd_bit_valid),
        .rand_word(rnd_word), .word_valid(rnd_word_valid),
        .entropy_fail(entropy_fail)
    );

    // ---- stochastic softmax sampler ---------------------------------------
    reg               logit_we;
    reg  [IDX_W-1:0]  logit_addr;
    reg  [LOGIT_W-1:0] logit_wdata;
    reg               start;
    wire              busy, done, fallback;
    wire [IDX_W-1:0]  token;
    wire [ACC_W-1:0]  draw_u, total;

    sc_softmax_sampler #(
        .K(K), .LOGIT_W(LOGIT_W), .SC_LOG2(SC_LOG2), .POOL_W(POOL_W)
    ) u_smp (
        .clk(clk), .rst_n(rst_n),
        .logit_we(logit_we), .logit_addr(logit_addr),
        .logit_wdata(logit_wdata),
        .rand_word(rnd_word), .rand_word_valid(rnd_word_valid),
        .rand_bit(rnd_bit), .rand_bit_valid(rnd_bit_valid),
        .start(start), .busy(busy), .done(done),
        .token_id(token), .draw_u(draw_u), .total_weight(total),
        .fallback_argmax(fallback)
    );

    // ---- helpers -----------------------------------------------------------
    integer errors = 0;
    integer checks = 0;

    task check;
        input cond;
        input [511:0] msg;
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("  FAIL: %0s", msg);
            end
        end
    endtask

    reg signed [15:0] lg [0:K-1];
    integer hist [0:K-1];
    integer i, exp_cnt;

    task load_logits;
        integer k;
        begin
            @(posedge clk);
            for (k = 0; k < K; k = k + 1) begin
                logit_we    <= 1'b1;
                logit_addr  <= k[IDX_W-1:0];
                logit_wdata <= lg[k];
                @(posedge clk);
            end
            logit_we <= 1'b0;
        end
    endtask

    // Pulse start and wait for the done pulse; returns token in `token`.
    task do_draw;
        begin
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            @(posedge done);
            @(posedge clk);
        end
    endtask

    initial begin
        logit_we   = 1'b0;
        logit_addr = {IDX_W{1'b0}};
        logit_wdata= {LOGIT_W{1'b0}};
        start      = 1'b0;

        // Reset and let the TRNG pool fill.
        rst_n = 1'b0;
        repeat (200) @(posedge clk);
        rst_n = 1'b1;
        repeat (2000) @(posedge clk);

        check(entropy_fail == 1'b0, "TRNG entropy health not failed");

        // ---- 1. uniform distribution, 4000 draws ---------------------------
        $display("[core-1] uniform logits x4000 draws");
        for (i = 0; i < K; i = i + 1) begin
            lg[i]   = 16'd0;
            hist[i] = 0;
        end
        load_logits();
        for (i = 0; i < 4000; i = i + 1) begin
            do_draw();
            check(fallback == 1'b0, "uniform: no argmax fallback");
            check(token < K, "uniform: token in [0,K)");
            check(draw_u < total, "uniform: u < total");
            hist[token] = hist[token] + 1;
        end
        // p = 1/8 = 0.125, mean 500, sigma ~20.9; 6-sigma gate ~ +-125.
        for (i = 0; i < K; i = i + 1) begin
            exp_cnt = 500;
            if (hist[i] < 375 || hist[i] > 625) begin
                $display("  FAIL: uniform hist[%0d]=%0d outside [375,625]",
                         i, hist[i]);
                errors = errors + 1;
            end
            checks = checks + 1;
            $display("    token %0d: %0d (expect ~%0d)", i, hist[i], exp_cnt);
        end

        // ---- 2. weighted distribution, 4000 draws --------------------------
        // weights 4,4,2,2,1,1,1,1 (sum 16); logits = ln(weight)*256.
        $display("[core-2] weighted logits x4000 draws");
        for (i = 0; i < K; i = i + 1) begin
            hist[i] = 0;
            if (i < 2)       lg[i] = 16'sd355;  // ln(4)*256
            else if (i < 4)  lg[i] = 16'sd177;  // ln(2)*256
            else             lg[i] = 16'sd0;
        end
        load_logits();
        for (i = 0; i < 4000; i = i + 1) begin
            do_draw();
            check(fallback == 1'b0, "weighted: no argmax fallback");
            check(token < K, "weighted: token in [0,K)");
            check(draw_u < total, "weighted: u < total");
            hist[token] = hist[token] + 1;
        end
        // p: .25 (mean 1000, sigma 27.4), .125 (mean 500, sigma 20.9),
        //    .0625 (mean 250, sigma 15.3). 6-sigma gates below.
        for (i = 0; i < K; i = i + 1) begin
            if (i < 2) begin
                exp_cnt = 1000;
                if (hist[i] < 835 || hist[i] > 1165) begin
                    $display("  FAIL: w4 hist[%0d]=%0d outside [835,1165]",
                             i, hist[i]);
                    errors = errors + 1;
                end
            end else if (i < 4) begin
                exp_cnt = 500;
                if (hist[i] < 375 || hist[i] > 625) begin
                    $display("  FAIL: w2 hist[%0d]=%0d outside [375,625]",
                             i, hist[i]);
                    errors = errors + 1;
                end
            end else begin
                exp_cnt = 250;
                if (hist[i] < 158 || hist[i] > 342) begin
                    $display("  FAIL: w1 hist[%0d]=%0d outside [158,342]",
                             i, hist[i]);
                    errors = errors + 1;
                end
            end
            checks = checks + 1;
            $display("    token %0d: %0d (expect ~%0d)", i, hist[i], exp_cnt);
        end
        // Group ordering.
        check((hist[0] + hist[1]) > (hist[2] + hist[3]),
              "weight-4 group beats weight-2 group");
        check((hist[2] + hist[3]) >
              (hist[4] + hist[5] + hist[6] + hist[7]),
              "weight-2 group beats weight-1 group");

        // ---- summary --------------------------------------------------------
        $display("==================================================");
        if (errors == 0)
            $display("CORE TESTS PASSED: %0d checks", checks);
        else
            $display("CORE FAILED: %0d errors out of %0d checks", errors, checks);
        $display("==================================================");
        $finish;
    end

    // Watchdog.
    initial begin
        #500_000_000;
        $display("FAIL: core timeout");
        $finish;
    end

endmodule

`default_nettype wire
