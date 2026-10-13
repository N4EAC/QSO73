#pragma once
#include <sstream>
#include <string>
#include <vector>
std::vector<std::wstring> lines(const std::wstring &text, int width) {
  std::vector<std::wstring> result;
  std::wistringstream stream(text);
  std::wstring line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == L'\r')
      line.pop_back();
    if (line.empty())
      result.push_back(L"");
    else
      for (size_t i = 0; i < line.size(); i += width)
        result.push_back(line.substr(i, width));
  }
  return result;
}
