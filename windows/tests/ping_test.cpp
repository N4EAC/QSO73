#include "dashboard.hpp"
#include "ping.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace qso;
int main(int argc, char **argv) {
  const std::string id = "01234567-89ab-4cde-8123-456789abcdef";
  if (argc > 2 && std::string(argv[1]) == "verify") {
    std::ifstream file(argv[2]);
    std::string line;
    int n = 0;
    while (std::getline(file, line)) {
      auto p = PingMessage::decode(line);
      assert(p.id == id);
      n++;
    }
    assert(n == 2);
    std::cout << "PASS: Windows decodes Swift PING request and reply\n";
    return 0;
  }
  Packet request{"N4EAC", "K1ABC",
                 PingMessage{"request", id, "", "", std::nullopt}.encode()};
  PingSession a, b, disabled;
  a.receive(request, "N4EAC", true, false, 100);
  disabled.receive(request, "K1ABC", false, false, 100);
  assert(disabled.pending.empty());
  b.receive(request, "K1ABC", false, true, 100);
  assert(!b.receive(request, "K1ABC", false, true, 100));
  assert(
      !b.reply("K1ABC", "FN31", 102, [](const auto &) -> std::optional<double> {
        return std::nullopt;
      }));
  auto reply =
      b.reply("K1ABC", "FN31", 103,
              [](const auto &) -> std::optional<double> { return -14.3; });
  assert(reply && reply->destination == "N4EAC");
  assert(a.receive(*reply, "N4EAC", false, true, 104));
  assert(a.pending.empty());
  assert(!a.receive(*reply, "N4EAC", false, true, 105));
  auto other = request;
  other.text = PingMessage{"request", "01234567-89ab-4cde-8123-456789abcdee",
                           "", "", std::nullopt}
                   .encode();
  b.receive(other, "K1ABC", false, true, 106);
  assert(b.pending.empty());
  auto page = dashboard(
      "{\"channel_state\":\"idle\",\"audio_connected\":true,\"rx_audio_level_"
      "db\":-42.3,\"rx_frame_count\":12,\"tx_frame_count\":7,\"sync_count\":13,"
      "\"rx_error_count\":1,\"occupancy_pct\":14}",
      "{\"modulation\":\"RDM-600S\",\"csma_enabled\":true,\"slot_time_ms\":500,"
      "\"carrier_threshold_db\":-26}",
      "{}", "N4EAC", "7.105000 MHz", {"idle", "rx", "tx"}, {0, 10, 14});
  assert(page.find("TX 7") != page.npos &&
         page.find("7.105000 MHz") != page.npos &&
         page.find("-42.3 dBFS") != page.npos);
  assert(std::count(page.begin(), page.end(), '\n') == 21);
  auto missing = dashboard("{}", "{}", "{}", "N4EAC", "", {}, {});
  assert(missing.find("Carrier   --") != missing.npos);
  if (argc > 1) {
    std::ofstream file(argv[1]);
    file << request.text << "\n" << reply->text << "\n";
  }
  std::ofstream("windows/build/dashboard-preview.txt") << page;
  std::cout << "PASS: Windows PING opt-in, measured reply, deduplication, no "
               "loops and rate limit\nPASS: 21-row modem dashboard, real "
               "values and missing-data markers\n";
}
