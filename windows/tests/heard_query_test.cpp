#include "chat_presentation.hpp"
#include "heard_query.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace qso;
int main(int argc, char **argv) {
  const std::string id = "01234567-89AB-CDEF-0123-456789ABCDEF";
  double now = 1700001000;
  HeardBook b;
  b.begin("N4EAC", now - 3600);
  b.observe("K1ABC-7", -8.4, now - 120, now);
  b.observe("K1ABC", -9, now - 130, now);
  b.observe("W0XYZ", {}, now - 60, now);
  b.observe("N4EAC", 1, now, now);
  b.observe("STALE1", 0, now - 3601, now);
  auto list = b.select({}, "W0XYZ", now);
  assert(list.size() == 1 && list[0].call == "K1ABC-7" &&
         list[0].signal == -84 && list[0].age == 120);
  assert(b.select("K1ABC-0", "TEST1", now)[0].call == "K1ABC");
  assert(b.select("K1ABC", "TEST1", now)[0].call == "K1ABC-7");
  assert(b.select("N9ZZZ", "TEST1", now).empty());
  b.observe("W0XYZ", {}, now - 59, now, true);
  b.observe("W0XYZ", -3.2, now - 60, now);
  assert(b.select("W0XYZ", "TEST1", now)[0].signal == -32);
  b.observe("N4EAC-7", 1, now, now);
  assert(b.select("N4EAC-7", "TEST1", now)[0].call == "N4EAC-7");
  auto request = HeardMessage{"request", id, {}, {}}.encode();
  HeardSession receiver, requester;
  assert(requester.receive({"TEST1", "QST", request}, "TEST1", true, false, now,
                           2));
  assert(receiver.receive({"TEST1", "QST", request}, "N4EAC", false, true, now,
                          12));
  assert(!receiver.receive({"TEST1", "QST", request}, "N4EAC", false, true, now,
                           12));
  assert(!receiver.reply("N4EAC", now + 11, b));
  auto reply = *receiver.reply("N4EAC", now + 12, b);
  assert(requester.receive(reply, "TEST1", false, false, now + 12, 2));
  reply.source = "W1AAA";
  assert(requester.receive(reply, "TEST1", false, false, now + 13, 2));
  HeardSession stranger;
  assert(!stranger.receive(reply, "TEST1", false, true, now, 2));
  auto second = HeardMessage{
      "request",
      "11234567-89AB-CDEF-0123-456789ABCDEF",
      "K1ABC-0",
      {}}.encode();
  receiver.receive({"TEST1", "QST", second}, "N4EAC", false, true, now + 20, 2);
  assert(receiver.pending.empty());
  receiver.receive({"TEST2", "QST", second}, "N4EAC", false, true, now, 2);
  receiver.pending.clear();
  assert(receiver.pending.empty());
  receiver.receive({"TEST3", "QST", second}, "N4EAC", false, true, now, 2);
  assert(!receiver.reply("N4EAC", now + 121, b));
  auto negative =
      HeardMessage{"reply", id, "N9ZZZ", std::vector<HeardItem>{}}.encode();
  if (argc > 1) {
    std::ofstream file(argv[1]);
    file << request << "\n"
         << second << "\n"
         << reply.text << "\n"
         << negative << "\n";
  }
  if (argc > 2) {
    std::ifstream file(argv[2]);
    std::string line;
    while (std::getline(file, line))
      HeardMessage::decode(line);
  }
  Entry blue{"radio", "TEST1", "Hello", true};
  blue.utc = 0;
  assert(chatTone(blue) == ChatTone::own &&
         chatLine(blue).find("00:00:00 UTC") != std::string::npos &&
         chatLine(blue).find("You ->") == std::string::npos);
  Entry orange{"radio", "TEST1", "HEARD query", true, true};
  assert(chatTone(orange) == ChatTone::automatic);
  Entry green{"radio", "TEST2", "Hello", false};
  assert(chatTone(green) == ChatTone::received);
  auto luminance = [](ChatRGB rgb) {
    auto linear = [](int channel) {
      double c = channel / 255.0;
      return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) +
           0.0722 * linear(rgb.blue);
  };
  for (auto tone : {ChatTone::own, ChatTone::automatic, ChatTone::received})
    assert(1.05 / (luminance(chatRGB(tone)) + 0.05) >= 4.5);
  assert(beaconCountdown(false, false, true, 0, 0) == "Beacon off");
  assert(beaconCountdown(true, false, false, 300, 0) == "Beacon paused");
  assert(beaconCountdown(true, false, true, 300, 1) == "Beacon 04:59");
  assert(beaconCountdown(true, false, true, 300, 301) == "Beacon waiting idle");
  assert(beaconCountdown(false, true, true, 0, 0) == "Beacon waiting idle");
  std::cout << "PASS: Windows Heard policies/interoperability, UTC message "
               "categories and beacon countdown states\n";
}
