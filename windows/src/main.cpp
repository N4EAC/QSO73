#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
// Windows headers must precede common-control declarations.
// clang-format off
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <objbase.h>
#include <shellapi.h>
// clang-format on
#include "protocol.hpp"
#include "rig_settings.hpp"
#include <atomic>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <thread>
using namespace qso;
constexpr const wchar_t *VERSION = L"0.4.7 Windows test 3";
enum ControlID {
  START = 101,
  ROOMS,
  NEWROOM,
  JOIN,
  LEAVE,
  TOPIC,
  USERS,
  TO,
  SEND,
  CQ,
  SNR,
  CLOSEQSO,
  CUSTOM,
  ACTIVITY,
  EXPORT,
  REFRESH,
  SAVE,
  BEACON,
  BEACONMIN,
  ANNOUNCE,
  ANNMIN,
  SETFREQ,
  REFRESHRIG,
  BEACONNOW
};
enum SettingID {
  CALL = 201,
  GRID,
  RXDEVICE,
  OUTPUT,
  FAMILY,
  MODE,
  PTT,
  DRIVE,
  RIGHOST,
  RIGPORT,
  FREQUENCY,
  CUSTOMTEXT,
  RIGMODEL,
  CATCOM,
  CATBAUD
};
HWND win, history, composer, statusLabel, topicLabel, frequencyLabel;
HANDLE activityProcess = nullptr;
std::string catFrequency;
double frequencyTime = 0, lastActivityWrite = 0;
bool beaconPending = false;
std::map<int, HWND> controls;
HFONT font;
std::wstring base;
Rooms rooms;
std::map<std::string, std::string> drafts;
std::set<std::string> contacts;
struct Settings {
  std::string call, grid, input, output, family = "robust", mode = "RDM-600S",
                                         ptt = "rigctl", rigHost = "127.0.0.1",
                                         custom;
  int drive = 25, rigPort = 4532, rigModel = 0, catBaud = 38400;
  std::string catCOM;
};
Settings settings;
std::atomic<bool> running{false}, connected{false};
std::thread worker;
std::mutex mutex;
struct Event {
  std::string kind, data;
  Packet packet;
};
std::deque<Event> events;
std::deque<Packet> sends;
std::deque<std::string> commands;
HANDLE engine = nullptr, job = nullptr, rigDaemon = nullptr;
DWORD rigPID = 0;
std::vector<RigModel> modelCatalog;
DWORD enginePID = 0;
std::string rawStatus, rawConfig, rawFrames, lastError, channelState;
std::deque<std::string> modemEvents;
bool audioReady = false, rigReady = false;
int queueDepth = 0;
double statusTime = 0, beaconDue = 0, announcementDue = 0, lastAuto = 0;
std::string announceRoom;
bool beaconOn = false, announceOn = false;
std::vector<std::string> roomNames{"radio"};
double now() {
  return std::chrono::duration<double>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}
