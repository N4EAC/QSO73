#pragma once
#include "protocol.hpp"
#include <cmath>
#include <ctime>
#include <iomanip>
#include <sstream>
namespace qso {
enum class ChatTone { own, automatic, received };
struct ChatRGB {
  int red, green, blue;
};
inline ChatRGB chatRGB(ChatTone tone, bool cyberpunk = false) {
  if(cyberpunk) return tone==ChatTone::own ? ChatRGB{103,182,255} : tone==ChatTone::automatic ? ChatRGB{255,192,100} : ChatRGB{119,230,163};
  return tone == ChatTone::automatic ? ChatRGB{143, 57, 0}
         : tone == ChatTone::own     ? ChatRGB{7, 85, 176}
                                     : ChatRGB{0, 103, 53};
}
inline ChatTone chatTone(const Entry &e) {
  return e.automatic  ? ChatTone::automatic
         : e.outgoing ? ChatTone::own
                      : ChatTone::received;
}
inline std::string utcStamp(double epoch) {
  std::time_t seconds = std::time_t(epoch);
  std::tm t{};
#ifdef _WIN32
  gmtime_s(&t, &seconds);
#else
  gmtime_r(&seconds, &t);
#endif
  std::ostringstream out;
  out << std::put_time(&t, "%H:%M:%S UTC");
  return out.str();
}
inline std::string chatLine(const Entry &e) {
  return utcStamp(e.utc) + " | " + e.source + ":\r\n" + e.text + "\r\n\r\n";
}
inline std::string beaconCountdown(bool on, bool pending, bool ready,
                                   double due, double now) {
  if (!on && !pending)
    return "Beacon off";
  if (!ready)
    return "Beacon paused";
  if (pending || (due > 0 && now >= due))
    return "Beacon waiting idle";
  if (due <= 0)
    return "Beacon scheduling";
  int seconds = int(std::ceil(std::max(0.0, due - now)));
  std::ostringstream o;
  o << "Beacon " << std::setw(2) << std::setfill('0') << seconds / 60 << ":"
    << std::setw(2) << seconds % 60;
  return o.str();
}
} // namespace qso
