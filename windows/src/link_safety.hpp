#pragma once
#include "protocol.hpp"
#include <optional>
#include <regex>
namespace qso {
struct CheckedLink {
  std::string url, host;
  explicit CheckedLink(const std::string &raw) {
    auto lower = raw;
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c) { return char(std::tolower(c)); });
    if (raw.size() > 2048 || lower.rfind("https://", 0) ||
        raw.find('\\') != raw.npos ||
        std::any_of(raw.begin(), raw.end(),
                    [](unsigned char c) { return c < 33 || c == 127; }) ||
        std::regex_search(lower, std::regex("%(0[0-9a-f]|1[0-9a-f]|7f)")))
      throw std::runtime_error(
          "Only HTTPS links without control characters are opened.");
    auto end = lower.find_first_of("/?#", 8);
    auto authority = lower.substr(8, end == lower.npos ? lower.npos : end - 8);
    if (authority.find('@') != authority.npos)
      throw std::runtime_error("Links with credentials are blocked.");
    auto colon = authority.find(':');
    if (colon != authority.npos) {
      if (authority.substr(colon) != ":443")
        throw std::runtime_error(
            "IP literals and unusual URL ports are blocked.");
      authority.resize(colon);
    }
    host = authority;
    if (host.size() > 253 || host.find("xn--") != host.npos)
      throw std::runtime_error(
          "Ambiguous or internationalized hostnames are blocked.");
    std::vector<std::string> labels;
    size_t start = 0;
    for (;;) {
      auto dot = host.find('.', start);
      auto label =
          host.substr(start, dot == host.npos ? host.npos : dot - start);
      if (label.empty() || label.size() > 63 || label.front() == '-' ||
          label.back() == '-' ||
          !std::all_of(label.begin(), label.end(), [](unsigned char c) {
            return c < 128 && (std::isalnum(c) || c == '-');
          }))
        throw std::runtime_error("Invalid hostname.");
      labels.push_back(label);
      if (dot == host.npos)
        break;
      start = dot + 1;
    }
    std::set<std::string> reserved{
        "local", "localhost", "localdomain", "lan",     "internal",
        "home",  "onion",     "test",        "invalid", "example"};
    if (labels.size() < 2 || labels.back().size() < 2 ||
        !std::all_of(
            labels.back().begin(), labels.back().end(),
            [](unsigned char c) { return c < 128 && std::isalpha(c); }) ||
        reserved.count(labels.back()))
      throw std::runtime_error("Local and IP-literal links are blocked.");
    url = raw;
  }
};
struct DNSLinkCheck {
  static Bytes query(const std::string &host, uint16_t type) {
    Bytes b{0x73, 0x51, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0};
    size_t p = 0;
    for (;;) {
      auto e = host.find('.', p);
      auto label = host.substr(p, e == host.npos ? host.npos : e - p);
      b.push_back(uint8_t(label.size()));
      b.insert(b.end(), label.begin(), label.end());
      if (e == host.npos)
        break;
      p = e + 1;
    }
    b.insert(b.end(), {0, uint8_t(type >> 8), uint8_t(type), 0, 1});
    return b;
  }
  static bool publicAddress(const Bytes &b) {
    if (b.size() == 4)
      return !(b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
               (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
               (b[0] == 169 && b[1] == 254) ||
               (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
               (b[0] == 192 &&
                (b[1] == 168 || (b[1] == 0 && (b[2] == 0 || b[2] == 2)))) ||
               (b[0] == 198 &&
                (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
               (b[0] == 203 && b[1] == 0 && b[2] == 113));
    if (b.size() == 16)
      return (b[0] & 0xe0) == 0x20 && !(b[0] == 0x20 && b[1] == 2) &&
             !(b[0] == 0x20 && b[1] == 1 &&
               ((b[2] == 0x0d && b[3] == 0xb8) || (b[2] == 0 && b[3] == 0)));
    return false;
  }
  static bool response(const Bytes &b, const std::string &host, uint16_t type) {
    auto fail = []() {
      throw std::runtime_error("Domain blocked, unresolvable, or security "
                               "reply invalid. Link not opened.");
    };
    auto word = [&](size_t p) -> int {
      if (p + 2 > b.size())
        fail();
      return int(b[p]) << 8 | b[p + 1];
    };
    auto name = [&](size_t &start) {
      size_t p = start;
      std::optional<size_t> end;
      std::set<size_t> seen;
      std::string out;
      for (int step = 0; step < 64; ++step) {
        if (p >= b.size() || !seen.insert(p).second)
          fail();
        int n = b[p++];
        if (n == 0) {
          start = end ? *end : p;
          return out;
        }
        if ((n & 0xc0) == 0xc0) {
          if (p >= b.size())
            fail();
          if (!end)
            end = p + 1;
          p = ((n & 0x3f) << 8) | b[p];
          continue;
        }
        if (n > 63 || p + size_t(n) > b.size())
          fail();
        if (!out.empty())
          out += '.';
        for (int i = 0; i < n; ++i) {
          if (b[p] < 33 || b[p] >= 127)
            fail();
          out += char(std::tolower(b[p++]));
        }
      }
      fail();
      return std::string{};
    };
    if (b.size() < 12 || b.size() > 4096 || word(0) != 0x7351 ||
        (word(2) & 0x8000) == 0 || (word(2) & 0x020f) != 0 || word(4) != 1 ||
        word(6) > 64)
      fail();
    size_t p = 12;
    if (name(p) != host || word(p) != type || word(p + 2) != 1)
      fail();
    p += 4;
    bool found = false;
    for (int i = 0; i < word(6); ++i) {
      name(p);
      int t = word(p), cls = word(p + 2), length = word(p + 8);
      p += 10;
      if (p + size_t(length) > b.size())
        fail();
      if (cls == 1 && (t == 1 || t == 28)) {
        if (length != (t == 1 ? 4 : 16) ||
            !publicAddress(Bytes(b.begin() + p, b.begin() + p + length)))
          fail();
        found = true;
      }
      p += length;
    }
    return found;
  }
  static std::string base64URL(const Bytes &bytes) {
    static const char *table =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    std::string s;
    uint32_t v = 0;
    int bits = 0;
    for (auto b : bytes) {
      v = (v << 8) | b;
      bits += 8;
      while (bits >= 6) {
        bits -= 6;
        s += table[(v >> bits) & 63];
      }
    }
    if (bits)
      s += table[(v << (6 - bits)) & 63];
    return s;
  }
};
} // namespace qso
