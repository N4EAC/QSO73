#pragma once
#include "cJSON.h"
#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <deque>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
namespace qso {
using Bytes = std::vector<uint8_t>;
struct Json {
  cJSON *p = nullptr;
  explicit Json(const std::string &s) {
    const char *end = nullptr;
    p = cJSON_ParseWithLengthOpts(s.c_str(), s.size() + 1, &end, 1);
    if (!p)
      throw std::runtime_error("Invalid JSON");
  }
  explicit Json(cJSON *value) : p(value) {}
  ~Json() { cJSON_Delete(p); }
  Json(const Json &) = delete;
  Json &operator=(const Json &) = delete;
  std::string str(const char *key) const {
    auto v = cJSON_GetObjectItemCaseSensitive(p, key);
    return cJSON_IsString(v) ? v->valuestring : "";
  }
  double num(const char *key, double fallback = 0) const {
    auto v = cJSON_GetObjectItemCaseSensitive(p, key);
    return cJSON_IsNumber(v) ? v->valuedouble : fallback;
  }
  bool yes(const char *key) const {
    return cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(p, key));
  }
  std::string dump(bool pretty = false) const {
    char *s = pretty ? cJSON_Print(p) : cJSON_PrintUnformatted(p);
    if (!s)
      throw std::runtime_error("JSON allocation failed");
    std::string r = s;
    cJSON_free(s);
    return r;
  }
};
inline std::string trim(std::string s) {
  auto space = [](unsigned char c) { return std::isspace(c); };
  while (!s.empty() && space(s.front()))
    s.erase(s.begin());
  while (!s.empty() && space(s.back()))
    s.pop_back();
  return s;
}
inline std::string call(std::string s) {
  s = trim(s);
  for (char &c : s)
    c = std::toupper((unsigned char)c);
  if (s.size() > 2 && s.substr(s.size() - 2) == "-0")
    s.resize(s.size() - 2);
  return s;
}
inline bool address(const std::string &s) {
  auto n = s.find('-');
  auto a = s.substr(0, n);
  if (a.empty() || a.size() > 6)
    return false;
  for (auto c : a)
    if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')))
      return false;
  if (n != s.npos) {
    auto b = s.substr(n + 1);
    if (b.empty() || b.size() > 2 ||
        b.find_first_not_of("0123456789") != b.npos || std::stoi(b) > 15)
      return false;
  }
  return true;
}
inline bool station(const std::string &s) {
  return address(s) &&
         s.find_first_of("ABCDEFGHIJKLMNOPQRSTUVWXYZ") != s.npos &&
         s.find_first_of("0123456789") != s.npos;
}
inline std::string channel(std::string s) {
  s = trim(s);
  for (auto &c : s)
    c = std::tolower((unsigned char)c);
  if (s.empty() || s[0] != '#')
    s = "#" + s;
  if (s.size() < 2 || s.size() > 21 ||
      s.substr(1).find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789-_") !=
          s.npos)
    throw std::runtime_error("Channel names use 1-20 letters, digits, - or _.");
  return s;
}
inline bool uuid(const std::string &s) {
  if (s.size() != 36)
    return false;
  for (size_t i = 0; i < 36; ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (s[i] != '-')
        return false;
    } else if (!std::isxdigit((unsigned char)s[i]))
      return false;
  }
  return true;
}
inline bool utf8(const std::string &s) {
  size_t i = 0;
  while (i < s.size()) {
    uint8_t a = s[i++];
    if (a < 128)
      continue;
    int n = 0;
    uint32_t cp = 0, min = 0;
    if (a >= 0xc2 && a <= 0xdf) {
      n = 1;
      cp = a & 31;
      min = 128;
    } else if (a >= 0xe0 && a <= 0xef) {
      n = 2;
      cp = a & 15;
      min = 2048;
    } else if (a >= 0xf0 && a <= 0xf4) {
      n = 3;
      cp = a & 7;
      min = 65536;
    } else
      return false;
    while (n--) {
      if (i == s.size())
        return false;
      uint8_t b = s[i++];
      if ((b & 0xc0) != 0x80)
        return false;
      cp = (cp << 6) | (b & 63);
    }
    if (cp < min || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff))
      return false;
  }
  return true;
}
struct Envelope {
  std::string k, r, t, id;
  void validate() const {
    if (!uuid(id) || !utf8(t) || t.find_first_of("\r\n\v\f") != t.npos ||
        t.find('\0') != t.npos || t.find("\xc2\x85") != t.npos ||
        t.find("\xE2\x80\xA8") != t.npos || t.find("\xE2\x80\xA9") != t.npos)
      throw std::runtime_error("Invalid conversation content.");
    if (k != "msg" && k != "join" && k != "leave" && k != "topic" &&
        k != "announce")
      throw std::runtime_error("Invalid conversation event.");
    if (!r.empty() && r[0] == '#') {
      if (channel(r) != r)
        throw std::runtime_error("Noncanonical channel.");
    } else if (k != "msg" || !station(r) || call(r) != r)
      throw std::runtime_error("Invalid direct recipient.");
    if (k == "msg" && trim(t).empty())
      throw std::runtime_error("Enter a message.");
    if ((k == "join" || k == "leave") && !t.empty())
      throw std::runtime_error("Invalid membership event.");
  }
  std::string encode() const {
    validate();
    Json j(cJSON_CreateObject());
    cJSON_AddNumberToObject(j.p, "v", 1);
    cJSON_AddStringToObject(j.p, "k", k.c_str());
    cJSON_AddStringToObject(j.p, "r", r.c_str());
    cJSON_AddStringToObject(j.p, "t", t.c_str());
    cJSON_AddStringToObject(j.p, "id", id.c_str());
    auto s = "~Q73:" + j.dump();
    if (s.size() > 200)
      throw std::runtime_error("Shorten the message/topic: routing and text "
                               "must fit 200 UTF-8 bytes.");
    return s;
  }
  static Envelope decode(const std::string &s) {
    if (s.size() > 200 || s.rfind("~Q73:", 0) != 0)
      throw std::runtime_error("Invalid envelope.");
    if (s.find("\\u0000") != s.npos)
      throw std::runtime_error("NUL is not allowed in conversation strings.");
    Json j(s.substr(5));
    for (auto field : {"k", "r", "t", "id"})
      if (!cJSON_IsString(cJSON_GetObjectItemCaseSensitive(j.p, field)))
        throw std::runtime_error("Missing conversation field.");
    if (j.num("v", -1) != 1)
      throw std::runtime_error("Unsupported protocol version.");
    Envelope e{j.str("k"), j.str("r"), j.str("t"), j.str("id")};
    e.validate();
    return e;
  }
};
inline Bytes addr(const std::string &s, bool last) {
  if (!address(s))
    throw std::runtime_error("Invalid AX.25 address.");
  auto n = s.find('-');
  auto a = s.substr(0, n);
  a.resize(6, ' ');
  Bytes b;
  for (auto c : a)
    b.push_back(uint8_t(c) << 1);
  b.push_back(0x60 | ((n == s.npos ? 0 : std::stoi(s.substr(n + 1))) << 1) |
              (last ? 1 : 0));
  return b;
}
inline std::string unaddr(const Bytes &b, size_t pos) {
  if (pos + 7 > b.size())
    throw std::runtime_error("Truncated address.");
  std::string a;
  for (size_t i = 0; i < 6; i++) {
    auto v = b[pos + i];
    if (v & 1)
      throw std::runtime_error("Malformed address.");
    a += char(v >> 1);
  }
  a = trim(a);
  int ssid = (b[pos + 6] >> 1) & 15;
  if (ssid)
    a += "-" + std::to_string(ssid);
  if (!address(a))
    throw std::runtime_error("Malformed address.");
  return a;
}
struct Packet {
  std::string source, destination, text;
  bool automatic = false;
  Bytes encode() const {
    if (text.empty() || text.size() > 200 || !utf8(text))
      throw std::runtime_error("Packet allows 1-200 UTF-8 bytes.");
    auto b = addr(destination, false);
    auto a = addr(source, true);
    b.insert(b.end(), a.begin(), a.end());
    b.insert(b.end(), {3, 0xf0});
    b.insert(b.end(), text.begin(), text.end());
    return b;
  }
  static Packet decode(const Bytes &b) {
    if (b.size() < 17 || (b[6] & 1))
      throw std::runtime_error("Not AX.25 UI.");
    Packet p{unaddr(b, 7), unaddr(b, 0), ""};
    size_t pos = 14;
    bool last = b[13] & 1;
    int count = 2;
    while (!last) {
      if (pos + 7 > b.size() || count++ >= 10)
        throw std::runtime_error("Invalid path.");
      unaddr(b, pos);
      last = b[pos + 6] & 1;
      pos += 7;
    }
    if (pos + 2 >= b.size() || (b[pos] & 0xef) != 3 || b[pos + 1] != 0xf0)
      throw std::runtime_error("Not UI text.");
    p.text = std::string(b.begin() + pos + 2, b.end());
    if (!utf8(p.text))
      throw std::runtime_error("Not UTF-8 text.");
    return p;
  }
};
inline Bytes kiss(const Bytes &b) {
  Bytes r{0xc0, 0};
  for (auto c : b) {
    if (c == 0xc0)
      r.insert(r.end(), {0xdb, 0xdc});
    else if (c == 0xdb)
      r.insert(r.end(), {0xdb, 0xdd});
    else
      r.push_back(c);
  }
  r.push_back(0xc0);
  return r;
}
struct Framer {
  Bytes b;
  bool inside = false, escape = false, bad = false;
  std::vector<Bytes> feed(const Bytes &input) {
    std::vector<Bytes> out;
    for (auto c : input) {
      if (c == 0xc0) {
        if (!bad && !escape && !b.empty() && (b[0] & 15) == 0)
          out.emplace_back(b.begin() + 1, b.end());
        b.clear();
        inside = true;
        escape = bad = false;
      } else if (inside && !bad) {
        if (escape) {
          if (c != 0xdc && c != 0xdd) {
            bad = true;
            continue;
          }
          b.push_back(c == 0xdc ? 0xc0 : 0xdb);
          escape = false;
        } else if (c == 0xdb)
          escape = true;
        else
          b.push_back(c);
        if (b.size() > 65536) {
          b.clear();
          bad = true;
        }
      }
    }
    return out;
  }
};
struct Entry {
  std::string room, source, text;
  bool outgoing = false;
  bool automatic = false;
  double utc = std::chrono::duration<double>(
                   std::chrono::system_clock::now().time_since_epoch())
                   .count();
};
struct Rooms {
  std::set<std::string> joined, discovered, directs, seen;
  std::deque<std::string> seenOrder;
  std::map<std::string, std::string> topics;
  std::map<std::string, std::map<std::string, double>> members, participants;
  std::map<std::string, int> unread;
  std::vector<Entry> entries;
  std::string selected = "radio";
  bool route(const Packet &p, const std::string &own, bool outgoing,
             double now) {
    if (!outgoing && p.destination != own && p.destination != "QST" &&
        p.destination != "CQ" && p.destination != "ALL")
      return false;
    Entry entry{"radio", p.source, p.text, outgoing};
    entry.automatic = p.automatic || (p.text.rfind("BEACON ", 0) == 0 &&
                                      p.text.find(" QSO73 v") != p.text.npos);
    if (p.text.rfind("~Q73:", 0) == 0) {
      auto e = Envelope::decode(p.text);
      entry.automatic = entry.automatic || e.k != "msg";
      if (!station(p.source))
        throw std::runtime_error("Invalid sender.");
      bool ch = e.r[0] == '#';
      if (ch) {
        if (p.destination != "QST")
          throw std::runtime_error("Channel must be QST.");
        entry.room = e.r;
      } else {
        if (p.destination != e.r || (!outgoing && p.destination != own))
          return false;
        entry.room = outgoing ? p.destination : p.source;
      }
      auto key = p.source + ":" + e.id;
      if (seen.count(key))
        return false;
      seen.insert(key);
      seenOrder.push_back(key);
      if (seenOrder.size() > 4000) {
        seen.erase(seenOrder.front());
        seenOrder.pop_front();
      }
      if (ch) {
        discovered.insert(e.r);
        if (e.k == "leave") {
          members[e.r].erase(p.source);
          participants[e.r].erase(p.source);
        } else
          members[e.r][p.source] = now;
        if (e.k == "topic" || (e.k == "announce" && !topics.count(e.r)))
          topics[e.r] = e.t;
        if (!outgoing && p.source != own && (e.k == "join" || e.k == "msg"))
          participants[e.r][p.source] = now;
        if (!joined.count(e.r) && !outgoing)
          return false;
      } else
        directs.insert(entry.room);
      if (e.k == "msg")
        entry.text = e.t;
      else if (e.k == "topic")
        entry.text = e.t.empty() ? "cleared the topic" : "topic: " + e.t;
      else if (e.k == "announce")
        entry.text =
            "invites stations to " + e.r + (e.t.empty() ? "" : " - " + e.t);
      else
        entry.text = e.k == "join" ? "joined " + e.r : "left " + e.r;
    }
    entries.push_back(entry);
    if (entries.size() > 10000)
      entries.erase(entries.begin());
    if (!outgoing && entry.room != selected)
      unread[entry.room]++;
    return true;
  }
  std::vector<std::string> users(const std::string &room,
                                 const std::string &own, double now) const {
    std::set<std::string> calls;
    auto it = members.find(room);
    if (it != members.end())
      for (auto &p : it->second)
        if (now - p.second <= 600)
          calls.insert(p.first);
    if (joined.count(room))
      calls.insert(own);
    return {calls.begin(), calls.end()};
  }
  bool hasParticipant(const std::string &room, double now) const {
    auto it = participants.find(room);
    if (it != participants.end())
      for (auto &p : it->second)
        if (now - p.second <= 600)
          return true;
    return false;
  }
};
} // namespace qso
