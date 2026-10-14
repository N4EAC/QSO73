#include "link_safety.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace qso;
int main(int argc, char **argv) {
  for (auto url : {"http://example.com", "javascript:alert(1)",
                   "file:///etc/passwd", "https://user:secret@example.com/",
                   "https://@example.com/", "https://127.0.0.1/",
                   "https://10.0.0.1/", "https://[::1]/", "https://localhost/",
                   "https://radio.local/", "https://radio.localdomain/",
                   "https://example.com:8443/", "https://example.com/%0Dtest",
                   "https://example.com/%09test", "https://xn--fake-123.com/",
                   "https://exa\\mple.com/", "https://example.com\n/evil"}) {
    bool rejected = false;
    try {
      CheckedLink l(url);
    } catch (...) {
      rejected = true;
    }
    assert(rejected);
  }
  assert(CheckedLink("https://example.com/path?q=radio#section").host ==
         "example.com");
  assert(CheckedLink("HTTPS://EXAMPLE.COM:443/").host == "example.com");
  for (Bytes address : std::vector<Bytes>{{0, 0, 0, 0},
                                          {10, 1, 2, 3},
                                          {127, 0, 0, 1},
                                          {172, 16, 1, 1},
                                          {192, 168, 0, 1},
                                          {169, 254, 1, 1},
                                          {100, 64, 0, 1},
                                          {198, 18, 1, 1},
                                          {203, 0, 113, 1},
                                          {224, 0, 0, 1}})
    assert(!DNSLinkCheck::publicAddress(address));
  assert(DNSLinkCheck::publicAddress({93, 184, 216, 34}));
  assert(!DNSLinkCheck::publicAddress(Bytes(16, 0)));
  auto q = DNSLinkCheck::query("example.com", 1);
  if (argc > 1) {
    std::ofstream f(argv[1], std::ios::binary);
    f.write((char *)q.data(), q.size());
  }
  auto answer = q;
  answer[2] = 0x81;
  answer[3] = 0x80;
  answer[7] = 1;
  answer.insert(answer.end(),
                {0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 93, 184, 216, 34});
  assert(DNSLinkCheck::response(answer, "example.com", 1));
  auto rejected = [](const Bytes &b, const std::string &host) {
    try {
      DNSLinkCheck::response(b, host, 1);
      return false;
    } catch (...) {
      return true;
    }
  };
  auto blocked = answer;
  std::fill(blocked.end() - 4, blocked.end(), 0);
  assert(rejected(blocked, "example.com"));
  auto nx = q;
  nx[2] = 0x81;
  nx[3] = 0x83;
  assert(rejected(nx, "example.com"));
  q[2] = 0x81;
  q[3] = 0x80;
  assert(!DNSLinkCheck::response(q, "example.com", 1));
  for (size_t i = 0; i < answer.size(); ++i)
    assert(rejected(Bytes(answer.begin(), answer.begin() + i), "example.com"));
  assert(rejected(answer, "different.com"));
  auto loop = answer;
  loop[12] = 0xc0;
  loop[13] = 12;
  assert(rejected(loop, "example.com"));
  std::cout << "PASS: Windows HTTPS policy, malware/private DNS responses, "
               "correlation and malformed-response rejection\n";
}
