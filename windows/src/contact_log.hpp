#pragma once
#include "protocol.hpp"
#include <cmath>
#include <ctime>
#include <iomanip>
#include <regex>
#include <sstream>
namespace qso {
struct Contact {
  std::string id, callsign, station, grid, myGrid, frequency, start, end, sent,
      received, note;
  static std::string clean(std::string s) {
    s = call(s);
    return std::regex_replace(s, std::regex("-[0-9]{1,2}$"), "");
  }
  static bool validCall(const std::string &s) {
    return s.size() >= 3 && s.size() <= 32 &&
           std::regex_match(s, std::regex("[A-Z0-9]+(/[A-Z0-9]+)*")) &&
           s.find_first_of("0123456789") != s.npos &&
           s.find_first_of("ABCDEFGHIJKLMNOPQRSTUVWXYZ") != s.npos;
  }
  static bool validGrid(const std::string &s) {
    return s.empty() ||
           std::regex_match(
               s, std::regex("[A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?"));
  }
  static std::string utc(std::time_t value) {
    std::tm t{};
#ifdef _WIN32
    gmtime_s(&t, &value);
#else
    gmtime_r(&value, &t);
#endif
    std::ostringstream o;
    o << std::put_time(&t, "%Y%m%d %H%M%S");
    return o.str();
  }
  static std::time_t timestamp(const std::string &value) {
    if (!std::regex_match(value, std::regex("[0-9]{8} [0-9]{6}")))
      throw std::runtime_error("Use UTC dates YYYYMMDD and times HHMMSS.");
    std::tm t{};
    std::istringstream input(value);
    input >> std::get_time(&t, "%Y%m%d %H%M%S");
    if (input.fail() || t.tm_year < 0 || t.tm_year > 199)
      throw std::runtime_error("Invalid UTC date/time.");
#ifdef _WIN32
    auto result = _mkgmtime(&t);
#else
    auto result = timegm(&t);
#endif
    if (utc(result) != value)
      throw std::runtime_error("Invalid UTC calendar date/time.");
    return result;
  }
  std::string band() const {
    size_t parsed = 0;
    double f = std::stod(frequency, &parsed);
    if (parsed != frequency.size() || !std::isfinite(f))
      throw std::runtime_error("Enter frequency in MHz.");
    struct Band {
      const char *name;
      double low, high;
    };
    for (auto b : {Band{"2190m", .1357, .1378}, Band{"630m", .472, .479},
                   Band{"560m", .501, .504},    Band{"160m", 1.8, 2},
                   Band{"80m", 3.5, 4},         Band{"60m", 5.06, 5.45},
                   Band{"40m", 7, 7.3},         Band{"30m", 10.1, 10.15},
                   Band{"20m", 14, 14.35},      Band{"17m", 18.068, 18.168},
                   Band{"15m", 21, 21.45},      Band{"12m", 24.89, 24.99},
                   Band{"10m", 28, 29.7},       Band{"8m", 40, 45},
                   Band{"6m", 50, 54},          Band{"5m", 54.000001, 69.9},
                   Band{"4m", 70, 71},          Band{"2m", 144, 148},
                   Band{"1.25m", 222, 225},     Band{"70cm", 420, 450},
                   Band{"33cm", 902, 928},      Band{"23cm", 1240, 1300}})
      if (f >= b.low && f <= b.high)
        return b.name;
    throw std::runtime_error("Frequency is outside supported amateur bands.");
  }
  void validate() {
    callsign = clean(callsign);
    station = clean(station);
    grid = call(grid);
    myGrid = call(myGrid);
    if (!validCall(callsign) || !validCall(station) || callsign == station ||
        !validGrid(grid) || !validGrid(myGrid))
      throw std::runtime_error(
          "Check distinct station/contact callsigns and Maidenhead grids.");
    band();
    if (timestamp(end) < timestamp(start))
      throw std::runtime_error("End UTC cannot precede start UTC.");
    for (auto &s : {sent, received, note})
      if (s.size() > 512 ||
          !std::all_of(s.begin(), s.end(),
                       [](unsigned char c) { return c >= 32 && c <= 126; }))
        throw std::runtime_error(
            "Reports/notes require printable ASCII, up to 512 characters.");
  }
  std::string adif() const {
    auto c = *this;
    c.validate();
    std::ostringstream freq;
    freq.imbue(std::locale::classic());
    freq << std::fixed << std::setprecision(6) << std::stod(c.frequency);
    std::string result;
    const std::pair<std::string, std::string> fields[] = {
        {"CALL", c.callsign},
        {"STATION_CALLSIGN", c.station},
        {"OPERATOR", c.station},
        {"QSO_DATE", c.start.substr(0, 8)},
        {"TIME_ON", c.start.substr(9)},
        {"QSO_DATE_OFF", c.end.substr(0, 8)},
        {"TIME_OFF", c.end.substr(9)},
        {"FREQ", freq.str()},
        {"BAND", c.band()},
        {"MODE", "PKT"},
        {"GRIDSQUARE", c.grid},
        {"MY_GRIDSQUARE", c.myGrid},
        {"RST_SENT", c.sent},
        {"RST_RCVD", c.received},
        {"COMMENT", c.note}};
    for (const auto &pair : fields)
      if (!pair.second.empty())
        result += "<" + pair.first + ":" + std::to_string(pair.second.size()) +
                  ">" + pair.second;
    return result + "<EOR>\n";
  }
  Json json() const {
    auto j = cJSON_CreateObject();
    for (auto &p : std::vector<std::pair<std::string, std::string>>{
             {"id", id},
             {"call", callsign},
             {"station", station},
             {"grid", grid},
             {"myGrid", myGrid},
             {"frequency", frequency},
             {"start", start},
             {"end", end},
             {"sent", sent},
             {"received", received},
             {"note", note}})
      cJSON_AddStringToObject(j, p.first.c_str(), p.second.c_str());
    return Json(j);
  }
  static Contact from(const Json &j) {
    return {j.str("id"),       j.str("call"),   j.str("station"),
            j.str("grid"),     j.str("myGrid"), j.str("frequency"),
            j.str("start"),    j.str("end"),    j.str("sent"),
            j.str("received"), j.str("note")};
  }
  static std::string exportADIF(const std::vector<Contact> &contacts) {
    std::string s = "QSO73 contact "
                    "export\n<ADIF_VER:5>3.1.6<PROGRAMID:5>QSO73<"
                    "PROGRAMVERSION:5>1.1.1<EOH>\n";
    for (auto &c : contacts)
      s += c.adif();
    return s;
  }
};
} // namespace qso
