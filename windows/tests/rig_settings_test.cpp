#include "rig_settings.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
using namespace qso;
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
  auto models = radioModels(
      " Rig #  Mfg                    Model                   Version         "
      "Status\n     1  Hamlib                 Dummy                   "
      "20240709.0      Stable\n  1049  Yaesu                  FT-710           "
      "       20250310.0      Stable\n  3073  Icom                   IC-7300   "
      "              20260101.0      Stable\n");
  assert(models.size() == 3);
  bool found = false;
  for (auto &m : models)
    if (m.id == 1049) {
      found = true;
      assert(m.label == "1049 - Yaesu FT-710");
    }
  assert(found);
  assert(validFrequencyReply("7100000\n"));
  assert(frequencyText("7105000\n") == "7.105000 MHz");
  assert(frequencyText("RPRT -7\n").empty());
  assert(!validFrequencyReply("RPRT -7\n"));
  assert(!validFrequencyReply("nan\n"));
  assert(!validFrequencyReply("0\n"));
  assert(!validFrequencyReply("7100000junk\n"));
  auto args = rigArguments(1049, "COM12", 115200);
  assert(args == std::vector<std::string>({"-m", "1049", "-r", "COM12", "-s",
                                           "115200", "-P", "RIG", "-T",
                                           "127.0.0.1", "-t", "4532", "-vv"}));
  reject([] { rigArguments(0, "COM1", 9600); });
  reject([] { rigArguments(1, "COM0", 9600); });
  reject([] { rigArguments(1, "COM3 -m 1", 9600); });
  reject([] { rigArguments(1, "COM3", 0); });
  if (argc > 1) {
    std::ifstream f(argv[1]);
    auto all =
        radioModels(std::string((std::istreambuf_iterator<char>(f)), {}));
    assert(all.size() > 200);
    bool ft = false;
    for (auto &m : all)
      if (m.id == 1049)
        ft = true;
    assert(ft);
    std::cout << "PASS: parsed " << all.size() << " actual Hamlib models\n";
  }
  std::cout << "PASS: bundled rigctld model/COM/baud validation, CAT PTT "
               "arguments and localhost binding\n";
}
