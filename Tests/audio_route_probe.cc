// Opens playback with silence only. Never keys PTT, writes a tone or opens capture.
#include "miniaudio_audio.hh"
#include <iostream>
int main(int argc, char** argv) {
    MiniAudio unavailable("default", "QSO73-NONEXISTENT-DEVICE", 48000);
    if (unavailable.open_playback()) { std::cerr << "Unexpected default fallback"; return 1; }
    std::cout << "PASS: unavailable output refuses default-device fallback" << std::endl;
    std::vector<float> input(48000, 0.1f), converted(44100), restored(48000);
    auto n = ma_convert_frames(converted.data(), 44100, ma_format_f32, 1, 44100,
                              input.data(), 48000, ma_format_f32, 1, 48000);
    auto m = ma_convert_frames(restored.data(), 48000, ma_format_f32, 1, 48000,
                              converted.data(), n, ma_format_f32, 1, 44100);
    if (n < 44000 || m < 47900) { std::cerr << "Sample conversion failed"; return 1; }
    std::cout << "PASS: 48 kHz -> 44.1 kHz -> 48 kHz sample conversion" << std::endl;
    if (argc > 1) {
        MiniAudio audio("default", argv[1], 48000);
        if (!audio.open_playback()) return 1;
        audio.close_playback();
        std::cout << "PASS: selected CoreAudio output UID verified (silence only)" << std::endl;
    }
}
