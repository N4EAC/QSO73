#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "activity_text.hpp"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <windows.h>
std::wstring unicode(const std::string &text) {
  int n = MultiByteToWideChar(CP_UTF8, 0, text.data(), int(text.size()),
                              nullptr, 0);
  std::wstring result(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, text.data(), int(text.size()), result.data(),
                      n);
  return result;
}
int wmain(int argc, wchar_t **argv) {
  if (argc != 2)
    return 1;
  SetConsoleTitleW(L"QSO73 Modem Activity - text console");
  HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE),
         input = GetStdHandle(STD_INPUT_HANDLE);
  DWORD mode = 0;
  GetConsoleMode(input, &mode);
  SetConsoleMode(input, (mode | ENABLE_WINDOW_INPUT | ENABLE_EXTENDED_FLAGS) &
                            ~(ENABLE_QUICK_EDIT_MODE | ENABLE_MOUSE_INPUT));
  CONSOLE_CURSOR_INFO cursor{1, FALSE};
  SetConsoleCursorInfo(output, &cursor);
  std::wstring snapshot = L"Waiting for QSO73 activity...";
  bool paused = false;
  int top = 0;
  while (true) {
    if (!paused) {
      std::ifstream file(std::filesystem::path(argv[1]), std::ios::binary);
      if (file) {
        std::string text((std::istreambuf_iterator<char>(file)), {});
        if (!text.empty())
          snapshot = unicode(text);
      }
    }
    CONSOLE_SCREEN_BUFFER_INFO info{};
    if (!GetConsoleScreenBufferInfo(output, &info))
      return 0;
    int width = info.srWindow.Right - info.srWindow.Left + 1,
        height = info.srWindow.Bottom - info.srWindow.Top + 1;
    if (width < 1 || height < 3) {
      Sleep(200);
      continue;
    }
    auto content = lines(snapshot, width);
    int rows = height - 2;
    top = std::clamp(top, 0, std::max(0, int(content.size()) - rows));
    std::vector<CHAR_INFO> screen(size_t(width) * height);
    for (auto &cell : screen) {
      cell.Char.UnicodeChar = L' ';
      cell.Attributes = FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE;
    }
    auto write = [&](int row, const std::wstring &line, WORD attr) {
      for (int x = 0; x < width && x < int(line.size()); x++) {
        auto &cell = screen[size_t(row) * width + x];
        cell.Char.UnicodeChar = line[x];
        cell.Attributes = attr;
      }
    };
    write(0,
          L"QSO73 Activity | PgUp/PgDn, arrows, Home/End | Space: pause | Q: "
          L"close",
          FOREGROUND_GREEN | FOREGROUND_BLUE | FOREGROUND_INTENSITY);
    for (int i = 0; i < rows && top + i < int(content.size()); i++)
      write(i + 1, content[top + i],
            FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE);
    write(height - 1,
          (paused ? L"PAUSED" : L"LIVE") + std::wstring(L" | lines ") +
              std::to_wstring(top + 1) + L"-" +
              std::to_wstring(std::min(top + rows, int(content.size()))) +
              L" / " + std::to_wstring(content.size()) +
              L" | Closing this window keeps the modem and chat running.",
          FOREGROUND_GREEN | FOREGROUND_INTENSITY);
    SMALL_RECT rectangle = info.srWindow;
    COORD dimensions{SHORT(width), SHORT(height)}, origin{0, 0};
    WriteConsoleOutputW(output, screen.data(), dimensions, origin, &rectangle);
    if (WaitForSingleObject(input, 500) == WAIT_OBJECT_0) {
      INPUT_RECORD events[64];
      DWORD count = 0;
      ReadConsoleInputW(input, events, 64, &count);
      for (DWORD i = 0; i < count; i++)
        if (events[i].EventType == KEY_EVENT &&
            events[i].Event.KeyEvent.bKeyDown) {
          auto key = events[i].Event.KeyEvent.wVirtualKeyCode;
          switch (key) {
          case 'Q':
          case VK_ESCAPE:
            return 0;
          case VK_SPACE:
            paused = !paused;
            break;
          case VK_PRIOR:
            top -= rows;
            break;
          case VK_NEXT:
            top += rows;
            break;
          case VK_UP:
            top--;
            break;
          case VK_DOWN:
            top++;
            break;
          case VK_HOME:
            top = 0;
            break;
          case VK_END:
            top = std::max(0, int(content.size()) - rows);
            break;
          }
        }
    }
  }
}
