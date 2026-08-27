// -----------------------------------------------------------------------------
// tb_sampler — statistical testbench for sampler_uart_top
//
// Drives real protocol frames into the DUT's UART pin (at the accelerated
// SIM_BAUD from sim.py), collects the returned token ids, and checks the
// histogram against the distribution the RTL is specified to implement.
//
// This is the test that actually matters. A sampler can compile, route, and
// answer every frame while still being statistically wrong -- a swapped logit
// byte order, an off-by-one in the CDF scan, or a bad exponent constant all
// show up here and nowhere else.
//
// Usage: tb_sampler [samples] [seed]
// Prints machine-readable lines consumed by sim.py::_parse_sim_output.
// -----------------------------------------------------------------------------
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <vector>

#include "Vsampler_uart_top.h"
#include "verilated.h"

namespace {

// Must match sc_softmax_sampler.v exp_const() and protocol.py EXP_CONSTS.
const uint32_t kExpConsts[16] = {
    65280, 65030, 64524, 63524, 61569, 57841, 51035, 39749,
    24109, 8869,  1200,  22,    0,     0,     0,     0,
};

constexpr int kK = 32;              // candidates, matches RTL parameter K
constexpr int kClkPerBit = 4;       // 100 MHz / SIM_BAUD(25 MHz)
constexpr uint8_t kSofHost = 0x5A;
constexpr uint8_t kSofFpga = 0xA5;
constexpr uint8_t kCmdSample = 0x4C;
constexpr uint8_t kRspToken = 0x54;

uint8_t crc8(const std::vector<uint8_t>& data) {
    uint8_t crc = 0;
    for (uint8_t byte : data) {
        crc ^= byte;
        for (int i = 0; i < 8; ++i) {
            crc = (crc & 0x80) ? static_cast<uint8_t>((crc << 1) ^ 0x07)
                               : static_cast<uint8_t>(crc << 1);
        }
    }
    return crc;
}

int16_t toQ88(double nats) {
    double scaled = std::round(nats * 256.0);
    if (scaled > 32767.0) return 32767;
    if (scaled < -32768.0) return -32768;
    return static_cast<int16_t>(scaled);
}

// The probability the AND-reduce fires, i.e. what the hardware really computes.
double hardwareProbability(int32_t deficitQ88) {
    if (deficitQ88 <= 0) return 1.0;
    double p = 1.0;
    for (int j = 0; j < 16; ++j) {
        if (deficitQ88 & (1 << j)) p *= static_cast<double>(kExpConsts[j]) / 65536.0;
    }
    return p;
}

class Harness {
  public:
    explicit Harness(Vsampler_uart_top* dut) : dut_(dut) {}

    void tick() {
        dut_->clk_100mhz = 0;
        dut_->eval();
        dut_->clk_100mhz = 1;
        dut_->eval();
        sampleRxLine();
        ++cycles_;
    }

    void reset() {
        dut_->resetn = 0;
        dut_->uart_rxd = 1;
        for (int i = 0; i < 64; ++i) tick();
        dut_->resetn = 1;
        for (int i = 0; i < 64; ++i) tick();
    }

    // 8N1, LSB first, driven bit-by-bit on the DUT's rx pin.
    void sendByte(uint8_t value) {
        driveBit(0);  // start
        for (int i = 0; i < 8; ++i) driveBit((value >> i) & 1);
        driveBit(1);  // stop
        // Idle gap so the receiver's edge detector re-arms.
        dut_->uart_rxd = 1;
        for (int i = 0; i < kClkPerBit; ++i) tick();
    }

    void sendFrame(uint8_t cmd, const std::vector<uint8_t>& payload) {
        std::vector<uint8_t> body;
        body.push_back(cmd);
        body.push_back(static_cast<uint8_t>(payload.size() & 0xFF));
        body.push_back(static_cast<uint8_t>((payload.size() >> 8) & 0xFF));
        for (uint8_t b : payload) body.push_back(b);
        uint8_t crc = crc8(body);

        sendByte(kSofHost);
        for (uint8_t b : body) sendByte(b);
        sendByte(crc);
    }

    // Run the clock until a complete device frame has been decoded, or give up.
    bool receiveFrame(std::vector<uint8_t>* out, uint64_t maxCycles) {
        rxBytes_.clear();
        uint64_t start = cycles_;
        while (cycles_ - start < maxCycles) {
            tick();
            if (rxBytes_.size() >= 5) {
                size_t want = 5 + (rxBytes_[2] | (rxBytes_[3] << 8));
                if (rxBytes_.size() >= want) {
                    out->assign(rxBytes_.begin(), rxBytes_.begin() + want);
                    return true;
                }
            }
        }
        return false;
    }

    uint64_t cycles() const { return cycles_; }

  private:
    void driveBit(int value) {
        dut_->uart_rxd = value;
        for (int i = 0; i < kClkPerBit; ++i) tick();
    }

    // Mirror-image UART receiver watching the DUT's tx pin.
    void sampleRxLine() {
        int tx = dut_->uart_txd;
        switch (rxState_) {
            case kIdle:
                if (txPrev_ == 1 && tx == 0) {
                    rxState_ = kData;
                    rxTick_ = kClkPerBit + kClkPerBit / 2;  // aim at mid-bit
                    rxBitIdx_ = 0;
                    rxShift_ = 0;
                }
                break;
            case kData:
                if (--rxTick_ == 0) {
                    rxShift_ |= (tx & 1) << rxBitIdx_;
                    rxTick_ = kClkPerBit;
                    if (++rxBitIdx_ == 8) rxState_ = kStop;
                }
                break;
            case kStop:
                if (--rxTick_ == 0) {
                    rxBytes_.push_back(static_cast<uint8_t>(rxShift_));
                    rxState_ = kIdle;
                }
                break;
        }
        txPrev_ = tx;
    }

