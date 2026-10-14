#pragma once
#include "protocol.hpp"
#include <optional>
#include <cmath>
namespace qso {
struct AudioVUReading {
  double rms, peak;
  static std::optional<AudioVUReading> parse(const Json &object, const std::string &prefix) {
    if (!object.yes((prefix + "_audio_available").c_str())) return {};
    auto rms = cJSON_GetObjectItemCaseSensitive(object.p, (prefix + "_audio_rms_dbfs").c_str());
    auto peak = cJSON_GetObjectItemCaseSensitive(object.p, (prefix + "_audio_peak_dbfs").c_str());
    if (!cJSON_IsNumber(rms) || !cJSON_IsNumber(peak) || !std::isfinite(rms->valuedouble) || !std::isfinite(peak->valuedouble)) return {};
    return AudioVUReading{std::clamp(rms->valuedouble, -100.0, 0.0), std::clamp(peak->valuedouble, -100.0, 0.0)};
  }
  static double fraction(double db) { return std::clamp((db + 60) / 60, 0.0, 1.0); }
};
struct AudioLevels {
  std::optional<AudioVUReading> rx, tx;
  double time = -1e9;
  void update(const Json &object, double now) { rx = AudioVUReading::parse(object, "rx"); tx = AudioVUReading::parse(object, "tx"); time = now; }
  std::optional<AudioVUReading> reading(bool outgoing, bool connected, double now) const {
    if (!connected || now < time || now - time > 1) return {};
    return outgoing ? tx : rx;
  }
};
}
