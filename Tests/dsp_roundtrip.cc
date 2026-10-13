// Exercise the real modem73 PHY without audio devices or RF transmission.
#include "modem.hh"
#include "phy/robust_modem.hh"
#include "phy/mfsk_modem.hh"
#include <memory>
#include <stdexcept>
#include <string>
#include <iostream>

template<typename Decoder>
void verify(const std::string& name, std::vector<float> samples, Decoder& decoder,
            const std::vector<uint8_t>& input) {
    if (samples.empty()) throw std::runtime_error(name + ": encoder returned no audio");
    // A silent lead and tail give the streaming synchronizer its search window.
    samples.insert(samples.begin(), 48000, 0.0f);
    samples.insert(samples.end(), 96000, 0.0f);
    bool matched = false;
    auto callback = [&](const uint8_t* data, size_t length) {
        if (length >= input.size() && std::equal(input.begin(), input.end(), data)) matched = true;
    };
    for (size_t i = 0; i < samples.size(); i += 1024)
        decoder.process(samples.data() + i, std::min(size_t(1024), samples.size() - i), callback);
    if (!matched) throw std::runtime_error(name + ": payload failed clean-audio round trip");
    std::cout << "PASS: " << name << " encode -> 48 kHz audio samples -> decode" << std::endl;
}
int main() {
    try {
        // Native chat AX.25 UI packet, including UTF-8. Encoders accept arbitrary packet bytes.
        std::vector<uint8_t> input = {0xA8,0x8A,0xA6,0xA8,0x64,0x40,0x60,
                                    0xA8,0x8A,0xA6,0xA8,0x62,0x40,0x61,0x03,0xF0};
        std::string text = "73 caf\xC3\xA9 \xF0\x9F\x91\x8B";
        input.insert(input.end(), text.begin(), text.end());
        auto ofdm = std::make_unique<Encoder48k>();
        auto ofdm_rx = std::make_unique<Decoder48k>();
        verify("OFDM QPSK 1/2", ofdm->encode(input.data(), input.size(), 1500,
               ModemConfig::encode_callsign("TEST1"), ModemConfig::encode_mode("QPSK", "1/2", 1)), *ofdm_rx, input);
        auto robust = std::make_unique<RobustEncoder>();
        auto robust_rx = std::make_unique<RobustDecoder>();
        verify("ROBUST RDM-600", robust->encode(input.data(), input.size(), 1500, RobustMode::RDM_600), *robust_rx, input);
        auto mfsk = std::make_unique<MFSKEncoder>();
        auto mfsk_rx = std::make_unique<MFSKDecoder>(MFSKMode::MFSK_16, 1500);
        verify("MFSK-16", mfsk->encode(input.data(), input.size(), 1500, MFSKMode::MFSK_16), *mfsk_rx, input);
    } catch (const std::exception& e) { std::cerr << e.what() << std::endl; return 1; }
}
