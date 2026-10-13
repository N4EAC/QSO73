#pragma once
#include "protocol.hpp"
#include <cmath>
#include <iomanip>
#include <sstream>
namespace qso {
inline std::string metric(const Json &json, const char *key, int decimals = 0,
                          const std::string &unit = "") {
  auto item = cJSON_GetObjectItemCaseSensitive(json.p, key);
  if (!cJSON_IsNumber(item) || !std::isfinite(item->valuedouble))
    return "--";
  std::ostringstream out;
  out << std::fixed << std::setprecision(decimals) << item->valuedouble << unit;
  return out.str();
}
inline std::string dashboard(const std::string &status,
                             const std::string &config,
                             const std::string &frames, const std::string &call,
                             const std::string &frequency,
                             const std::deque<std::string> &activity,
                             const std::deque<double> &occupancy) {
  Json s(status.empty() ? "{}" : status), c(config.empty() ? "{}" : config),
      f(frames.empty() ? "{}" : frames);
  std::vector<std::string> recent;
  std::vector<std::pair<double, std::string>> records;
  std::string heard = "--", snrHist, lastSignal = "--";
  double ber = -1;
  auto array = cJSON_GetObjectItemCaseSensitive(f.p, "frames");
  cJSON *item;
  int n = 0;
  cJSON_ArrayForEach(item, array) {
    auto who = cJSON_GetObjectItemCaseSensitive(item, "callsign"),
         mode = cJSON_GetObjectItemCaseSensitive(item, "mode"),
         signal = cJSON_GetObjectItemCaseSensitive(item, "snr"),
         age = cJSON_GetObjectItemCaseSensitive(item, "age_s"),
         size = cJSON_GetObjectItemCaseSensitive(item, "size"),
         err = cJSON_GetObjectItemCaseSensitive(item, "ber_pct");
    std::ostringstream row;
    row << "RX ";
    if (cJSON_IsNumber(size))
      row << int(size->valuedouble) << "B ";
    if (cJSON_IsString(who))
      row << who->valuestring << " ";
    if (cJSON_IsNumber(signal))
      row << std::fixed << std::setprecision(1) << signal->valuedouble << "dB ";
    if (cJSON_IsNumber(age))
      row << int(age->valuedouble) << "s";
    auto timestamp = cJSON_GetObjectItemCaseSensitive(item, "time");
    records.emplace_back(cJSON_IsNumber(timestamp) ? timestamp->valuedouble : 0,
                         row.str());
    if (n++ == 0) {
      if (cJSON_IsNumber(signal) && std::isfinite(signal->valuedouble)) {
        std::ostringstream out;
        out << std::fixed << std::setprecision(1) << signal->valuedouble
            << " dB";
        lastSignal = out.str();
      }
      if (cJSON_IsString(mode))
        heard = mode->valuestring;
      if (cJSON_IsString(who))
        heard += " " + std::string(who->valuestring);
      if (cJSON_IsNumber(err))
        ber = err->valuedouble;
    }
    if (cJSON_IsNumber(signal))
      snrHist += signal->valuedouble < 0    ? '.'
                 : signal->valuedouble < 10 ? ':'
                 : signal->valuedouble < 20 ? '='
                                            : '#';
  }
  auto tx = cJSON_GetObjectItemCaseSensitive(s.p, "tx_history");
  cJSON_ArrayForEach(item, tx) {
    auto size = cJSON_GetObjectItemCaseSensitive(item, "size"),
         age = cJSON_GetObjectItemCaseSensitive(item, "age_s"),
         time = cJSON_GetObjectItemCaseSensitive(item, "time");
    std::ostringstream row;
    row << "TX ";
    if (cJSON_IsNumber(size))
      row << int(size->valuedouble) << "B ";
    if (cJSON_IsNumber(age))
      row << int(age->valuedouble) << "s";
    records.emplace_back(cJSON_IsNumber(time) ? time->valuedouble : 0,
                         row.str());
  }
  std::sort(records.begin(), records.end(),
            [](const auto &a, const auto &b) { return a.first > b.first; });
  for (auto &r : records)
    if (recent.size() < 6)
      recent.push_back(r.second);
  std::string trail;
  for (auto &a : activity)
    trail += a == "tx" ? 'T' : a == "rx" ? 'R' : '.';
  std::string occ;
  for (auto a : occupancy)
    occ += a < 10 ? '.' : a < 30 ? ':' : a < 60 ? '=' : '#';
  auto level = cJSON_GetObjectItemCaseSensitive(s.p, "rx_audio_level_db");
  std::string bar = "--";
  if (cJSON_IsNumber(level)) {
    int fill = std::clamp(int((level->valuedouble + 100) / 100 * 20), 0, 20);
    bar = "[" + std::string(fill, '=') + std::string(20 - fill, ' ') + "]";
  }
  std::string state = s.str("channel_state"),
              csma = cJSON_IsBool(
                         cJSON_GetObjectItemCaseSensitive(c.p, "csma_enabled"))
                         ? (c.yes("csma_enabled") ? "ON" : "OFF")
                         : "--";
  if (s.yes("dcd_active"))
    csma += " BUSY (sync)";
  else if (state == "tx")
    csma += " TX";
  std::ostringstream errorPercent;
  double total = s.num("sync_count");
  if (total > 0)
    errorPercent << std::fixed << std::setprecision(1)
                 << s.num("rx_error_count") / total * 100 << "%";
  else
    errorPercent << "--";
  std::string quiet = metric(s, "csma_quiet_ms", 0, " ms"),
              window = metric(s, "csma_window_ms", 0, " ms");
  if (s.num("csma_quiet_ms") <= 0)
    quiet = c.num("csma_quiet_ms") > 0 ? metric(c, "csma_quiet_ms", 0, " ms")
                                       : "auto (no acquisition yet)";
  if (s.num("csma_window_ms") <= 0)
    window = "-- (no acquisition yet)";
  std::string berText = "--";
  if (ber >= 0) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(2) << ber << "%";
    berText = out.str();
  }
  std::vector<std::pair<std::string, std::string>> rows = {
      {"SIGNAL", "ACTIVITY (sampled; T=TX R=RX)"},
      {"Carrier   " + metric(s, "rx_audio_level_db", 1, " dBFS"),
       trail.empty() ? "--" : trail},
      {"Level     " + bar, ""},
      {"Threshold " + metric(c, "carrier_threshold_db", 0, " dB"), "STATS"},
      {"Last SNR  " + lastSignal, "RX " + metric(s, "rx_frame_count") +
                                      "  TX " + metric(s, "tx_frame_count")},
      {"SNR hist  " + (snrHist.empty() ? "--" : snrHist),
       "Err " + metric(s, "rx_error_count") + "/" + metric(s, "sync_count") +
           " (" + errorPercent.str() + ")"},
      {"BER       " + berText, "Clients " + metric(s, "client_count") +
                                   "  Queue " + metric(s, "tx_queue")},
      {"Heard     " + heard, ""},
      {"", "RECENT RX / TX FRAMES"},
      {"CSMA", recent.size() > 0 ? recent[0] : "--"},
      {"Status    " + csma, recent.size() > 1 ? recent[1] : ""},
      {"Occupancy " + metric(s, "occupancy_pct", 0, "%"),
       recent.size() > 2 ? recent[2] : ""},
      {"Occ hist  " + (occ.empty() ? "--" : occ),
       recent.size() > 3 ? recent[3] : ""},
      {"Quiet     " + quiet, recent.size() > 4 ? recent[4] : ""},
      {"Last CW   " + window, recent.size() > 5 ? recent[5] : ""},
      {"Slot      " + metric(c, "slot_time_ms", 0, " ms"), ""},
      {std::string("TX        ") + (state == "tx"   ? "sending"
                                    : state.empty() ? "--"
                                                    : "idle"),
       "RADIO"},
      {"", "CAT " + std::string(s.yes("rigctl_connected") ? "connected"
                                                          : "unavailable")},
      {"Audio     " +
           std::string(s.yes("audio_connected") ? "ready" : "unavailable"),
       frequency.empty() ? "Frequency --" : frequency},
  };
  std::string output = "QSO73 / MODEM73 2.4.2 | " + call + " | " +
                       c.str("modulation") + " | " +
                       (state.empty() ? "OFFLINE" : state) + "\r\n";
  output += std::string(78, '-') + "\r\n";
  for (auto &row : rows) {
    auto left = row.first.substr(0, 38);
    left.resize(40, ' ');
    output += left + row.second.substr(0, 38) + "\r\n";
  }
  return output;
}
} // namespace qso
