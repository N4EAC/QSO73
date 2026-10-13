#pragma once
#include "protocol.hpp"
#include <cmath>
#include <functional>
#include <iomanip>
#include <optional>
#include <regex>
#include <sstream>
namespace qso {
struct PingMessage {
  static constexpr const char *prefix = "~Q73P:";
  std::string kind, id, call, grid;
  std::optional<double> snr;
  void validate() const {
    if (!uuid(id) || (kind != "request" && kind != "reply"))
      throw std::runtime_error("Invalid PING packet.");
    if (kind == "reply") {
      if (!station(call) || qso::call(call) != call ||
          !std::regex_match(
              grid, std::regex("[A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?")) ||
          !snr || !std::isfinite(*snr))
        throw std::runtime_error(
            "PING reply needs callsign, grid and measured SNR.");
    } else if (!call.empty() || !grid.empty() || snr)
      throw std::runtime_error("Invalid PING request fields.");
  }
  std::string encode() const {
    validate();
    Json j(cJSON_CreateObject());
    cJSON_AddNumberToObject(j.p, "v", 1);
    cJSON_AddStringToObject(j.p, "k", kind.c_str());
    cJSON_AddStringToObject(j.p, "id", id.c_str());
    if (kind == "reply") {
      cJSON_AddStringToObject(j.p, "call", call.c_str());
      cJSON_AddStringToObject(j.p, "grid", grid.c_str());
      cJSON_AddNumberToObject(j.p, "snr", *snr);
    }
    auto wire = std::string(prefix) + j.dump();
    if (wire.size() > 200)
      throw std::runtime_error("PING packet too long.");
    return wire;
  }
  static PingMessage decode(const std::string &wire) {
    if (wire.rfind(prefix, 0) || wire.size() > 200)
      throw std::runtime_error("Invalid PING packet.");
    Json j(wire.substr(6));
    if (j.num("v", -1) != 1)
      throw std::runtime_error("Unsupported PING version.");
    PingMessage p{j.str("k"), j.str("id"), j.str("call"), j.str("grid"),
                  std::nullopt};
    auto number = cJSON_GetObjectItemCaseSensitive(j.p, "snr");
    if (cJSON_IsNumber(number))
      p.snr = number->valuedouble;
    p.validate();
    return p;
  }
};
struct PingSession {
  struct Pending {
    std::string source, id;
    double received;
  };
  std::vector<Pending> pending;
  std::set<std::string> seen;
  std::deque<std::string> order;
  std::map<std::string, double> requested, replied;
  std::optional<std::string> receive(const Packet &p, const std::string &own,
                                     bool outgoing, bool enabled, double now) {
    auto event = PingMessage::decode(p.text);
    if (!station(p.source))
      throw std::runtime_error("Invalid PING sender.");
    auto key = p.source + ":" + event.kind + ":" + event.id;
    if (seen.count(key))
      return std::nullopt;
    if (event.kind == "reply") {
      if (event.call != p.source ||
          (!outgoing && (p.destination != own || !requested.count(event.id) ||
                         now - requested[event.id] > 180)))
        return std::nullopt;
    } else {
      if (!outgoing && p.destination != own && p.destination != "QST" &&
          p.destination != "CQ" && p.destination != "ALL")
        return std::nullopt;
      if (outgoing) {
        requested[event.id] = now;
        for (auto it = requested.begin(); it != requested.end();)
          if (now - it->second > 180)
            it = requested.erase(it);
          else
            ++it;
      } else if (enabled && p.source != own && pending.size() < 16 &&
                 (!replied.count(p.source) || now - replied[p.source] >= 30))
        pending.push_back({p.source, event.id, now});
    }
    seen.insert(key);
    order.push_back(key);
    if (order.size() > 512) {
      seen.erase(order.front());
      order.pop_front();
    }
    if (event.kind == "request")
      return "PING request";
    std::ostringstream out;
    out << "PING reply: " << event.call << " " << event.grid << " - SNR "
        << std::fixed << std::setprecision(1) << *event.snr
        << " dB (your request at this station)";
    return out.str();
  }
  std::optional<Packet>
  reply(const std::string &own, const std::string &grid, double now,
        std::function<std::optional<double>(const Pending &)> measurement) {
    pending.erase(std::remove_if(pending.begin(), pending.end(),
                                 [&](const auto &p) {
                                   return now - p.received > 30 ||
                                          (replied.count(p.source) &&
                                           now - replied[p.source] < 30);
                                 }),
                  pending.end());
    for (auto it = pending.begin(); it != pending.end(); ++it) {
      if (now - it->received < 2)
        continue;
      auto signal = measurement(*it);
      if (!signal || !std::isfinite(*signal))
        continue;
      Packet result{own, it->source,
                    PingMessage{"reply", it->id, own, grid, signal}.encode()};
      replied[it->source] = now;
      pending.erase(it);
      return result;
    }
    return std::nullopt;
  }
};
} // namespace qso
