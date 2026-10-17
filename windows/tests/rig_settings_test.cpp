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
  reject([] { rigArguments(3092, "COM0", 9600); });
  reject([] { rigArguments(3092, "COM3 -m 1", 9600); });
  reject([] { rigArguments(3092, "COM3", 0); });
  assert(serialEndpoint("CNCA0") && serialEndpoint("CNCB12") && serialEndpoint("com257"));
  assert(!serialEndpoint("COM0") && !serialEndpoint("COM3 -m 1"));
  auto virtualArgs = rigArguments(3092, "CNCA0", 19200, 5002);
  assert(std::find(virtualArgs.begin(), virtualArgs.end(), "CNCA0") != virtualArgs.end());
  assert(std::find(virtualArgs.begin(), virtualArgs.end(), "5002") != virtualArgs.end());
  auto flrig = rigArguments(4, "127.0.0.1:12345", 0);
  assert(std::find(flrig.begin(), flrig.end(), "-s") == flrig.end());
  auto net = rigArguments(2, "radio.example:5000", 0);
  assert(std::find(net.begin(), net.end(), "radio.example:5000") != net.end());
  reject([] { rigArguments(4, "COM3", 9600); });
  reject([] { rigArguments(4, "localhost:65536", 9600); });
  reject([] { rigArguments(2, "localhost:4532", 9600); });
  assert(!rigArguments(1, "", 0).empty());
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
