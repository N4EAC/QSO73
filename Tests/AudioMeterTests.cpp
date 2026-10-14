#include "audio_meter.hh"
#include <cassert>
#include <vector>
#include <limits>
#include <iostream>
int main() {
    AudioMeter rx, tx;
    assert(!rx.snapshot().available);
    std::vector<float> samples(4800);
    for (size_t i = 0; i < samples.size(); ++i) samples[i] = 0.5f * std::sin(2 * 3.141592653589793 * 1000 * i / 48000);
    const auto original = samples;
    rx.observe(samples.data(), 2400, 48000);
    assert(!rx.snapshot().available);
    rx.observe(samples.data()+2400, 2400, 48000);
    auto measured = rx.snapshot();
    assert(measured.available && std::abs(measured.rms + 9.0309) < 0.001 && std::abs(measured.peak + 6.0206) < 0.001);
    for (auto &value : samples) value *= 0.25f;
    tx.observe(samples.data(), 4800, 48000);
    assert(std::abs(tx.snapshot().rms + 21.0721) < 0.001);
    assert(std::abs(tx.snapshot().peak + 18.0618) < 0.001);
    assert(!rx.snapshot(AudioMeter::now_ms()+501).available);
    samples.assign(4800, 0); tx.observe(samples.data(), 4800, 48000);
    assert(tx.snapshot().available && tx.snapshot().rms == -100 && tx.snapshot().peak == -100);
    samples.assign(4800, 1.25f); tx.observe(samples.data(),4800,48000);
    assert(tx.snapshot().rms == 0 && tx.snapshot().peak == 0);
    samples.assign(4800, std::numeric_limits<float>::quiet_NaN()); tx.observe(samples.data(),4800,48000);
    assert(tx.snapshot().rms == -100);
    tx.reset(); assert(!tx.snapshot().available);
    samples=original; rx.observe(samples.data(),4800,48000); assert(samples==original);
    std::cout << "PASS: 100 ms PCM RMS/peak, post-gain levels, silence, full scale, invalid samples, stale/reset and unmodified waveform\n";
}
