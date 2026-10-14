#include "audio_vu.hpp"
#include <cassert>
#include <iostream>
using namespace qso;
int main() {
    AudioLevels levels;
    Json valid(R"({"rx_audio_available":true,"rx_audio_rms_dbfs":-32.5,"rx_audio_peak_dbfs":-18,"tx_audio_available":true,"tx_audio_rms_dbfs":-100,"tx_audio_peak_dbfs":-100})");
    levels.update(valid, 100);
    assert(levels.reading(false,true,100)->rms==-32.5);
    assert(levels.reading(true,true,100)->rms==-100);
    assert(!levels.reading(false,true,101.01));
    assert(!levels.reading(true,false,100));
    Json absent(R"({"rx_audio_available":false,"rx_audio_rms_dbfs":-1,"tx_audio_available":true,"tx_audio_rms_dbfs":null,"tx_audio_peak_dbfs":-1})");
    levels.update(absent,100); assert(!levels.rx && !levels.tx);
    assert(AudioVUReading::fraction(-100)==0 && AudioVUReading::fraction(-30)==0.5 && AudioVUReading::fraction(3)==1);
    std::cout<<"PASS: Windows VU freshness, unavailable input and dBFS scale\n";
}