std::wstring wide(const std::string &s) {
  if (s.empty())
    return L"";
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(),
                              int(s.size()), nullptr, 0);
  std::wstring w(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.data(), int(s.size()), w.data(), n);
  return w;
}
std::string narrow(const std::wstring &s) {
  if (s.empty())
    return "";
  int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), int(s.size()), nullptr, 0,
                              nullptr, nullptr);
  std::string r(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, s.data(), int(s.size()), r.data(), n, nullptr,
                      nullptr);
  return r;
}
std::string text(HWND h) {
  int n = GetWindowTextLengthW(h);
  std::wstring s(n + 1, 0);
  GetWindowTextW(h, s.data(), n + 1);
  s.resize(n);
  return narrow(s);
}
std::string value(int id) { return text(controls.at(id)); }
void put(HWND h, const std::string &s) { SetWindowTextW(h, wide(s).c_str()); }
void notify(const std::string &s) {
  lastError = s;
  put(statusLabel, s);
}
void error(const std::exception &e) {
  MessageBoxW(win, wide(e.what()).c_str(), L"QSO73", MB_OK | MB_ICONWARNING);
}
std::string newID() {
  GUID id;
  CoCreateGuid(&id);
  wchar_t s[40];
  StringFromGUID2(id, s, 40);
  auto r = narrow(s);
  return r.substr(1, 36);
}
void post(Event e) {
  std::lock_guard<std::mutex> l(mutex);
  events.push_back(std::move(e));
}
void comboSet(int id, const std::vector<std::string> &vals,
              const std::string &chosen) {
  auto h = controls[id];
  SendMessageW(h, CB_RESETCONTENT, 0, 0);
  int selected = -1;
  for (size_t i = 0; i < vals.size(); i++) {
    SendMessageW(h, CB_ADDSTRING, 0, (LPARAM)wide(vals[i]).c_str());
    if (vals[i] == chosen)
      selected = int(i);
  }
  if (selected < 0 && !chosen.empty()) {
    selected = int(vals.size());
    SendMessageW(h, CB_ADDSTRING, 0, (LPARAM)wide(chosen).c_str());
  }
  SendMessageW(h, CB_SETCURSEL, selected, 0);
}
HWND child(const wchar_t *cls, const std::wstring &caption, int id, int x,
           int y, int w, int h, DWORD style = 0) {
  auto a = CreateWindowExW(wcscmp(cls, L"EDIT") == 0 ? WS_EX_CLIENTEDGE : 0,
                           cls, caption.c_str(), WS_CHILD | WS_VISIBLE | style,
                           x, y, w, h, win, (HMENU)(INT_PTR)id,
                           GetModuleHandleW(nullptr), nullptr);
  SendMessageW(a, WM_SETFONT, (WPARAM)font, TRUE);
  if (id)
    controls[id] = a;
  return a;
}
void label(const wchar_t *s, int x, int y, int w = 170) {
  child(L"STATIC", s, 0, x, y, w, 20);
}
void edit(int id, int x, int y, int w, const std::string &s) {
  child(L"EDIT", wide(s), id, x, y, w, 25, WS_TABSTOP | ES_AUTOHSCROLL);
}
void button(int id, const wchar_t *s, int x, int y, int w) {
  child(L"BUTTON", s, id, x, y, w, 27, WS_TABSTOP);
}
void combo(int id, int x, int y, int w, const std::vector<std::string> &vals,
           const std::string &choice, bool editable = false) {
  child(L"COMBOBOX", L"", id, x, y, w, 240,
        WS_TABSTOP | WS_VSCROLL | (editable ? CBS_DROPDOWN : CBS_DROPDOWNLIST));
  comboSet(id, vals, choice);
}
void saveSettings() {
  Json j(cJSON_CreateObject());
  for (auto p : std::vector<std::pair<const char *, std::string>>{
           {"call", settings.call},
           {"grid", settings.grid},
           {"input", settings.input},
           {"output", settings.output},
           {"family", settings.family},
           {"mode", settings.mode},
           {"ptt", settings.ptt},
           {"rigHost", settings.rigHost},
           {"custom", settings.custom},
           {"catCOM", settings.catCOM}})
    cJSON_AddStringToObject(j.p, p.first, p.second.c_str());
  cJSON_AddNumberToObject(j.p, "drive", settings.drive);
  cJSON_AddNumberToObject(j.p, "rigPort", settings.rigPort);
  cJSON_AddNumberToObject(j.p, "rigModel", settings.rigModel);
  cJSON_AddNumberToObject(j.p, "catBaud", settings.catBaud);
  auto a = cJSON_AddArrayToObject(j.p, "joined");
  for (auto &r : rooms.joined)
    cJSON_AddItemToArray(a, cJSON_CreateString(r.c_str()));
  std::ofstream f(std::filesystem::path(base + L"settings.json"),
                  std::ios::binary);
  if (!f)
    throw std::runtime_error(
        "Cannot save portable settings. Extract QSO73 to a writable folder.");
  f << j.dump(true);
}
void loadSettings() {
  std::ifstream f(std::filesystem::path(base + L"settings.json"),
                  std::ios::binary);
  if (!f)
    return;
  std::string s((std::istreambuf_iterator<char>(f)), {});
  try {
    Json j(s);
    settings.call = j.str("call");
    settings.grid = j.str("grid");
    settings.input = j.str("input");
    settings.output = j.str("output");
    settings.family = j.str("family");
    settings.mode = j.str("mode");
    settings.ptt = j.str("ptt");
    settings.rigHost = "127.0.0.1";
    settings.custom = j.str("custom");
    settings.drive = int(j.num("drive", 25));
    settings.rigPort = 4532;
    settings.rigModel = int(j.num("rigModel", 0));
    settings.catCOM = j.str("catCOM");
    settings.catBaud = int(j.num("catBaud", 38400));
    auto a = cJSON_GetObjectItemCaseSensitive(j.p, "joined");
    cJSON *v;
    cJSON_ArrayForEach(v, a) {
      if (cJSON_IsString(v)) {
        auto r = channel(v->valuestring);
        rooms.joined.insert(r);
        rooms.discovered.insert(r);
      }
    }
  } catch (...) {
    settings = Settings{};
  }
}
void readSettings() {
  Settings s;
  s.call = call(value(CALL));
  s.grid = call(value(GRID));
  s.input = value(RXDEVICE);
  s.output = value(OUTPUT);
  s.family = value(FAMILY);
  s.mode = value(MODE);
  s.ptt = value(PTT);
  s.rigHost = "127.0.0.1";
  s.custom = value(CUSTOMTEXT);
  s.drive = std::stoi(value(DRIVE));
  s.rigPort = 4532;
  int index = int(SendMessageW(controls[RIGMODEL], CB_GETCURSEL, 0, 0));
  s.rigModel = index > 0 && index <= int(modelCatalog.size())
                   ? modelCatalog[index - 1].id
                   : 0;
  s.catCOM = call(value(CATCOM));
  s.catBaud = std::stoi(value(CATBAUD));
  if (s.ptt == "rigctl")
    rigArguments(s.rigModel, s.catCOM, s.catBaud);
  if (!station(s.call))
    throw std::runtime_error("Enter your callsign, optional SSID 0-15.");
  if (s.input.empty() || s.output.empty() || s.input == "default" ||
      s.output == "default")
    throw std::runtime_error(
        "Select explicit radio USB input and output devices.");
  if (s.drive < 5 || s.drive > 100 || s.rigPort < 1 || s.rigPort > 65535)
    throw std::runtime_error("Audio level: 5-100. rigctld port: 1-65535.");
  if (s.rigHost.empty())
    throw std::runtime_error("Enter the rigctld host.");
  settings = s;
  saveSettings();
}
std::wstring quote(const std::wstring &s) {
  std::wstring r = L"\"";
  int slash = 0;
  for (auto c : s) {
    if (c == '\\')
      slash++;
    else {
      r.append(slash * (c == '"' ? 2 : 1), L'\\');
      slash = 0;
      if (c == '"')
        r += L'\\';
      r += c;
    }
  }
  r.append(slash * 2, L'\\');
  return r + L"\"";
}
PROCESS_INFORMATION launchProgram(const std::wstring &exe,
                                  const std::vector<std::string> &args,
                                  const std::wstring &log, bool own) {
  std::wstring cmd = quote(exe);
  for (auto &a : args)
    cmd += L" " + quote(wide(a));
  SECURITY_ATTRIBUTES sa{sizeof(sa), nullptr, TRUE};
  HANDLE out = CreateFileW(log.c_str(), GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  HANDLE in =
      CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                  OPEN_EXISTING, 0, nullptr);
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  si.hStdOutput = si.hStdError = out;
  si.hStdInput = in;
  PROCESS_INFORMATION pi{};
  BOOL ok = CreateProcessW(exe.c_str(), cmd.data(), nullptr, nullptr, TRUE,
                           CREATE_NEW_CONSOLE | CREATE_SUSPENDED, nullptr,
                           base.c_str(), &si, &pi);
  CloseHandle(out);
  CloseHandle(in);
  if (!ok)
    throw std::runtime_error("Cannot launch bundled executable. Extract the "
                             "complete portable folder.");
  if (own && !AssignProcessToJobObject(job, pi.hProcess)) {
    TerminateProcess(pi.hProcess, 1);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    throw std::runtime_error("Cannot supervise modem process.");
  }
  ResumeThread(pi.hThread);
  CloseHandle(pi.hThread);
  return pi;
}
PROCESS_INFORMATION launch(const std::vector<std::string> &args,
                           const std::wstring &log, bool own) {
  return launchProgram(base + L"engine\\modem73.exe", args, log, own);
}
void refreshRig() {
  if (running || rigDaemon)
    throw std::runtime_error(
        "Stop the modem before refreshing radio settings.");
  auto pi = launchProgram(base + L"hamlib\\bin\\rigctld.exe", {"-l"},
                          base + L"radio-models.txt", false);
  if (WaitForSingleObject(pi.hProcess, 5000) != WAIT_OBJECT_0) {
    TerminateProcess(pi.hProcess, 1);
    CloseHandle(pi.hProcess);
    throw std::runtime_error("Hamlib model list timed out.");
  }
  DWORD result = 0;
  GetExitCodeProcess(pi.hProcess, &result);
  CloseHandle(pi.hProcess);
  if (result != 0)
    throw std::runtime_error("Bundled Hamlib could not load. Extract the "
                             "complete package including hamlib/bin DLLs.");
  std::ifstream file(std::filesystem::path(base + L"radio-models.txt"));
  std::string data((std::istreambuf_iterator<char>(file)), {});
  modelCatalog = radioModels(data);
  if (modelCatalog.empty())
    throw std::runtime_error("Hamlib returned no recognizable radio models.");
  std::vector<std::string> labels{"Select radio model"};
  std::string selected = labels[0];
  for (const auto &model : modelCatalog) {
    labels.push_back(model.label);
    if (model.id == settings.rigModel)
      selected = model.label;
  }
  comboSet(RIGMODEL, labels, selected);
  SendMessageW(controls[RIGMODEL], CB_SETDROPPEDWIDTH, 450, 0);
  std::vector<std::string> ports;
  wchar_t buffer[4096];
  for (int i = 1; i <= 256; ++i) {
    std::wstring port = L"COM" + std::to_wstring(i);
    if (QueryDosDeviceW(port.c_str(), buffer, 4096))
      ports.push_back(narrow(port));
  }
  comboSet(CATCOM, ports, settings.catCOM);
  notify("Bundled Hamlib 4.7.2: " + std::to_string(modelCatalog.size()) +
         " models. Choose the radio's CAT COM port and matching baud.");
}
void closeChild(HANDLE &process, DWORD pid, DWORD signal) {
  if (!process)
    return;
  if (WaitForSingleObject(process, 0) != WAIT_OBJECT_0) {
    FreeConsole();
    if (AttachConsole(pid)) {
      SetConsoleCtrlHandler(nullptr, TRUE);
      GenerateConsoleCtrlEvent(signal, 0);
      WaitForSingleObject(process, 3000);
      FreeConsole();
      SetConsoleCtrlHandler(nullptr, FALSE);
    }
    if (WaitForSingleObject(process, 0) != WAIT_OBJECT_0)
      TerminateProcess(process, 1);
    WaitForSingleObject(process, 2000);
  }
  CloseHandle(process);
  process = nullptr;
}
void refreshDevices() {
  if (running)
    throw std::runtime_error("Stop the modem before refreshing devices.");
  auto pi = launch({"--list-audio"}, base + L"audio-devices.txt", false);
  DWORD result = WaitForSingleObject(pi.hProcess, 8000);
  if (result != WAIT_OBJECT_0) {
    TerminateProcess(pi.hProcess, 1);
    CloseHandle(pi.hProcess);
    throw std::runtime_error("Audio enumeration timed out.");
  }
  CloseHandle(pi.hProcess);
  std::ifstream f(std::filesystem::path(base + L"audio-devices.txt"));
  std::string line;
  std::vector<std::string> in, out;
  int section = 0;
  while (std::getline(f, line)) {
    if (line.find("Input devices:") != line.npos) {
      section = 1;
      continue;
    }
    if (line.find("Output devices:") != line.npos) {
      section = 2;
      continue;
    }
    auto s = trim(line);
    if (line.rfind("  ", 0) != 0 || s.empty() || s.rfind("default", 0) == 0)
      continue;
    if (section == 1)
      in.push_back(s);
    if (section == 2)
      out.push_back(s);
  }
  comboSet(RXDEVICE, in, settings.input);
  comboSet(OUTPUT, out, settings.output);
  notify("Choose the radio's USB audio devices in both lists; system defaults "
         "are excluded.");
}
SOCKET connectPort(const std::string &host, int port) {
  addrinfo hints{}, *info = nullptr;
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &info))
    return INVALID_SOCKET;
  SOCKET s = socket(info->ai_family, info->ai_socktype, info->ai_protocol);
  u_long nb = 1;
  ioctlsocket(s, FIONBIO, &nb);
  int rc = connect(s, info->ai_addr, int(info->ai_addrlen));
  freeaddrinfo(info);
  if (rc == SOCKET_ERROR && WSAGetLastError() != WSAEWOULDBLOCK) {
    closesocket(s);
    return INVALID_SOCKET;
  }
  fd_set fd;
  FD_ZERO(&fd);
  FD_SET(s, &fd);
  timeval tv{1, 0};
  int ready = select(0, nullptr, &fd, nullptr, &tv);
  int err = 0, n = sizeof(err);
  getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&err, &n);
  if (ready <= 0 || err) {
    closesocket(s);
    return INVALID_SOCKET;
  }
  nb = 0;
  ioctlsocket(s, FIONBIO, &nb);
  DWORD timeout = 1500;
  setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
  setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout, sizeof(timeout));
  return s;
}
bool sendAll(SOCKET s, const Bytes &b) {
  size_t i = 0;
  while (i < b.size()) {
    int n = send(s, (const char *)b.data() + i, int(b.size() - i), 0);
    if (n <= 0)
      return false;
    i += n;
  }
  return true;
}
bool readAll(SOCKET s, char *b, size_t size) {
  size_t i = 0;
  while (i < size) {
    int n = recv(s, b + i, int(size - i), 0);
    if (n <= 0)
      return false;
    i += n;
  }
  return true;
}
std::string request(SOCKET s, const std::string &cmd) {
  auto n = uint32_t(cmd.size());
  Bytes b{uint8_t(n >> 24), uint8_t(n >> 16), uint8_t(n >> 8), uint8_t(n)};
  b.insert(b.end(), cmd.begin(), cmd.end());
  if (!sendAll(s, b))
    throw std::runtime_error("Control socket disconnected.");
  for (int events = 0; events < 30; events++) {
    uint8_t h[4];
    if (!readAll(s, (char *)h, 4))
      throw std::runtime_error("Control read timed out.");
    uint32_t count = (uint32_t(h[0]) << 24) | (uint32_t(h[1]) << 16) |
                     (uint32_t(h[2]) << 8) | h[3];
    if (count == 0 || count > 1048576)
      throw std::runtime_error("Invalid control length.");
    std::string r(count, 0);
    if (!readAll(s, r.data(), count))
      throw std::runtime_error("Truncated control response.");
    Json j(r);
    if (!j.str("event").empty()) {
      post({"event", r, {}});
      continue;
    }
    return r;
  }
  throw std::runtime_error("Too many control notifications.");
}
std::string readCATFrequency() {
  SOCKET socket = connectPort("127.0.0.1", 4532);
  if (socket == INVALID_SOCKET)
    return "";
  DWORD timeout = 500;
  setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout,
             sizeof(timeout));
  std::string response;
  if (sendAll(socket, Bytes{'f', '\n'})) {
    while (response.size() < 512 && response.find('\n') == response.npos) {
      char data[128];
      int n = recv(socket, data, sizeof(data), 0);
      if (n <= 0)
        break;
      response.append(data, n);
    }
  }
  closesocket(socket);
  if (response.find('\n') == response.npos)
    return "";
  return frequencyText(response);
}
void network() {
  SOCKET k = INVALID_SOCKET, c = INVALID_SOCKET;
  try {
    double deadline = now() + 15;
    while (running && now() < deadline) {
      k = connectPort("127.0.0.1", 8001);
      c = connectPort("127.0.0.1", 8073);
      if (k != INVALID_SOCKET && c != INVALID_SOCKET)
        break;
      if (k != INVALID_SOCKET)
        closesocket(k);
      if (c != INVALID_SOCKET)
        closesocket(c);
      k = c = INVALID_SOCKET;
      std::this_thread::sleep_for(std::chrono::milliseconds(300));
    }
    if (!running)
      throw std::runtime_error("Stopped.");
    if (k == INVALID_SOCKET || c == INVALID_SOCKET)
      throw std::runtime_error(
          "Engine did not open its local ports. See engine.log.");
    connected = true;
    post({"connected", "", {}});
    post({"config", request(c, "{\"cmd\":\"get_config\"}"), {}});
    Framer fr;
    double poll = 0;
    while (running) {
      std::deque<Packet> outgoing;
      std::deque<std::string> control;
      {
        std::lock_guard<std::mutex> l(mutex);
        outgoing.swap(sends);
        control.swap(commands);
      }
      for (auto &p : outgoing) {
        if (!sendAll(k, kiss(p.encode())))
          throw std::runtime_error(
              "KISS send failed; packet not confirmed submitted.");
        post({"sent", "", p});
      }
      for (auto &cmd : control)
        post({"command", request(c, cmd), {}});
      if (now() >= poll) {
        auto status = request(c, "{\"cmd\":\"get_status\"}");
        post({"status", status, {}});
        if (settings.ptt == "rigctl" &&
            Json(status).str("channel_state") != "tx")
          post({"frequency", readCATFrequency(), {}});
        post({"frames",
              request(c, "{\"cmd\":\"rx_frame_history\",\"limit\":32}"),
              {}});
        poll = now() + 2;
      }
      fd_set fd;
      FD_ZERO(&fd);
      FD_SET(k, &fd);
      timeval tv{0, 100000};
      if (select(0, &fd, nullptr, nullptr, &tv) > 0) {
        uint8_t b[8192];
        int n = recv(k, (char *)b, sizeof(b), 0);
        if (n <= 0)
          throw std::runtime_error("KISS disconnected.");
        for (auto &payload : fr.feed(Bytes(b, b + n))) {
          try {
            post({"packet", "", Packet::decode(payload)});
          } catch (const std::exception &e) {
            post({"event", e.what(), {}});
          }
        }
      }
    }
  } catch (const std::exception &e) {
    if (running)
      post({"error", e.what(), {}});
  }
  connected = false;
  if (k != INVALID_SOCKET)
    closesocket(k);
  if (c != INVALID_SOCKET)
    closesocket(c);
}
void setSettingsEnabled(bool yes) {
  for (int id : std::vector<int>{CALL, GRID, RXDEVICE, OUTPUT, FAMILY, MODE,
                                 PTT, DRIVE, RIGMODEL, CATCOM, CATBAUD,
                                 CUSTOMTEXT, SAVE, REFRESH, REFRESHRIG})
    EnableWindow(controls[id], yes);
}
void startRig() {
  if (settings.ptt != "rigctl")
    return;
  SOCKET existing = connectPort("127.0.0.1", 4532);
  if (existing != INVALID_SOCKET) {
    closesocket(existing);
    throw std::runtime_error(
        "CAT port 4532 is already in use. Stop the other rigctld/radio "
        "application before starting QSO73's bundled CAT service.");
  }
  auto pi = launchProgram(
      base + L"hamlib\\bin\\rigctld.exe",
      rigArguments(settings.rigModel, settings.catCOM, settings.catBaud),
      base + L"rigctld.log", true);
  rigDaemon = pi.hProcess;
  rigPID = pi.dwProcessId;
  double deadline = now() + 8;
  while (now() < deadline) {
    if (WaitForSingleObject(rigDaemon, 0) == WAIT_OBJECT_0)
      break;
    SOCKET probe = connectPort("127.0.0.1", 4532);
    if (probe != INVALID_SOCKET) {
      bool ready = false;
      if (sendAll(probe, Bytes{'f', '\n'})) {
        char reply[512];
        int n = recv(probe, reply, sizeof(reply), 0);
        if (n > 0)
          ready = validFrequencyReply(std::string(reply, reply + n));
      }
      closesocket(probe);
      if (ready)
        return;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  closeChild(rigDaemon, rigPID, CTRL_C_EVENT);
  throw std::runtime_error("Hamlib could not read the radio frequency. Check "
                           "model, CAT COM port and baud; "
                           "see rigctld.log / Modem Activity.");
}
void start() {
  readSettings();
  for (int port : {8001, 8073}) {
    SOCKET s = connectPort("127.0.0.1", port);
    if (s != INVALID_SOCKET) {
      closesocket(s);
      throw std::runtime_error(
          "A modem already uses port 8001 or 8073. Stop it first; QSO73 will "
          "not take over another process.");
    }
  }
  startRig();
  std::ofstream(std::filesystem::path(base + L"engine-empty.conf"));
  std::vector<std::string> a{"--headless",
                             "--config",
                             narrow(base + L"engine-empty.conf"),
                             "--bind",
                             "127.0.0.1",
                             "--control-bind",
                             "127.0.0.1",
                             "--port",
                             "8001",
                             "--control-port",
                             "8073",
                             "--callsign",
                             settings.call.substr(0, settings.call.find('-')),
                             "--input-device",
                             settings.input,
                             "--output-device",
                             settings.output,
                             "--tx-level",
                             std::to_string(settings.drive),
                             "--frag",
                             "--csma-mode",
                             "sync",
                             "--csma-band",
                             "hf",
                             "--modem",
                             settings.family,
                             "--ptt",
                             settings.ptt};
  if (settings.family == "robust")
    a.insert(a.end(), {"--robust-mode", settings.mode});
  else if (settings.family == "mfsk")
    a.insert(a.end(), {"--mfsk-mode", settings.mode});
  else
    a.insert(a.end(),
             {"--modulation", settings.mode, "--rate", "1/2", "--normal"});
  if (settings.ptt == "rigctl")
    a.insert(a.end(), {"--rigctl", settings.rigHost + ":" +
                                       std::to_string(settings.rigPort)});
  PROCESS_INFORMATION pi{};
  try {
    pi = launch(a, base + L"engine.log", true);
  } catch (...) {
    closeChild(rigDaemon, rigPID, CTRL_C_EVENT);
    throw;
  }
  engine = pi.hProcess;
  enginePID = pi.dwProcessId;
  running = true;
  audioReady = false;
  statusTime = 0;
  lastError.clear();
  rawStatus.clear();
  rawConfig.clear();
  rawFrames.clear();
  modemEvents.clear();
  setSettingsEnabled(false);
  SetWindowTextW(controls[START], L"Stop Modem");
  worker = std::thread(network);
  notify("Starting modem - no packets sent automatically.");
}
void stop() {
  running = false;
  if (worker.joinable())
    worker.join();
  connected = false;
  {
    std::lock_guard<std::mutex> l(mutex);
    sends.clear();
    commands.clear();
  }
  if (engine) {
    FreeConsole();
    if (AttachConsole(enginePID)) {
      SetConsoleCtrlHandler(nullptr, TRUE);
      GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, 0);
      WaitForSingleObject(engine, 3000);
      FreeConsole();
      SetConsoleCtrlHandler(nullptr, FALSE);
    }
    if (WaitForSingleObject(engine, 0) != WAIT_OBJECT_0)
      TerminateProcess(engine, 1);
    WaitForSingleObject(engine, 2000);
    CloseHandle(engine);
    engine = nullptr;
    // Ensure rigctld PTT is released after this client's engine stops.
    if (settings.ptt == "rigctl") {
      SOCKET s = connectPort(settings.rigHost, settings.rigPort);
      if (s != INVALID_SOCKET) {
        sendAll(s, Bytes{'T', ' ', '0', '\n'});
        closesocket(s);
      }
    }
  }
  closeChild(rigDaemon, rigPID, CTRL_C_EVENT);
  audioReady = false;
  statusTime = 0;
  beaconDue = announcementDue = 0;
  beaconPending = false;
  catFrequency.clear();
  frequencyTime = 0;
  put(frequencyLabel, "CAT: unavailable");
  setSettingsEnabled(true);
  SetWindowTextW(controls[START], L"Start Modem");
  notify("Modem stopped.");
}
void enqueue(const Packet &p) {
  p.encode();
  if (!connected || !audioReady || (settings.ptt == "rigctl" && !rigReady) ||
      now() - statusTime > 6)
    throw std::runtime_error("Connect the modem and wait for healthy audio, "
                             "PTT and fresh status before sending.");
  std::lock_guard<std::mutex> l(mutex);
  if (sends.size() >= 32)
    throw std::runtime_error("Local queue full.");
  sends.push_back(p);
}
void sendEnvelope(const std::string &k, const std::string &room,
                  const std::string &message) {
  Envelope e{k, room, message, newID()};
  enqueue({settings.call, room[0] == '#' ? "QST" : room, e.encode()});
}
void showHistory() {
  std::string s;
  for (auto &e : rooms.entries)
    if (e.room == rooms.selected)
      s +=
          (e.outgoing ? "You -> " : "") + e.source + ": " + e.text + "\r\n\r\n";
  put(history, s);
  SendMessageW(history, EM_SETSEL, -1, -1);
  SendMessageW(history, EM_SCROLLCARET, 0, 0);
  put(topicLabel, rooms.selected[0] == '#'
                      ? "Topic: " + rooms.topics[rooms.selected]
                  : rooms.selected == "radio"
                      ? "Radio Chat - QST broadcasts to all stations"
                      : "Direct: " + rooms.selected);
}
void rebuildRooms() {
  roomNames = {"radio"};
  roomNames.insert(roomNames.end(), rooms.discovered.begin(),
                   rooms.discovered.end());
  roomNames.insert(roomNames.end(), rooms.directs.begin(), rooms.directs.end());
  std::vector<std::string> labels;
  for (auto &r : roomNames)
    labels.push_back(
        (r == "radio" ? "Radio Chat" : r) +
        (rooms.unread[r] ? " (" + std::to_string(rooms.unread[r]) + ")" : ""));
  comboSet(ROOMS, labels, "");
  auto it = std::find(roomNames.begin(), roomNames.end(), rooms.selected);
  SendMessageW(controls[ROOMS], CB_SETCURSEL, it - roomNames.begin(), 0);
  EnableWindow(controls[LEAVE], rooms.joined.count(rooms.selected));
  EnableWindow(controls[TOPIC],
               rooms.joined.count(rooms.selected) && connected);
  EnableWindow(controls[USERS], rooms.selected[0] == '#');
  EnableWindow(controls[ANNOUNCE], rooms.joined.count(rooms.selected));
  std::vector<std::string> to{"QST"};
  to.insert(to.end(), contacts.begin(), contacts.end());
  comboSet(TO, to, value(TO).empty() ? "QST" : value(TO));
  SendMessageW(controls[ANNOUNCE], BM_SETCHECK,
               announceOn && announceRoom == rooms.selected ? BST_CHECKED
                                                            : BST_UNCHECKED,
               0);
  showHistory();
}
void selectRoom(const std::string &r) {
  drafts[rooms.selected] = text(composer);
  rooms.selected = r;
  rooms.unread[r] = 0;
  put(composer, drafts[r]);
  if (r == "radio")
    put(controls[TO], "QST");
  rebuildRooms();
}
void joinRoom() {
  auto r = trim(value(NEWROOM));
  if (r.empty())
    r = rooms.selected;
  if (r == "radio")
    return;
  if (r[0] == '#') {
    r = channel(r);
    rooms.joined.insert(r);
    rooms.discovered.insert(r);
    saveSettings();
    selectRoom(r);
    if (connected && audioReady)
      sendEnvelope("join", r, "");
  } else {
    r = call(r);
    if (!station(r))
      throw std::runtime_error("Enter a station callsign or #channel.");
    rooms.directs.insert(r);
    selectRoom(r);
  }
}
void sendMessage() {
  auto message = text(composer);
  if (rooms.selected == "radio") {
    auto to = call(value(TO));
    enqueue({settings.call, to, message});
    if (to != "QST")
      contacts.insert(to);
  } else {
    if (rooms.selected[0] == '#' && !rooms.joined.count(rooms.selected))
      throw std::runtime_error(
          "Click Open / Join to join this discovered channel first.");
    sendEnvelope("msg", rooms.selected, message);
  }
  put(composer, "");
  drafts[rooms.selected].clear();
}
std::string measuredSNR(const std::string &target) {
  if (rawFrames.empty())
    throw std::runtime_error("No measured signal report available.");
  Json j(rawFrames);
  auto arr = cJSON_GetObjectItemCaseSensitive(j.p, "frames");
  cJSON *f;
  std::string result;
  double newest = 601;
  cJSON_ArrayForEach(f, arr) {
    auto who = cJSON_GetObjectItemCaseSensitive(f, "callsign");
    auto age = cJSON_GetObjectItemCaseSensitive(f, "age_s");
    auto snr = cJSON_GetObjectItemCaseSensitive(f, "snr");
    if (cJSON_IsString(who) && call(who->valuestring) == target &&
        cJSON_IsNumber(age) && age->valuedouble >= 0 &&
        age->valuedouble <= 600 && age->valuedouble < newest &&
        cJSON_IsNumber(snr) && std::isfinite(snr->valuedouble)) {
      newest = age->valuedouble;
      std::ostringstream s;
      s << std::fixed << std::setprecision(1) << snr->valuedouble;
      result = s.str();
    }
  }
  if (result.empty() || now() - statusTime > 6)
    throw std::runtime_error(
        "No recent sender-labelled SNR from that callsign.");
  return result;
}
struct PromptState {
  HWND input = nullptr;
  std::string value;
  bool done = false, accepted = false;
};
LRESULT CALLBACK promptProc(HWND h, UINT m, WPARAM w, LPARAM l) {
  auto state = (PromptState *)GetWindowLongPtrW(h, GWLP_USERDATA);
  if (m == WM_NCCREATE) {
    auto cs = (CREATESTRUCTW *)l;
    SetWindowLongPtrW(h, GWLP_USERDATA, (LONG_PTR)cs->lpCreateParams);
    return TRUE;
  }
  if (m == WM_COMMAND && state) {
    if (LOWORD(w) == IDOK) {
      state->value = text(state->input);
      state->accepted = true;
      state->done = true;
    } else if (LOWORD(w) == IDCANCEL)
      state->done = true;
    return 0;
  }
  if (m == WM_CLOSE && state) {
    state->done = true;
    return 0;
  }
  return DefWindowProcW(h, m, w, l);
}
bool prompt(const std::wstring &title, const std::wstring &instruction,
            std::string &value) {
  PromptState s;
  WNDCLASSW wc{};
  wc.lpfnWndProc = promptProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"QSO73Prompt";
  wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&wc);
  auto h = CreateWindowExW(WS_EX_DLGMODALFRAME, L"QSO73Prompt", title.c_str(),
                           WS_POPUP | WS_CAPTION | WS_SYSMENU, 150, 150, 520,
                           170, win, nullptr, wc.hInstance, &s);
  auto make = [&](const wchar_t *cls, const wchar_t *txt, int id, int x, int y,
                  int width, DWORD style) {
    auto child =
        CreateWindowExW(wcscmp(cls, L"EDIT") == 0 ? WS_EX_CLIENTEDGE : 0, cls,
                        txt, WS_CHILD | WS_VISIBLE | style, x, y, width, 27, h,
                        (HMENU)(INT_PTR)id, wc.hInstance, nullptr);
    SendMessageW(child, WM_SETFONT, (WPARAM)font, TRUE);
    return child;
  };
  make(L"STATIC", instruction.c_str(), 0, 12, 12, 485, 0);
  s.input = make(L"EDIT", wide(value).c_str(), 1000, 12, 45, 485,
                 WS_TABSTOP | ES_AUTOHSCROLL);
  SendMessageW(s.input, EM_SETLIMITTEXT, 200, 0);
  make(L"BUTTON", L"Transmit Topic", IDOK, 260, 86, 140,
       WS_TABSTOP | BS_DEFPUSHBUTTON);
  make(L"BUTTON", L"Cancel", IDCANCEL, 408, 86, 88, WS_TABSTOP);
  EnableWindow(win, FALSE);
  ShowWindow(h, SW_SHOW);
  SetFocus(s.input);
  MSG msg;
  while (!s.done && GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if (!IsDialogMessageW(h, &msg)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }
  DestroyWindow(h);
  EnableWindow(win, TRUE);
  SetForegroundWindow(win);
  if (s.accepted)
    value = s.value;
  return s.accepted;
}

void macro(int id) {
  auto to = call(value(TO));
  std::string s;
  if (id == CQ) {
    to = "QST";
    s = "CQ CQ CQ de " + settings.call + " " + settings.grid + " K";
  } else if (id == SNR) {
    if (!station(to))
      throw std::runtime_error("Select a station in To for F2.");
    s = to + " de " + settings.call + " SNR " + measuredSNR(to) + " dB K";
  } else if (id == CLOSEQSO) {
    s = to + " de " + settings.call + " TNX QSO 73 SK";
  } else {
    s = settings.custom;
    if (trim(s).empty())
      throw std::runtime_error("Set an F4 custom message in station settings.");
    for (auto pair : std::vector<std::pair<std::string, std::string>>{
             {"{call}", settings.call},
             {"{locator}", settings.grid},
             {"{to}", to}}) {
      size_t pos = 0;
      while ((pos = s.find(pair.first, pos)) != s.npos) {
        s.replace(pos, pair.first.size(), pair.second);
        pos += pair.second.size();
      }
    }
    if (s.find("{snr}") != s.npos) {
      auto report = measuredSNR(to);
      size_t pos;
      while ((pos = s.find("{snr}")) != s.npos)
        s.replace(pos, 5, report);
    }
  }
  enqueue({settings.call, to, s});
}
int minutes(int id) {
  int n = std::stoi(value(id));
  if (n < 1 || n > 60)
    throw std::runtime_error("Interval must be 1-60 minutes.");
  return n;
}
bool validGrid(const std::string &g) {
  if (g.size() != 4 && g.size() != 6 && g.size() != 8)
    return false;
  if (g[0] < 'A' || g[0] > 'R' || g[1] < 'A' || g[1] > 'R' || g[2] < '0' ||
      g[2] > '9' || g[3] < '0' || g[3] > '9')
    return false;
  if (g.size() >= 6 && (g[4] < 'A' || g[4] > 'X' || g[5] < 'A' || g[5] > 'X'))
    return false;
  if (g.size() == 8 && (g[6] < '0' || g[6] > '9' || g[7] < '0' || g[7] > '9'))
    return false;
  return true;
}
void automation() {
  if (!connected || !audioReady || (settings.ptt == "rigctl" && !rigReady) ||
      now() - statusTime > 6)
    return;
  if (beaconOn && !beaconDue)
    beaconDue = now() + minutes(BEACONMIN) * 60;
  if (announceOn && !announcementDue)
    announcementDue = now() + minutes(ANNMIN) * 60;
  if (announceOn && rooms.hasParticipant(announceRoom, now())) {
    announceOn = false;
    rebuildRooms();
  }
  if (channelState != "idle" || queueDepth != 0 || now() - lastAuto < 5)
    return;
  {
    std::lock_guard<std::mutex> l(mutex);
    if (!sends.empty())
      return;
  }
  if (beaconPending || (beaconOn && now() >= beaconDue)) {
    enqueue({settings.call, "QST",
             "BEACON " + settings.call + " " + settings.grid +
                 " QSO73 v0.4.7-win-test3"});
    beaconPending = false;
    beaconDue = beaconOn ? now() + minutes(BEACONMIN) * 60 : 0;
    lastAuto = now();
  } else if (announceOn && now() >= announcementDue) {
    auto topic = rooms.topics[announceRoom];
    while (true) {
      try {
        Envelope e{"announce", announceRoom, topic, newID()};
        e.encode();
        break;
      } catch (...) {
        if (topic.empty())
          throw;
        do {
          topic.pop_back();
        } while (!utf8(topic));
      }
    }
    sendEnvelope("announce", announceRoom, topic);
    announcementDue = now() + minutes(ANNMIN) * 60;
    lastAuto = now();
  }
}
std::string activity() {
  std::string s = std::string("QSO73 Windows test 3 - ") +
                  (connected ? "connected" : "offline (last snapshots)") +
                  "\r\nInput: " + settings.input +
                  "\r\nOutput: " + settings.output + "\r\n\r\nSTATUS\r\n";
  s += "CAT frequency: " +
       (catFrequency.empty() ? std::string("unavailable") : catFrequency) +
       "\r\n";
  for (auto p : std::vector<std::pair<std::string, std::string>>{
           {"", rawStatus},
           {"CONFIGURATION", rawConfig},
           {"RECENT RX FRAMES", rawFrames}}) {
    s += p.first + "\r\n";
    try {
      Json j(p.second);
      s += j.dump(true);
    } catch (...) {
      s += "Unavailable";
    }
    s += "\r\n\r\n";
  }
  s += "RECENT CONTROL EVENTS\r\n";
  for (const auto &e : modemEvents)
    s += e + "\r\n";
  for (const auto &item : std::vector<std::pair<std::wstring, std::string>>{
           {L"rigctld.log", "HAMLIB CAT LOG"}, {L"engine.log", "ENGINE LOG"}}) {
    s += "\r\n" + item.second + "\r\n";
    std::ifstream f(std::filesystem::path(base + item.first), std::ios::binary);
    if (f) {
      f.seekg(0, std::ios::end);
      auto len = f.tellg();
      if (len > std::streamoff(16384))
        f.seekg(len - std::streamoff(16384));
      else
        f.seekg(0);
      s += std::string((std::istreambuf_iterator<char>(f)), {});
    }
  }
  std::string r;
  for (char c : s) {
    if (c == '\n' && (r.empty() || r.back() != '\r'))
      r += '\r';
    r += c;
  }
  return r;
}
void publishActivity() {
  if (!activityProcess)
    return;
  if (WaitForSingleObject(activityProcess, 0) == WAIT_OBJECT_0) {
    CloseHandle(activityProcess);
    activityProcess = nullptr;
    return;
  }
  if (now() - lastActivityWrite < 2)
    return;
  auto temp = base + L"activity-snapshot.tmp",
       target = base + L"activity-snapshot.txt";
  {
    std::ofstream file(std::filesystem::path(temp), std::ios::binary);
    if (!file)
      return;
    file << activity();
  }
  MoveFileExW(temp.c_str(), target.c_str(),
              MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
  lastActivityWrite = now();
}
void openActivity() {
  if (activityProcess &&
      WaitForSingleObject(activityProcess, 0) != WAIT_OBJECT_0) {
    notify("Modem Activity is already open in its text console.");
    return;
  }
  if (activityProcess) {
    CloseHandle(activityProcess);
    activityProcess = nullptr;
  }
  {
    std::ofstream file(std::filesystem::path(base + L"activity-snapshot.txt"),
                       std::ios::binary);
    if (!file)
      throw std::runtime_error(
          "Cannot write activity snapshot in portable folder.");
    file << activity();
  }
  auto exe = base + L"QSO73-Activity.exe";
  auto command = quote(exe) + L" " + quote(base + L"activity-snapshot.txt");
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
                      CREATE_NEW_CONSOLE | CREATE_SUSPENDED, nullptr,
                      base.c_str(), &startup, &process))
    throw std::runtime_error("Cannot launch QSO73-Activity.exe. Extract the "
                             "complete portable package.");
  if (!AssignProcessToJobObject(job, process.hProcess)) {
    TerminateProcess(process.hProcess, 1);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    throw std::runtime_error("Cannot supervise activity console.");
  }
  ResumeThread(process.hThread);
  CloseHandle(process.hThread);
  activityProcess = process.hProcess;
  lastActivityWrite = now();
}
void exportChat() {
  wchar_t path[MAX_PATH] = L"QSO73-chat.txt";
  OPENFILENAMEW of{};
  of.lStructSize = sizeof(of);
  of.hwndOwner = win;
  of.lpstrFilter = L"Text files\0*.txt\0\0";
  of.lpstrFile = path;
  of.nMaxFile = MAX_PATH;
  of.Flags = OFN_OVERWRITEPROMPT;
  of.lpstrDefExt = L"txt";
  if (GetSaveFileNameW(&of)) {
    std::ofstream f(std::filesystem::path(path), std::ios::binary);
    if (!f)
      throw std::runtime_error("Cannot write transcript.");
    for (auto &e : rooms.entries)
      f << "[" << e.room << "] " << (e.outgoing ? "You -> " : "") << e.source
        << ": " << e.text << "\n";
  }
}
void pollUI() {
  std::deque<Event> pending;
  {
    std::lock_guard<std::mutex> l(mutex);
    pending.swap(events);
  }
  bool changed = false;
  for (auto &e : pending) {
    try {
      if (e.kind == "packet" || e.kind == "sent") {
        bool sent = e.kind == "sent";
        if (rooms.route(e.packet, settings.call, sent, now()))
          changed = true;
        if (!sent && e.packet.source != settings.call &&
            station(e.packet.source) && contacts.size() < 200)
          contacts.insert(e.packet.source);
      } else if (e.kind == "status") {
        Json j(e.data);
        rawStatus = e.data;
        statusTime = now();
        audioReady = j.yes("audio_connected");
        rigReady = j.yes("rigctl_connected");
        channelState = j.str("channel_state");
        queueDepth = int(j.num("tx_queue"));
        notify("Connected | Audio " +
               std::string(audioReady ? "ready" : "unavailable") + " | " +
               channelState + " | RX " +
               std::to_string(int(j.num("rx_frame_count"))) + " TX " +
               std::to_string(int(j.num("tx_frame_count"))) + " | Queue " +
               std::to_string(queueDepth) + " | CAT " +
               (j.yes("rigctl_connected") ? "connected" : "unavailable"));
      } else if (e.kind == "config")
        rawConfig = e.data;
      else if (e.kind == "frames")
        rawFrames = e.data;
      else if (e.kind == "frequency") {
        catFrequency = e.data;
        frequencyTime = now();
      } else if (e.kind == "event") {
        modemEvents.push_back(e.data);
        if (modemEvents.size() > 100)
          modemEvents.pop_front();
      } else if (e.kind == "command") {
        Json j(e.data);
        notify(j.yes("ok") ? "CAT response: " + j.str("response")
                           : "CAT command failed: " + e.data);
      } else if (e.kind == "error") {
        lastError = e.data;
        stop();
        notify("Disconnected: " + e.data);
      } else if (e.kind == "connected") {
        changed = true;
        beaconDue = announcementDue = 0;
      }
    } catch (const std::exception &ex) {
      notify(ex.what());
    }
  }
  if (changed)
    rebuildRooms();
  put(frequencyLabel,
      catFrequency.empty()
          ? "CAT: unavailable"
          : catFrequency + (now() - frequencyTime > 6 ? " (last read)" : ""));
  publishActivity();
  if (running && rigDaemon &&
      WaitForSingleObject(rigDaemon, 0) == WAIT_OBJECT_0) {
    stop();
    notify("Hamlib exited. See rigctld.log / Modem Activity.");
  }
  if (running && engine && WaitForSingleObject(engine, 0) == WAIT_OBJECT_0) {
    stop();
    notify("Engine exited. See Modem Activity / engine.log.");
  }
  if (!connected) {
    audioReady = false;
    statusTime = 0;
  }
  if (announceOn && rooms.hasParticipant(announceRoom, now())) {
    announceOn = false;
    rebuildRooms();
  }
  try {
    automation();
  } catch (const std::exception &e) {
    beaconOn = announceOn = false;
    SendMessageW(controls[BEACON], BM_SETCHECK, BST_UNCHECKED, 0);
    notify(e.what());
    rebuildRooms();
  }
  for (int id : {SEND, CQ, SNR, CLOSEQSO, CUSTOM, SETFREQ, BEACONNOW})
    EnableWindow(controls[id],
                 connected && audioReady &&
                     (settings.ptt != "rigctl" || rigReady) &&
                     now() - statusTime <= 6 &&
                     (id != CUSTOM || !settings.custom.empty()) &&
                     (id != BEACONNOW || validGrid(settings.grid)) &&
                     (id != SETFREQ ||
                      (settings.ptt == "rigctl" && channelState == "idle")));
  EnableWindow(controls[TOPIC], connected && audioReady &&
                                    (settings.ptt != "rigctl" || rigReady) &&
                                    rooms.joined.count(rooms.selected));
}
void modes() {
  auto family = value(FAMILY);
  std::vector<std::string> list =
      family == "robust"
          ? std::vector<std::string>{"RDM-1200",  "RDM-800",  "RDM-600",
                                     "RDM-300",   "RDMN-300", "RDMN-150",
                                     "RDM-1200S", "RDM-600S", "RDM-300S",
                                     "RDMN-300S", "RDMN-150S"}
      : family == "mfsk"
          ? std::vector<std::string>{"MFSK-8", "MFSK-16", "MFSK-32", "MFSK-32R"}
          : std::vector<std::string>{"BPSK", "QPSK", "8PSK", "QAM16"};
  auto chosen = std::find(list.begin(), list.end(), settings.mode) != list.end()
                    ? settings.mode
                : family == "robust" ? "RDM-600S"
                : family == "mfsk"   ? "MFSK-16"
                                     : "QPSK";
  comboSet(MODE, list, chosen);
}
void layout(int w, int h) {
  int left = 300, right = w - left - 15;
  MoveWindow(history, left, 158, right, h - 335, TRUE);
  MoveWindow(composer, left, h - 167, right - 115, 65, TRUE);
  MoveWindow(controls[SEND], w - 120, h - 167, 105, 65, TRUE);
  MoveWindow(statusLabel, left, h - 42, right, 32, TRUE);
  for (int id : {CQ, SNR, CLOSEQSO, CUSTOM})
    MoveWindow(controls[id], left + (id - CQ) * 112, h - 95, 105, 27, TRUE);
  MoveWindow(controls[EXPORT], left + 455, h - 95, 110, 27, TRUE);
  MoveWindow(controls[ACTIVITY], left + 570, h - 95, 145, 27, TRUE);
  MoveWindow(controls[ROOMS], left + 90, 14, std::max(190, right - 490), 240,
             TRUE);
  MoveWindow(controls[NEWROOM], w - 390, 14, 200, 25, TRUE);
  MoveWindow(controls[JOIN], w - 185, 14, 170, 27, TRUE);
  MoveWindow(topicLabel, left, 49, right - 240, 22, TRUE);
  MoveWindow(frequencyLabel, 778, 86, std::max(100, w - 793), 24, TRUE);
  MoveWindow(controls[TOPIC], w - 235, 45, 70, 27, TRUE);
  MoveWindow(controls[USERS], w - 160, 45, 70, 27, TRUE);
  MoveWindow(controls[LEAVE], w - 85, 45, 70, 27, TRUE);
}
void makeUI() {
  font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
  label(L"QSO73 Windows test 3", 15, 14, 275);
  label(L"Station callsign", 15, 50);
  edit(CALL, 15, 72, 260, settings.call);
  label(L"Grid", 15, 104);
  edit(GRID, 15, 125, 260, settings.grid);
  label(L"Radio RX audio input", 15, 159);
  combo(RXDEVICE, 15, 181, 260, {}, settings.input);
  label(L"Radio TX audio output", 15, 215);
  combo(OUTPUT, 15, 237, 260, {}, settings.output);
  button(REFRESH, L"Refresh audio devices", 15, 269, 260);
  label(L"Modem family / transmit mode", 15, 309, 270);
  combo(FAMILY, 15, 331, 100, {"robust", "ofdm", "mfsk"}, settings.family);
  combo(MODE, 120, 331, 155, {}, "");
  modes();
  label(L"PTT method / TX audio %", 15, 367, 270);
  combo(PTT, 15, 390, 170, {"rigctl", "vox"}, settings.ptt);
  edit(DRIVE, 195, 390, 80, std::to_string(settings.drive));
  label(L"Radio model (bundled Hamlib)", 15, 426, 270);
  combo(RIGMODEL, 15, 450, 260, {"Select radio model"}, "Select radio model");
  label(L"CAT COM port / baud", 15, 483, 270);
  combo(CATCOM, 15, 505, 130, {}, settings.catCOM, true);
  combo(CATBAUD, 150, 505, 125,
        {"1200", "2400", "4800", "9600", "19200", "38400", "57600", "115200",
         "230400"},
        std::to_string(settings.catBaud));
  button(REFRESHRIG, L"Refresh models / COM ports", 15, 538, 260);
  label(L"F4 custom ({call}, {to}, {locator}, {snr})", 15, 578, 275);
  edit(CUSTOMTEXT, 15, 600, 260, settings.custom);
  button(SAVE, L"Save settings", 15, 636, 125);
  button(START, L"Start Modem", 150, 636, 125);
  label(L"Stop modem to change settings.", 15, 679, 275);
  label(L"Hamlib starts automatically with rigctl PTT.", 15, 702, 280);
  label(L"Conversation", 300, 18, 88);
  combo(ROOMS, 390, 14, 220, {"Radio Chat"}, "Radio Chat");
  edit(NEWROOM, 620, 14, 200, "");
  SendMessageW(controls[NEWROOM], EM_SETCUEBANNER, 0,
               (LPARAM)L"#channel or callsign");
  button(JOIN, L"Open / Join", 825, 14, 165);
  topicLabel = child(L"STATIC", L"", 0, 300, 49, 450, 22);
  button(TOPIC, L"Topic...", 765, 45, 70);
  button(USERS, L"Users...", 840, 45, 70);
  button(LEAVE, L"Leave", 915, 45, 70);
  label(L"To", 300, 86, 35);
  combo(TO, 338, 80, 180, {"QST"}, "QST", true);
  edit(FREQUENCY, 528, 80, 105, "");
  SendMessageW(controls[FREQUENCY], EM_SETCUEBANNER, 0, (LPARAM)L"MHz");
  button(SETFREQ, L"Set Frequency", 640, 80, 125);
  frequencyLabel = child(L"STATIC", L"CAT: unavailable", 0, 778, 86, 250, 24);
  child(L"BUTTON", L"Beacon", BEACON, 300, 120, 85, 25,
        BS_AUTOCHECKBOX | WS_TABSTOP);
  edit(BEACONMIN, 388, 120, 42, "5");
  label(L"min", 434, 124, 32);
  button(BEACONNOW, L"Beacon Now", 475, 119, 110);
  child(L"BUTTON", L"Announce channel", ANNOUNCE, 600, 120, 145, 25,
        BS_AUTOCHECKBOX | WS_TABSTOP);
  edit(ANNMIN, 750, 120, 42, "10");
  label(L"min", 798, 124, 32);
  history = child(L"EDIT", L"", 0, 300, 158, 680, 380,
                  ES_MULTILINE | ES_READONLY | WS_VSCROLL | ES_AUTOVSCROLL);
  composer = child(L"EDIT", L"", 0, 300, 550, 560, 65,
                   ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL | WS_TABSTOP);
  SendMessageW(composer, EM_SETLIMITTEXT, 200, 0);
  button(SEND, L"Send Packet", 870, 550, 105);
  button(CQ, L"F1 - CQ", 300, 627, 105);
  button(SNR, L"F2 - SNR", 412, 627, 105);
  button(CLOSEQSO, L"F3 - 73", 524, 627, 105);
  button(CUSTOM, L"F4 - Custom", 636, 627, 105);
  button(EXPORT, L"Export Chat", 755, 627, 110);
  button(ACTIVITY, L"Modem Activity", 870, 627, 145);
  statusLabel = child(L"STATIC", L"Offline", 0, 300, 667, 680, 32);
  rebuildRooms();
  SetTimer(win, 1, 500, nullptr);
  SetTimer(win, 2, 100, nullptr);
}
LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l) {
  if (m == WM_CREATE) {
    win = h;
    makeUI();
    return 0;
  }
  if (m == WM_SIZE && history) {
    layout(LOWORD(l), HIWORD(l));
    return 0;
  }
  if (m == WM_GETMINMAXINFO) {
    auto p = (MINMAXINFO *)l;
    p->ptMinTrackSize = {1050, 820};
    return 0;
  }
  if (m == WM_TIMER) {
    if (w == 2) {
      KillTimer(win, 2);
      try {
        refreshRig();
      } catch (const std::exception &e) {
        notify(e.what());
      }
      return 0;
    }
    pollUI();
    return 0;
  }
  if (m == WM_COMMAND) {
    int id = LOWORD(w);
    try {
      if (HIWORD(w) == CBN_SELCHANGE) {
        if (id == ROOMS) {
          int i = int(SendMessageW(controls[id], CB_GETCURSEL, 0, 0));
          if (i >= 0 && i < int(roomNames.size()))
            selectRoom(roomNames[i]);
        } else if (id == FAMILY)
          modes();
        return 0;
      }
      if (HIWORD(w) != BN_CLICKED)
        return 0;
      switch (id) {
      case START:
        if (running || engine)
          stop();
        else
          start();
        break;
      case SAVE:
        readSettings();
        notify("Portable settings saved.");
        break;
      case REFRESHRIG:
        refreshRig();
        break;
      case REFRESH:
        refreshDevices();
        break;
      case JOIN:
        joinRoom();
        break;
      case LEAVE:
        if (rooms.joined.count(rooms.selected)) {
          auto r = rooms.selected;
          if (connected && audioReady)
            sendEnvelope("leave", r, "");
          rooms.joined.erase(r);
          if (announceRoom == r)
            announceOn = false;
          saveSettings();
          selectRoom("radio");
        }
        break;
      case SEND:
        sendMessage();
        break;
      case CQ:
      case SNR:
      case CLOSEQSO:
      case CUSTOM:
        macro(id);
        break;
      case TOPIC: {
        auto t = rooms.topics[rooms.selected];
        if (prompt(L"Channel topic",
                   L"A short topic for the channel; an empty value clears it.",
                   t))
          sendEnvelope("topic", rooms.selected, t);
        break;
      }
      case USERS: {
        auto calls = rooms.users(rooms.selected, settings.call, now());
        std::string s = "Heard in last ten minutes (not confirmed online):\n\n";
        for (auto &c : calls)
          s += c + "\n";
        s += "\nEnter a callsign in Open / Join for direct chat.";
        MessageBoxW(win, wide(s).c_str(), L"Channel users", MB_OK);
        break;
      }
      case BEACONNOW:
        if (!connected || !audioReady ||
            (settings.ptt == "rigctl" && !rigReady) || now() - statusTime > 6)
          throw std::runtime_error("Connect the modem and wait for ready "
                                   "audio/PTT before beaconing.");
        if (!validGrid(settings.grid))
          throw std::runtime_error(
              "Save a valid callsign and Maidenhead grid before beaconing.");
        beaconPending = true;
        notify("Beacon requested; waits for idle modem and empty queue.");
        automation();
        break;
      case BEACON:
        beaconOn = SendMessageW(controls[id], BM_GETCHECK, 0, 0) == BST_CHECKED;
        if (beaconOn) {
          if (!validGrid(call(value(GRID)))) {
            beaconOn = false;
            SendMessageW(controls[id], BM_SETCHECK, BST_UNCHECKED, 0);
            throw std::runtime_error(
                "Enter and save a valid Maidenhead grid before beaconing.");
          }
          beaconDue = now() + minutes(BEACONMIN) * 60;
        }
        break;
      case ANNOUNCE:
        announceOn =
            SendMessageW(controls[id], BM_GETCHECK, 0, 0) == BST_CHECKED;
        announceRoom = rooms.selected;
        if (announceOn && !rooms.joined.count(announceRoom)) {
          announceOn = false;
          throw std::runtime_error("Join the channel first.");
        }
        announcementDue = now() + minutes(ANNMIN) * 60;
        break;
      case ACTIVITY:
        openActivity();
        break;
      case EXPORT:
        exportChat();
        break;
      case SETFREQ: {
        auto mhz = trim(value(FREQUENCY));
        size_t end = 0;
        double f = std::stod(mhz, &end);
        if (end != mhz.size() || !std::isfinite(f) || f < 0.1 || f > 1300)
          throw std::runtime_error(
              "Enter frequency in MHz, for example 7.105.");
        if (channelState != "idle" || settings.ptt != "rigctl")
          throw std::runtime_error(
              "Frequency setting requires idle modem and rigctl PTT.");
        std::lock_guard<std::mutex> lock(mutex);
        commands.push_back("{\"cmd\":\"rigctl\",\"command\":\"F " +
                           std::to_string(std::llround(f * 1000000)) + "\"}");
        break;
      }
      }
    } catch (const std::exception &e) {
      error(e);
    }
    return 0;
  }
  if (m == WM_CLOSE) {
    stop();
    DestroyWindow(h);
    return 0;
  }
  if (m == WM_DESTROY) {
    if (activityProcess) {
      TerminateProcess(activityProcess, 0);
      CloseHandle(activityProcess);
      activityProcess = nullptr;
    }
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(h, m, w, l);
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR, int show) {
  WSADATA data;
  WSAStartup(MAKEWORD(2, 2), &data);
  wchar_t path[32768];
  GetModuleFileNameW(nullptr, path, 32768);
  base = path;
  base = base.substr(0, base.find_last_of(L"\\/") + 1);
  loadSettings();
  job = CreateJobObjectW(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                          sizeof(limits));
  WNDCLASSW wc{};
  wc.lpfnWndProc = proc;
  wc.hInstance = instance;
  wc.lpszClassName = L"QSO73Portable";
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
  wc.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(1));
  RegisterClassW(&wc);

  auto h = CreateWindowExW(0, L"QSO73Portable",
                           (std::wstring(L"QSO73 - ") + VERSION).c_str(),
                           WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                           1100, 850, nullptr, nullptr, instance, nullptr);
  ShowWindow(h, show);
  UpdateWindow(h);
  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if (msg.message == WM_KEYDOWN && msg.wParam >= VK_F1 &&
        msg.wParam <= VK_F4) {
      SendMessageW(h, WM_COMMAND, CQ + (msg.wParam - VK_F1), 0);
      continue;
    }
    if (!IsDialogMessageW(h, &msg)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }
  CloseHandle(job);
  WSACleanup();
  return 0;
}
