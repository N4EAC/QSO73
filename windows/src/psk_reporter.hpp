#pragma once
#include "protocol.hpp"
#include <cmath>
#include <optional>
#include <regex>
namespace qso {
struct PSKReception {
  std::string call;
  uint64_t frequency;
  int8_t snr;
  uint32_t time;
};
struct PSKReportQueue {
  std::vector<PSKReception> reports;
  std::map<std::string, double> seen;
  double due = 0;
  static std::string reportCall(const std::string &text) {
    auto c = qso::call(text);
    return c.substr(0, c.find('-'));
  }
  static bool grid(const std::string &s) {
    return std::regex_match(
        s, std::regex("[A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?"));
  }
  static std::optional<uint64_t> rfFrequency(double dial,
                                             const std::string &mode) {
    if (!std::isfinite(dial) || dial <= 0)
      return {};
    double offset;
    if (mode == "USB" || mode == "PKTUSB" || mode == "DATAUSB")
      offset = 1500;
    else if (mode == "LSB" || mode == "PKTLSB" || mode == "DATALSB")
      offset = -1500;
    else if (mode == "FM" || mode == "PKTFM" || mode == "DATAFM")
      offset = 0;
    else
      return {};
    auto rf = std::round(dial + offset);
    if (rf <= 0 || rf >= 1099511627776.0)
      return {};
    return uint64_t(rf);
  }
  void clear(double now, double delay = 315) {
    reports.clear();
    seen.clear();
    due = now + delay;
  }
  bool add(const std::string &sender, const std::string &own,
           uint64_t frequency, double snr, double received, double since,
           double now) {
    auto who = reportCall(sender);
    if (!station(qso::call(sender)) || who == reportCall(own) || !frequency ||
        frequency >= 1099511627776ULL || !std::isfinite(snr) ||
        !std::isfinite(received) || !std::isfinite(now) || received < since ||
        received < 0 || received > UINT32_MAX || now - received < -5 ||
        now - received > 30 || reports.size() >= 56)
      return false;
    for (auto i = seen.begin(); i != seen.end();)
      if (now - i->second >= 300)
        i = seen.erase(i);
      else
        ++i;
    auto key = who + ":" + std::to_string(frequency);
    if (seen.count(key))
      return false;
    if (seen.size() >= 512)
      seen.erase(std::min_element(
          seen.begin(), seen.end(),
          [](const auto &a, const auto &b) { return a.second < b.second; }));
    seen[key] = now;
    reports.push_back(
        {who, frequency,
         int8_t(std::max(-128.0, std::min(127.0, std::round(snr)))),
         uint32_t(received)});
    return true;
  }
  bool full() const { return reports.size() >= 56; }
  void expire(double now) {
    reports.erase(
        std::remove_if(reports.begin(), reports.end(),
                       [&](const auto &r) { return now - r.time > 900; }),
        reports.end());
  }
  static Bytes encode(const std::string &receiver, const std::string &locator,
                      const std::string &software,
                      const std::vector<PSKReception> &reports,
                      uint32_t sequence, uint32_t domain, uint32_t time) {
    if (!station(receiver) || !grid(locator) || reports.empty())
      throw std::runtime_error(
          "PSK Reporter needs a valid callsign, grid and reception.");
    auto number = [](uint64_t n, int count) {
      Bytes b;
      for (int i = count - 1; i >= 0; --i)
        b.push_back(uint8_t(n >> (i * 8)));
      return b;
    };
    auto append = [](Bytes &b, const Bytes &v) {
      b.insert(b.end(), v.begin(), v.end());
    };
    auto variable = [](const std::string &s) {
      if (s.size() > 254)
        throw std::runtime_error("PSK Reporter field too long.");
      Bytes b{uint8_t(s.size())};
      b.insert(b.end(), s.begin(), s.end());
      return b;
    };
    auto set = [&](uint16_t id, Bytes b) {
      int pad = (4 - (b.size() + 4) % 4) % 4;
      Bytes out = number(id, 2);
      append(out, number(b.size() + 4 + pad, 2));
      append(out, b);
      out.insert(out.end(), pad, 0);
      return out;
    };
    auto field = [&](uint16_t id, uint16_t length) {
      Bytes b = number(id | 0x8000, 2);
      append(b, number(length, 2));
      append(b, number(30351, 4));
      return b;
    };
    Bytes rt = number(0x9992, 2);
    append(rt, number(3, 2));
    append(rt, number(1, 2));
    for (auto id : {2, 4, 8})
      append(rt, field(id, 65535));
    Bytes st = number(0x9995, 2);
    append(st, number(6, 2));
    append(st, field(1, 65535));
    append(st, field(5, 5));
    append(st, field(6, 1));
    append(st, field(10, 65535));
    append(st, field(11, 1));
    append(st, number(150, 2));
    append(st, number(4, 2));
    Bytes rd = variable(reportCall(receiver));
    append(rd, variable(locator));
    append(rd, variable(software));
    Bytes sd;
    for (const auto &r : reports) {
      if (!station(r.call) || !r.frequency || r.frequency >= 1099511627776ULL)
        throw std::runtime_error("Invalid PSK Reporter reception.");
      append(sd, variable(r.call));
      append(sd, number(r.frequency, 5));
      sd.push_back(uint8_t(r.snr));
      append(sd, variable("PKT"));
      sd.push_back(1);
      append(sd, number(r.time, 4));
    }
    Bytes body = set(3, rt);
    append(body, set(2, st));
    append(body, set(0x9992, rd));
    append(body, set(0x9995, sd));
    if (body.size() + 16 > 1400)
      throw std::runtime_error("PSK Reporter datagram exceeds 1400 bytes.");
    Bytes out = number(10, 2);
    append(out, number(body.size() + 16, 2));
    append(out, number(time, 4));
    append(out, number(sequence, 4));
    append(out, number(domain, 4));
    append(out, body);
    return out;
  }
};
} // namespace qso