    enum RxState { kIdle, kData, kStop };

    Vsampler_uart_top* dut_;
    uint64_t cycles_ = 0;
    int txPrev_ = 1;
    RxState rxState_ = kIdle;
    int rxTick_ = 0;
    int rxBitIdx_ = 0;
    unsigned rxShift_ = 0;
    std::vector<uint8_t> rxBytes_;
};

}  // namespace

// Verilator 5 still calls this from verilated.cpp unless the TB uses
// VerilatedContext timing. GNU ld fails the --build link without it.
double sc_time_stamp() { return 0; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    int samples = (argc > 1) ? std::atoi(argv[1]) : 2000;
    if (samples < 1) samples = 1;
    unsigned seed = (argc > 2) ? static_cast<unsigned>(std::atoi(argv[2])) : 1u;
    std::srand(seed);

    auto* dut = new Vsampler_uart_top;
    Harness h(dut);
    h.reset();

    // A deliberately uneven distribution: a clear favourite, a few contenders,
    // and a long tail below the exponent table's resolution. A uniform vector
    // would hide byte-order and CDF bugs.
    std::vector<double> logits(kK, 0.0);
    for (int i = 0; i < kK; ++i) {
        if (i == 3) logits[i] = 2.0;
        else if (i == 7) logits[i] = 1.5;
        else if (i == 11) logits[i] = 1.0;
        else if (i < 16) logits[i] = 0.25 * static_cast<double>(i % 4);
        else logits[i] = -20.0;  // ~0 probability
    }

    std::vector<uint8_t> payload;
    payload.reserve(kK * 2);
    std::vector<int32_t> raw(kK);
    for (int i = 0; i < kK; ++i) {
        raw[i] = toQ88(logits[i]);
        payload.push_back(static_cast<uint8_t>(raw[i] & 0xFF));
        payload.push_back(static_cast<uint8_t>((raw[i] >> 8) & 0xFF));
    }

    int32_t lmax = raw[0];
    for (int i = 1; i < kK; ++i) lmax = std::max(lmax, raw[i]);

    std::vector<double> expected(kK, 0.0);
    double total = 0.0;
    for (int i = 0; i < kK; ++i) {
        expected[i] = hardwareProbability(lmax - raw[i]);
        total += expected[i];
    }
    for (int i = 0; i < kK; ++i) expected[i] /= total;

    std::map<int, int> counts;
    int collected = 0;
    int protocolErrors = 0;

    // A sample is 2^SC_LOG2 stochastic cycles plus the entropy wait for the
    // uniform draw, so the per-frame budget has to be generous.
    const uint64_t kFrameBudget = 4000000;

    for (int s = 0; s < samples; ++s) {
        h.sendFrame(kCmdSample, payload);
        std::vector<uint8_t> frame;
        if (!h.receiveFrame(&frame, kFrameBudget)) {
            std::printf("ERROR no response to sample %d after %llu cycles\n", s,
                        static_cast<unsigned long long>(kFrameBudget));
            ++protocolErrors;
            break;
        }
        if (frame[0] != kSofFpga || frame[1] != kRspToken || frame.size() != 16) {
            std::printf("ERROR malformed frame: sof=%02x kind=%02x len=%zu\n", frame[0],
                        frame[1], frame.size());
            ++protocolErrors;
            break;
        }
        std::vector<uint8_t> body(frame.begin() + 1, frame.end() - 1);
        if (crc8(body) != frame.back()) {
            std::printf("ERROR CRC mismatch on sample %d\n", s);
            ++protocolErrors;
            break;
        }
        int token = frame[4] | (frame[5] << 8);
        if (token < 0 || token >= kK) {
            std::printf("ERROR token %d out of range\n", token);
            ++protocolErrors;
            break;
        }
        counts[token]++;
        ++collected;
    }

    // Compare against expectation. Pearson chi-square over the bins the model
    // says are reachable, plus the worst single-bin deviation.
    double maxDev = 0.0;
    double chi2 = 0.0;
    for (int i = 0; i < kK; ++i) {
        double observedFrac = collected ? static_cast<double>(counts[i]) / collected : 0.0;
        maxDev = std::max(maxDev, std::fabs(observedFrac - expected[i]));
        double e = expected[i] * collected;
        if (e >= 5.0) {  // chi-square is only meaningful for populated bins
            double d = counts[i] - e;
            chi2 += d * d / e;
        }
    }

    for (const auto& kv : counts) std::printf("TOKEN_COUNT %d %d\n", kv.first, kv.second);
    for (int i = 0; i < kK; ++i) {
        if (expected[i] > 1e-9) std::printf("EXPECTED %d %.9f\n", i, expected[i]);
    }
    std::printf("SAMPLES %d\n", collected);
    std::printf("MAXDEV %.6f\n", maxDev);
    std::printf("CHI2 %.4f\n", chi2);
    std::printf("CYCLES %llu\n", static_cast<unsigned long long>(h.cycles()));

    // Sampling error scales as 1/sqrt(n); this bound is loose enough not to
    // flake at n=2000 but tight enough to catch a wrong distribution.
    double tolerance = 4.0 / std::sqrt(static_cast<double>(collected ? collected : 1));
    bool pass = (protocolErrors == 0) && (collected == samples) && (maxDev <= tolerance);
    std::printf("TOLERANCE %.6f\n", tolerance);
    std::printf("RESULT %s\n", pass ? "PASS" : "FAIL");

    dut->final();
    delete dut;
    return pass ? 0 : 1;
}
