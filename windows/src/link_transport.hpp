#pragma once
#include "link_safety.hpp"
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
#include <winhttp.h>
class LinkCheckWorker {
  std::mutex mutex;
  std::condition_variable condition;
  std::thread worker;
  bool quit = false;
  uint64_t generation = 0;
  std::string pending;
  std::function<void(std::string, std::string)> completion;
  struct Handle {
    HINTERNET value;
    ~Handle() {
      if (value)
        WinHttpCloseHandle(value);
    }
  };
  static qso::Bytes fetch(const wchar_t *host, const std::wstring &path) {
    Handle session{
        WinHttpOpen(L"QSO73 link safety", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0)};
    if (!session.value)
      throw std::runtime_error("Security check could not start.");
    WinHttpSetTimeouts(session.value, 3000, 3000, 3000, 3000);
    DWORD protocols = WINHTTP_PROTOCOL_FLAG_HTTP2;
    WinHttpSetOption(session.value, WINHTTP_OPTION_ENABLE_HTTP_PROTOCOL,
                     &protocols, sizeof(protocols));
    Handle connection{
        WinHttpConnect(session.value, host, INTERNET_DEFAULT_HTTPS_PORT, 0)};
    Handle request{connection.value
                       ? WinHttpOpenRequest(
                             connection.value, L"GET", path.c_str(), nullptr,
                             WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                             WINHTTP_FLAG_SECURE)
                       : nullptr};
    if (!request.value)
      throw std::runtime_error("Security service unavailable.");
    DWORD disabled = WINHTTP_DISABLE_REDIRECTS;
    WinHttpSetOption(request.value, WINHTTP_OPTION_DISABLE_FEATURE, &disabled,
                     sizeof(disabled));
    if (!WinHttpSendRequest(request.value,
                            L"Accept: application/dns-message\r\n", -1,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(request.value, nullptr))
      throw std::runtime_error(
          "Online security check failed. Link not opened.");
    DWORD code = 0, size = sizeof(code);
    if (!WinHttpQueryHeaders(request.value,
                             WINHTTP_QUERY_STATUS_CODE |
                                 WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &code, &size,
                             WINHTTP_NO_HEADER_INDEX) ||
        code != 200)
      throw std::runtime_error(
          "Security service unavailable. Link not opened.");
    wchar_t content[256]{};
    size = sizeof(content);
    if (!WinHttpQueryHeaders(request.value, WINHTTP_QUERY_CONTENT_TYPE,
                             WINHTTP_HEADER_NAME_BY_INDEX, content, &size,
                             WINHTTP_NO_HEADER_INDEX) ||
        std::wstring(content).rfind(L"application/dns-message", 0))
      throw std::runtime_error("Invalid security response.");
    qso::Bytes body;
    for (;;) {
      uint8_t buffer[1024];
      DWORD count = 0;
      if (!WinHttpReadData(request.value, buffer, sizeof(buffer), &count))
        throw std::runtime_error("Security response failed.");
      if (!count)
        break;
      if (body.size() + count > 4096)
        throw std::runtime_error("Security response too large.");
      body.insert(body.end(), buffer, buffer + count);
    }
    return body;
  }

public:
  void cancel() {
    std::lock_guard<std::mutex> lock(mutex);
    ++generation;
    pending.clear();
  }
  void stop() {
    {
      std::lock_guard<std::mutex> lock(mutex);
      quit = true;
      ++generation;
    }
    condition.notify_all();
    if (worker.joinable())
      worker.join();
  }
  ~LinkCheckWorker() { stop(); }
  void check(std::string raw,
             std::function<void(std::string, std::string)> callback) {
    std::lock_guard<std::mutex> lock(mutex);
    ++generation;
    pending = std::move(raw);
    completion = std::move(callback);
    if (!worker.joinable())
      worker = std::thread([this] { run(); });
    condition.notify_one();
  }

private:
  void run() {
    for (;;) {
      std::string raw;
      std::function<void(std::string, std::string)> callback;
      uint64_t token;
      {
        std::unique_lock<std::mutex> lock(mutex);
        condition.wait(lock, [&] { return quit || !pending.empty(); });
        if (quit)
          return;
        raw.swap(pending);
        callback = completion;
        token = generation;
      }
      std::string error, allowed;
      try {
        qso::CheckedLink link(raw);
        for (auto host : {L"security.cloudflare-dns.com", L"dns.quad9.net"}) {
          bool resolved = false;
          for (uint16_t type : {1, 28}) {
            {
              std::lock_guard<std::mutex> lock(mutex);
              if (quit || token != generation)
                throw std::runtime_error("Canceled");
            }
            auto q = qso::DNSLinkCheck::base64URL(
                qso::DNSLinkCheck::query(link.host, type));
            std::wstring path =
                L"/dns-query?dns=" + std::wstring(q.begin(), q.end());
            bool found =
                qso::DNSLinkCheck::response(fetch(host, path), link.host, type);
            resolved = resolved || found;
          }
          if (!resolved)
            throw std::runtime_error("Domain could not be resolved by the "
                                     "security service. Link not opened.");
        }
        allowed = link.url;
      } catch (const std::exception &e) {
        error = e.what();
      }
      bool current;
      {
        std::lock_guard<std::mutex> lock(mutex);
        current = !quit && token == generation;
      }
      if (current)
        callback(allowed, error);
    }
  }
};
