#pragma once
#include <atomic>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdint>

// One audio callback writer; control-thread readers. No allocation or locks.
struct AudioMeterSnapshot { bool available; float rms, peak; };
class AudioMeter {
    double energy_ = 0;
    float peak_ = 0;
    uint64_t frames_ = 0;
    std::atomic<float> rms_db_{-100}, peak_db_{-100};
    std::atomic<int64_t> measured_{0};
    static float db(double amplitude) {
        return float(std::clamp(20.0 * std::log10(std::max(1e-5, amplitude)), -100.0, 0.0));
    }
public:
    static int64_t now_ms() {
        return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
    }
    void reset() { energy_ = 0; peak_ = 0; frames_ = 0; measured_.store(0); }
    void observe(const float* samples, uint32_t frames, unsigned rate, float gain = 1) {
        if (!samples || !rate) return;
        for (uint32_t i = 0; i < frames; ++i) {
            double value = std::isfinite(samples[i]) ? std::clamp(samples[i] * gain, -1.0f, 1.0f) : 0;
            energy_ += value * value;
            peak_ = std::max(peak_, float(std::abs(value)));
        }
        frames_ += frames;
        if (frames_ >= std::max(1u, rate / 10)) {
            rms_db_.store(db(std::sqrt(energy_ / frames_)), std::memory_order_relaxed);
            peak_db_.store(db(peak_), std::memory_order_relaxed);
            measured_.store(now_ms(), std::memory_order_release);
            energy_ = 0; peak_ = 0; frames_ = 0;
        }
    }
    AudioMeterSnapshot snapshot(int64_t now = now_ms()) const {
        auto time = measured_.load(std::memory_order_acquire);
        return {time != 0 && now >= time && now - time <= 500,
                rms_db_.load(std::memory_order_relaxed), peak_db_.load(std::memory_order_relaxed)};
    }
};
static_assert(std::atomic<float>::is_always_lock_free, "Audio telemetry requires lock-free atomics");
