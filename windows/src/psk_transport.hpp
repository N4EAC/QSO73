#pragma once
#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
// Winsock is initialized by the client. DNS/UDP run away from CAT/audio work.
class PSKUploadWorker {
  std::mutex mutex;
  std::condition_variable condition;
  std::thread worker;
  bool quit = false, busy = false;
  uint64_t generation = 0;
  qso::Bytes pending;
  std::function<void(bool)> completion;
  SOCKET socket = INVALID_SOCKET;

public:
  void cancel() {
    std::lock_guard<std::mutex> lock(mutex);
    ++generation;
    pending.clear();
    busy = false;
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
    if (socket != INVALID_SOCKET) {
      closesocket(socket);
      socket = INVALID_SOCKET;
    }
  }
  ~PSKUploadWorker() { stop(); }
  void submit(qso::Bytes bytes, std::function<void(bool)> callback) {
    std::lock_guard<std::mutex> lock(mutex);
    if (busy)
      return;
    busy = true;
    pending = std::move(bytes);
    completion = std::move(callback);
    if (!worker.joinable())
      worker = std::thread([this] { run(); });
    condition.notify_one();
  }

private:
  void run() {
    for (;;) {
      qso::Bytes bytes;
      std::function<void(bool)> callback;
      uint64_t token;
      {
        std::unique_lock<std::mutex> lock(mutex);
        condition.wait(lock, [&] { return quit || !pending.empty(); });
        if (quit)
          return;
        bytes.swap(pending);
        callback = completion;
        token = generation;
      }
      auto started = std::chrono::steady_clock::now();
      addrinfo hints{};
      hints.ai_family = AF_INET;
      hints.ai_socktype = SOCK_DGRAM;
      hints.ai_protocol = IPPROTO_UDP;
      addrinfo *addresses = nullptr;
      bool resolved = getaddrinfo("report.pskreporter.info", "4739", &hints,
                                  &addresses) == 0;
      bool sent = false, current = false;
      {
        std::lock_guard<std::mutex> lock(mutex);
        current = !quit && token == generation;
        if (current && resolved &&
            std::chrono::steady_clock::now() - started <
                std::chrono::seconds(30)) {
          if (socket == INVALID_SOCKET) {
            socket = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
            if (socket != INVALID_SOCKET) {
              sockaddr_in local{};
              local.sin_family = AF_INET;
              if (bind(socket, reinterpret_cast<sockaddr *>(&local),
                       sizeof(local)) != 0) {
                closesocket(socket);
                socket = INVALID_SOCKET;
              }
            }
          }
          if (socket != INVALID_SOCKET)
            sent = sendto(socket, reinterpret_cast<const char *>(bytes.data()),
                          int(bytes.size()), 0, addresses->ai_addr,
                          int(addresses->ai_addrlen)) == int(bytes.size());
        }
        if (current)
          busy = false;
      }
      if (addresses)
        freeaddrinfo(addresses);
      if (current)
        callback(sent);
    }
  }
};
