#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct RxFrameInfo {
    uint64_t seq = 0;
    double time = 0.0;
    int64_t steady_ms = 0;
    float snr = 0.0f;
    float ber_pct = -1.0f;
    float level_db = 0.0f;
    int size = 0;
    bool reassembled = false;
    std::string modem;
    std::string mode;
    int oper_mode = -1;
    std::string modulation;
    std::string code_rate;
    std::string frame_size;
    int robust_mode = -1;
    int mfsk_mode = -1;
    std::string callsign;
    std::string callsign_source = "none";
};

// QSO73's two-address AX.25 UI frames carry the source callsign and SSID.
inline std::string ax25_ui_source(const std::vector<uint8_t>& payload) {
    if (payload.size() < 16 || (payload[6] & 1) || !(payload[13] & 1) || payload[14] != 3 || payload[15] != 0xF0)
        return {};
    std::string call;
    bool padding = false;
    for (int i = 7; i < 13; ++i) {
        if (payload[i] & 1) return {};
        char c = payload[i] >> 1;
        if (c == ' ') { padding = true; continue; }
        if (padding || !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) return {};
        call += c;
    }
    if (call.empty()) return {};
    int ssid = (payload[13] >> 1) & 15;
    if (ssid) call += "-" + std::to_string(ssid);
    return call;
}
