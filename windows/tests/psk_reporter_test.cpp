#include "psk_reporter.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace qso;
int main(int argc, char **argv) {
  assert(argc == 2);
  assert(PSKReportQueue::rfFrequency(7105000, "PKTUSB") == 7106500);
  assert(PSKReportQueue::rfFrequency(7105000, "LSB") == 7103500);
  assert(PSKReportQueue::rfFrequency(145500000, "FM") == 145500000);
  assert(!PSKReportQueue::rfFrequency(NAN, "USB") &&
         !PSKReportQueue::rfFrequency(7105000, "CW"));
  assert(PSKReportQueue::grid("FM18FW") && !PSKReportQueue::grid("ZZ99"));
  double now = 1700000010, since = 1700000000;
  PSKReportQueue q;
  q.clear(now, 315);
  assert(!q.add("N4EAC", "N4EAC-7", 7106500, -12.5, now, since, now));
  assert(!q.add("NOCALL", "N4EAC", 7106500, -12.5, now, since, now));
  assert(!q.add("K1ABC", "N4EAC", 7106500, NAN, now, since, now));
  assert(!q.add("K1ABC", "N4EAC", 7106500, 0, NAN, since, now));
  assert(!q.add("K1ABC", "N4EAC", 7106500, 0, since - 1, since, now));
  assert(q.add("K1ABC-2", "N4EAC", 7106500, -12.5, now, since, now));
  assert(!q.add("K1ABC-3", "N4EAC", 7106500, -12.5, now, since, now));
  assert(q.add("K1ABC", "N4EAC", 5400000000, -12.5, now, since, now));
  assert(q.reports[0].call == "K1ABC" && q.reports[0].snr == -13 &&
         q.due == now + 315);
  auto bytes = PSKReportQueue::encode("N4EAC-7", "FM18FW", "QSO73 test",
                                      q.reports, 9, 42, 1700000020);
  std::ofstream f(argv[1], std::ios::binary);
  f.write((char *)bytes.data(), bytes.size());
  f.close();
  q.reports.clear();
  assert(!q.add("K1ABC", "N4EAC", 7106500, 0, now + 100, since, now + 100));
  now += 301;
  assert(q.add("K1ABC", "N4EAC", 7106500, 0, now, since, now));
  for (int i = 0; i < 56; ++i)
    q.add("K" + std::to_string(i) + "AA", "N4EAC", 7106500, 0, now, since, now);
  assert(q.full() && q.reports.size() == 56);
  q.expire(now + 901);
  assert(q.reports.empty());
  std::vector<PSKReception> maximum(56, {"AA0AAA", 7106500, -20, 1700000010});
  auto maxBytes = PSKReportQueue::encode("N4EAC-7", "FM18FW00",
                                         "QSO73 0.4.10 / modem73 2.4.2",
                                         maximum, 0, 42, 1700000020);
  assert(maxBytes.size() <= 1400);
  std::cout << "PASS: Windows PSK encoding, freshness, dedup, bounds, SSIDs "
               "and frequency offsets\n";
}
