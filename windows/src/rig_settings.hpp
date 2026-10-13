#pragma once
#include "protocol.hpp"
#include <cmath>
#include <iomanip>
#include <regex>
#include <sstream>
namespace qso {
struct RigModel {
  int id;
  std::string label;
};
inline std::vector<RigModel> radioModels(const std::string &output) {
  std::regex pattern(R"(^\s*(\d+)\s{2,}(.+?)\s{2,}(.+?)\s{2,}(\S+)\s+(\S+))");
  std::vector<RigModel> result;
  std::istringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    std::smatch m;
    if (std::regex_search(line, m, pattern)) {
      int id = std::stoi(m[1]);
      if (id > 0)
        result.push_back(
            {id, std::to_string(id) + " - " + trim(m[2]) + " " + trim(m[3])});
    }
  }
  std::sort(result.begin(), result.end(), [](const auto &a, const auto &b) {
    return a.label.substr(a.label.find(" - ") + 3) <
           b.label.substr(b.label.find(" - ") + 3);
  });
  return result;
}
inline std::vector<std::string>
rigArguments(int model, const std::string &device, int baud) {
  if (model <= 0 ||
      !std::regex_match(device, std::regex("COM[1-9][0-9]{0,3}")) ||
      baud < 1200 || baud > 921600)
    throw std::runtime_error(
        "Choose your radio model, CAT COM port and baud rate.");
  return {"-m", std::to_string(model), "-r", device,
          "-s", std::to_string(baud),  "-P", "RIG",
          "-T", "127.0.0.1",           "-t", "4532",
          "-vv"};
}
inline bool validFrequencyReply(std::string response) {
  auto line = response.substr(0, response.find('\n'));
  line = trim(line);
  try {
    size_t consumed = 0;
    double hz = std::stod(line, &consumed);
    return consumed == line.size() && std::isfinite(hz) && hz > 0;
  } catch (...) {
    return false;
  }
}

inline std::string frequencyText(const std::string &response) {
  if (!validFrequencyReply(response))
    return "";
  std::ostringstream output;
  output << std::fixed << std::setprecision(6)
         << std::stod(response) / 1000000.0 << " MHz";
  return output.str();
}

} // namespace qso
