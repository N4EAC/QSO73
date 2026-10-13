#include "activity_text.hpp"
#include <cassert>
#include <iostream>
int main() {
  auto wrapped = lines(L"123456789\r\n\r\nend", 4);
  assert(wrapped ==
         std::vector<std::wstring>({L"1234", L"5678", L"9", L"", L"end"}));
  auto huge = lines(std::wstring(100000, L'x'), 100);
  assert(huge.size() == 1000 && huge.front().size() == 100 &&
         huge.back().size() == 100);
  assert(lines(L"a\nb", 1) == std::vector<std::wstring>({L"a", L"b"}));
  std::cout << "PASS: console snapshot wraps 100 KB without truncation and "
               "preserves CRLF/blank lines\n";
}
