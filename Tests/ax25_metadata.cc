#include "rx_frame_info.hh"
#include <iostream>
int main() {
    std::vector<uint8_t> packet;
    for (char c : std::string("QST   ")) packet.push_back(c << 1);
    packet.push_back(0x60);
    for (char c : std::string("TEST2 ")) packet.push_back(c << 1);
    packet.push_back(0x61 | (15 << 1));
    packet.push_back(3); packet.push_back(0xF0);
    if (ax25_ui_source(packet) != "TEST2-15") return 1;
    packet[13] = 0x61;
    if (ax25_ui_source(packet) != "TEST2") return 1;
    packet[14] = 0;
    if (!ax25_ui_source(packet).empty()) return 1;
    if (!ax25_ui_source({1,2,3}).empty()) return 1;
    std::cout << "PASS: AX.25 RX metadata source/SSID and non-chat rejection" << std::endl;
}
