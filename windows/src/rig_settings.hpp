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
inline bool serialEndpoint(const std::string &device) {
  // Named com0com endpoints are valid even when enumeration cannot find them.
  return std::regex_match(device, std::regex(R"((COM[1-9][0-9]{0,3}|CNC[A-Z][0-9]+))", std::regex::icase));
}
inline std::vector<std::string>
rigArguments(int model, const std::string &device, int baud, int port = 4532) {
  if (model <= 0 || port < 1 || port > 65535)
    throw std::runtime_error("Choose a radio model and valid rigctld listening port.");
  std::vector<std::string> args{"-m", std::to_string(model)};
  if (model == 2 || model == 4) {
    std::smatch match;
    if (!std::regex_match(device, match, std::regex(R"(([A-Za-z0-9_.-]+):([0-9]{1,5}))")) ||
        std::stoi(match[2]) < 1 || std::stoi(match[2]) > 65535)
      throw std::runtime_error("Network radio model: enter upstream host:port in CAT endpoint. FLRig normally uses 127.0.0.1:12345.");
    if ((match[1] == "127.0.0.1" || match[1] == "localhost") && std::stoi(match[2]) == port)
      throw std::runtime_error("Upstream and local rigctld ports must differ. Use Existing rigctld to connect directly.");
    args.insert(args.end(), {"-r", device});
  } else if (model != 1 && model != 6) {
    if (!serialEndpoint(device) || baud < 1200 || baud > 921600)
      throw std::runtime_error("Choose your actual radio model, CAT COM/com0com port and baud rate. You can type a virtual port name.");
    args.insert(args.end(), {"-r", device, "-s", std::to_string(baud)});
  }
  args.insert(args.end(), {"-P", "RIG", "-T", "127.0.0.1", "-t", std::to_string(port), "-vv"});
  return args;
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
