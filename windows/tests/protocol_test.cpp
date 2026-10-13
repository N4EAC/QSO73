#include "protocol.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace qso;
const std::string ID = "01234567-89ab-4cde-8123-456789abcdef";
std::string hex(const Bytes &b) {
  std::string s;
  for (auto c : b) {
    s += "0123456789abcdef"[c >> 4];
    s += "0123456789abcdef"[c & 15];
  }
  return s;
}
Bytes unhex(std::string s) {
  Bytes r;
  for (size_t i = 0; i < s.size(); i += 2)
    r.push_back(uint8_t(std::stoi(s.substr(i, 2), nullptr, 16)));
  return r;
}
template <class F> void reject(F f) {
  bool bad = false;
  try {
    f();
  } catch (...) {
    bad = true;
  }
  assert(bad);
}
int main(int argc, char **argv) {
  if (argc == 3 && std::string(argv[1]) == "verify") {
    std::ifstream f(argv[2]);
    std::string line;
    int count = 0;
    while (std::getline(f, line)) {
      auto packet = Packet::decode(unhex(line));
      assert(packet.source == "K1ABC-7");
      auto e = Envelope::decode(packet.text);
      assert(e.id == ID);
      assert(e.r == "#hfchat" || e.r == "N4EAC");
      count++;
    }
    assert(count == 6);
    std::cout
        << "PASS: Windows protocol decodes six Swift/Mac event fixtures\n";
    return 0;
  }
  reject([] { Json bad("{\"v\":1}junk"); });
  reject([] {
    Envelope::decode("~Q73:{\"v\":1,\"k\":\"join\",\"r\":\"#hf\",\"id\":\"" +
                     ID + "\"}");
  });
  assert(call(" k1abc-0 ") == "K1ABC");
  assert(station("N4EAC-15"));
  assert(!address("N4EAC-16"));
  assert(channel("#HFChat") == "#hfchat");
  reject([] { channel("#bad room"); });
  reject([] { Envelope{"msg", "K1ABC", "x", "bad"}.encode(); });
  reject(
      [] { Envelope{"msg", "#hfchat", std::string(200, 'x'), ID}.encode(); });
  reject([] { Envelope{"join", "#hfchat", "not empty", ID}.encode(); });
  reject([] { Envelope{"msg", "#hfchat", "bad\nline", ID}.encode(); });
  reject([] { Envelope{"msg", "#hfchat", std::string("\xff"), ID}.encode(); });
  Packet p{"N4EAC-15", "QST",
           Envelope{"msg", "#hfchat", "Hello caf\xc3\xa9", ID}.encode()};
  auto payload = p.encode();
  auto wire = kiss(payload);
  Framer fr;
  std::vector<Bytes> result;
  for (auto b : wire) {
    auto frames = fr.feed({b});
    result.insert(result.end(), frames.begin(), frames.end());
  }
  assert(result.size() == 1 && result[0] == payload);
  auto decoded = Packet::decode(result[0]);
  assert(decoded.source == p.source && decoded.text == p.text);
  Framer escaped;
  auto frames = escaped.feed(kiss({0xc0, 0xdb, 0, 0xff}));
  assert(frames.size() == 1 && frames[0] == Bytes({0xc0, 0xdb, 0, 0xff}));
  assert(escaped.feed({0xc0, 0, 0xdb, 0x99, 0xc0}).empty());
  Rooms a, b, observer;
  a.joined.insert("#hfchat");
  b.joined.insert("#hfchat");
  assert(b.route(p, "K1ABC", false, 100));
  assert(!b.route(p, "K1ABC", false, 100));
  assert(b.entries[0].text == "Hello caf\xc3\xa9");
  assert(b.unread["#hfchat"] == 1);
  assert(!observer.route(p, "W1AW", false, 100));
  assert(observer.discovered.count("#hfchat"));
  assert(b.hasParticipant("#hfchat", 700));
  assert(!b.hasParticipant("#hfchat", 701));
  assert(b.users("#hfchat", "K1ABC", 701) == std::vector<std::string>{"K1ABC"});
  auto direct =
      Packet{"N4EAC", "K1ABC", Envelope{"msg", "K1ABC", "direct", ID}.encode()};
  assert(b.route(direct, "K1ABC", false, 200));
  assert(b.entries.back().room == "N4EAC");
  assert(!observer.route(direct, "W1AW", false, 200));
  assert(a.route(direct, "N4EAC", true, 200));
  assert(a.entries.back().room == "K1ABC");
  auto topic = Packet{"N4EAC", "QST",
                      Envelope{"topic", "#hfchat", "40m net",
                               "01234567-89ab-4cde-8123-456789abcdee"}
                          .encode()};
  assert(b.route(topic, "K1ABC", false, 200));
  assert(b.topics["#hfchat"] == "40m net");
  auto wrong =
      Packet{"N4EAC", "K1ABC", Envelope{"topic", "#bad", "oops", ID}.encode()};
  reject([&] { b.route(wrong, "K1ABC", false, 200); });
  std::ofstream f(argc > 1 ? argv[1] : "windows-fixtures.hex");
  for (auto k : {"msg", "join", "leave", "topic", "announce"}) {
    auto t = std::string(k) == "join" || std::string(k) == "leave"
                 ? ""
                 : "Hello caf\xc3\xa9";
    f << hex(Packet{"N4EAC-15", "QST", Envelope{k, "#hfchat", t, ID}.encode()}
                 .encode())
      << "\n";
  }
  f << hex(Packet{"N4EAC-15", "K1ABC-7",
                  Envelope{"msg", "K1ABC-7", "private", ID}.encode()}
               .encode())
    << "\n";
  std::cout << "PASS: packet/KISS bounds, escapes, UTF-8, callsigns, channels, "
               "topics, direct routing, deduplication, discovery and "
               "heard-user expiry\n";
}
