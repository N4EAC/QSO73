#pragma once
#include "protocol.hpp"
#include <cmath>
#include <iomanip>
#include <optional>
namespace qso {
struct HeardItem {
  std::string call;
  int age;
  std::optional<int> signal;
};
struct HeardMessage {
  static constexpr const char *prefix = "~Q73H:";
  std::string kind, id;
  std::optional<std::string> query;
  std::optional<std::vector<HeardItem>> items;
  static std::string cleanQuery(std::string text) {
    text = qso::trim(text);
    for (auto &c : text)
      c = char(std::toupper((unsigned char)c));
    return text;
  }
  static std::string canonical(const std::string &text) {
    auto c = qso::call(text);
    if (c.size() > 2 && c.substr(c.size() - 2) == "-0")
      c.resize(c.size() - 2);
    return c;
  }
  static std::string base(const std::string &text) {
    auto c = canonical(text);
    return c.substr(0, c.find('-'));
  }
  static bool matches(const std::string &c, const std::string &q) {
    return q.find('-') != q.npos ? canonical(c) == canonical(q)
                                 : base(c) == base(q);
  }
  void validate() const {
    if (!uuid(id) || (kind != "request" && kind != "reply"))
      throw std::runtime_error("Invalid Heard query.");
    if (query && (!station(*query) || cleanQuery(*query) != *query))
      throw std::runtime_error(
          "Enter a valid callsign, optionally with an SSID.");
    if (kind == "request") {
      if (items)
        throw std::runtime_error("Invalid Heard request fields.");
    } else {
      if (!items || items->size() > (query ? 1 : 3))
        throw std::runtime_error("Invalid Heard response.");
      std::set<std::string> seen;
      for (auto &i : *items)
        if (!station(i.call) || canonical(i.call) != i.call || i.age < 0 ||
            i.age > 3600 ||
            (i.signal && (*i.signal < -2000 || *i.signal > 2000)) ||
            (query && !matches(i.call, *query)) || !seen.insert(i.call).second)
          throw std::runtime_error("Invalid Heard item.");
    }
  }
  std::string encode() const {
    validate();
    Json j(cJSON_CreateObject());
    cJSON_AddNumberToObject(j.p, "v", 1);
    cJSON_AddNumberToObject(j.p, "w", 60);
    cJSON_AddStringToObject(j.p, "k", kind.c_str());
    cJSON_AddStringToObject(j.p, "id", id.c_str());
    if (query)
      cJSON_AddStringToObject(j.p, "q", query->c_str());
    if (items) {
      auto a = cJSON_AddArrayToObject(j.p, "h");
      for (auto &i : *items) {
        auto r = cJSON_CreateArray();
        cJSON_AddItemToArray(r, cJSON_CreateString(i.call.c_str()));
        cJSON_AddItemToArray(r, cJSON_CreateNumber(i.age));
        cJSON_AddItemToArray(r, i.signal ? cJSON_CreateNumber(*i.signal)
                                         : cJSON_CreateNull());
        cJSON_AddItemToArray(a, r);
      }
    }
    auto wire = std::string(prefix) + j.dump();
    if (wire.size() > 200)
      throw std::runtime_error("Heard packet exceeds 200 bytes.");
    return wire;
  }
  static HeardMessage decode(const std::string &wire) {
    if (wire.rfind(prefix, 0) || wire.size() > 200)
      throw std::runtime_error("Invalid Heard packet.");
    Json j(wire.substr(6));
    if (j.num("v", -1) != 1 || j.num("w", -1) != 60)
      throw std::runtime_error("Unsupported Heard version/window.");
    HeardMessage m{j.str("k"), j.str("id"), {}, {}};
    auto q = cJSON_GetObjectItemCaseSensitive(j.p, "q");
    if (q && !cJSON_IsNull(q)) {
      if (!cJSON_IsString(q))
        throw std::runtime_error("Invalid Heard query callsign.");
      m.query = q->valuestring;
    }
    auto h = cJSON_GetObjectItemCaseSensitive(j.p, "h");
    if (h && !cJSON_IsNull(h)) {
      if (!cJSON_IsArray(h))
        throw std::runtime_error("Invalid Heard list.");
      m.items = std::vector<HeardItem>{};
      cJSON *r;
      cJSON_ArrayForEach(r, h) {
        if (!cJSON_IsArray(r) || cJSON_GetArraySize(r) != 3)
          throw std::runtime_error("Invalid Heard item.");
        auto c = cJSON_GetArrayItem(r, 0), a = cJSON_GetArrayItem(r, 1),
             s = cJSON_GetArrayItem(r, 2);
        if (!cJSON_IsString(c) || !cJSON_IsNumber(a) ||
            !std::isfinite(a->valuedouble) || a->valuedouble < 0 ||
            a->valuedouble > 3600 ||
            std::floor(a->valuedouble) != a->valuedouble ||
            (!cJSON_IsNull(s) &&
             (!cJSON_IsNumber(s) || !std::isfinite(s->valuedouble) ||
              s->valuedouble < -2000 || s->valuedouble > 2000 ||
              std::floor(s->valuedouble) != s->valuedouble)))
          throw std::runtime_error("Invalid Heard item fields.");
        m.items->push_back({c->valuestring, int(a->valuedouble),
                            cJSON_IsNull(s)
                                ? std::nullopt
                                : std::optional<int>(int(s->valuedouble))});
      }
    }
    m.validate();
    return m;
  }
  std::string readable() const {
    if (kind == "request")
      return query ? "HEARD query: have you heard " + *query +
                         " in the last 60 min?"
                   : "HEARD query: recent callsigns (last 60 min)";
    if (!items || items->empty())
      return query ? "HEARD reply: not heard " + *query +
                         " in the last 60 min of this session"
                   : "HEARD reply: no other recent callsigns in this session";
    std::string text = "HEARD reply: ";
    for (auto &i : *items) {
      if (text != "HEARD reply: ")
        text += "; ";
      text += i.call + " (" + std::to_string(i.age < 60 ? i.age : i.age / 60) +
              (i.age < 60 ? "s" : "m") + " ago, SNR ";
      if (i.signal) {
        std::ostringstream o;
        o << std::fixed << std::setprecision(1) << double(*i.signal) / 10
          << " dB";
        text += o.str();
      } else
        text += "unavailable";
      text += ")";
    }
    return text;
  }
};
struct HeardBook {
  struct Observation {
    std::string call;
    double time;
    std::optional<int> signal;
  };
  std::map<std::string, Observation> entries;
  double start = INFINITY;
  std::string own;
  void begin(const std::string &call, double now) {
    entries.clear();
    start = now;
    own = call;
  }
  void clear() {
    entries.clear();
    start = INFINITY;
    own.clear();
  }
  void observe(const std::string &source, std::optional<double> snr,
               double received, double now, bool fallback = false) {
    auto c = HeardMessage::canonical(source);
    double age = now - received;
    if (!station(c) || c == HeardMessage::canonical(own) || received < start ||
        !std::isfinite(age) || age < -5 || age > 3600)
      return;
    for (auto i = entries.begin(); i != entries.end();)
      if (now - i->second.time > 3600)
        i = entries.erase(i);
      else
        ++i;
    auto old = entries.find(c);
    if (old != entries.end()) {
      if (fallback && std::abs(received - old->second.time) <= 5)
        return;
      if (received < old->second.time &&
          !(!old->second.signal && snr &&
            std::abs(received - old->second.time) <= 5))
        return;
    }
    std::optional<int> signal;
    if (snr && std::isfinite(*snr) && std::abs(*snr) <= 200)
      signal = int(std::round(*snr * 10));
    entries[c] = {c, received, signal};
    if (entries.size() > 256)
      entries.erase(std::min_element(
          entries.begin(), entries.end(),
          [](auto &a, auto &b) { return a.second.time < b.second.time; }));
  }
  std::vector<HeardItem> select(const std::optional<std::string> &query,
                                const std::string &requester,
                                double now) const {
    std::vector<Observation> sorted;
    for (auto &i : entries)
      sorted.push_back(i.second);
    std::sort(sorted.begin(), sorted.end(), [](auto &a, auto &b) {
      return a.time == b.time ? a.call < b.call : a.time > b.time;
    });
    std::vector<HeardItem> result;
    std::set<std::string> bases;
    for (auto &i : sorted) {
      double age = now - i.time;
      if (!std::isfinite(age) || age < -5 || age > 3600)
        continue;
      if (query) {
        if (!HeardMessage::matches(i.call, *query))
          continue;
      } else if (HeardMessage::base(i.call) == HeardMessage::base(requester) ||
                 !bases.insert(HeardMessage::base(i.call)).second)
        continue;
      result.push_back({i.call, std::max(0, int(age)), i.signal});
      if (result.size() >= (query ? 1 : 3))
        break;
    }
    return result;
  }
};
struct HeardSession {
  struct Pending {
    std::string source, id;
    std::optional<std::string> query;
    double received, due;
  };
  struct Requested {
    double time;
    std::optional<std::string> query;
    std::string destination;
  };
  std::vector<Pending> pending;
  std::map<std::string, Requested> requested;
  std::map<std::string, double> replied;
  std::set<std::string> seen;
  std::deque<std::string> order;
  void reset() { *this = HeardSession{}; }
  std::optional<std::string> receive(const Packet &p, const std::string &own,
                                     bool outgoing, bool enabled, double now,
                                     double delay) {
    auto m = HeardMessage::decode(p.text);
    if (!station(p.source))
      throw std::runtime_error("Invalid Heard sender.");
    auto key = p.source + ":" + m.kind + ":" + m.id;
    if (seen.count(key))
      return {};
    for (auto i = requested.begin(); i != requested.end();)
      if (now - i->second.time > 600)
        i = requested.erase(i);
      else
        ++i;
    if (m.kind == "reply" && !outgoing) {
      auto i = requested.find(m.id);
      if (p.destination != own || i == requested.end() ||
          i->second.query != m.query ||
          (i->second.destination != "QST" && i->second.destination != "CQ" &&
           i->second.destination != "ALL" && p.source != i->second.destination))
        return {};
    } else if (m.kind == "request") {
      if (!outgoing && p.destination != own && p.destination != "QST" &&
          p.destination != "CQ" && p.destination != "ALL")
        return {};
      if (outgoing) {
        if (requested.size() >= 16)
          requested.erase(std::min_element(
              requested.begin(), requested.end(),
              [](auto &a, auto &b) { return a.second.time < b.second.time; }));
        requested[m.id] = {now, m.query, p.destination};
      } else if (enabled && p.source != own && pending.size() < 8 &&
                 (!replied.count(p.source) || now - replied[p.source] >= 60))
        pending.push_back({p.source, m.id, m.query, now,
                           now + std::max(2.0, std::min(24.0, delay))});
    }
    seen.insert(key);
    order.push_back(key);
    if (order.size() > 512) {
      seen.erase(order.front());
      order.pop_front();
    }
    return m.readable();
  }
  std::optional<Packet> reply(const std::string &own, double now,
                              const HeardBook &book) {
    pending.erase(std::remove_if(pending.begin(), pending.end(),
                                 [&](auto &p) {
                                   return now - p.received > 120 ||
                                          (replied.count(p.source) &&
                                           now - replied[p.source] < 60);
                                 }),
                  pending.end());
    auto i = std::find_if(pending.begin(), pending.end(),
                          [&](auto &p) { return now >= p.due; });
    if (i == pending.end())
      return {};
    HeardMessage m{"reply", i->id, i->query,
                   book.select(i->query, i->source, now)};
    std::string wire;
    for (;;) {
      try {
        wire = m.encode();
        break;
      } catch (...) {
        if (m.items->empty())
          throw;
        m.items->pop_back();
      }
    }
    Packet p{own, i->source, wire};
    replied[i->source] = now;
    pending.erase(i);
    if (replied.size() > 256)
      replied.erase(std::min_element(
          replied.begin(), replied.end(),
          [](auto &a, auto &b) { return a.second < b.second; }));
    return p;
  }
};
} // namespace qso
