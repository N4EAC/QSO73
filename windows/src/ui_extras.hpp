#pragma once
void layout(int, int);
void updateContactList() {
  if (!contactList)
    return;
  SendMessageW(contactList, LB_RESETCONTENT, 0, 0);
  for (auto &c : contactRecords) {
    auto label = wide(c.start + " UTC | " + c.callsign + " | " + c.frequency +
                      " MHz | PKT");
    SendMessageW(contactList, LB_ADDSTRING, 0,
                 reinterpret_cast<LPARAM>(label.c_str()));
  }
}
void loadContacts() {
  auto file = std::filesystem::path(base + L"contacts.json");
  if (!std::filesystem::exists(file))
    return;
  try {
    std::ifstream in(file, std::ios::binary);
    if (!in)
      throw std::runtime_error("Cannot read saved contacts.");
    std::string data((std::istreambuf_iterator<char>(in)), {});
    Json j(data);
    if (!cJSON_IsArray(j.p))
      throw std::runtime_error("Invalid contact storage.");
    std::set<std::string> ids;
    cJSON *item;
    cJSON_ArrayForEach(item, j.p) {
      Json copy(cJSON_Duplicate(item, 1));
      auto c = Contact::from(copy);
      c.validate();
      if (!uuid(c.id) || !ids.insert(c.id).second)
        throw std::runtime_error("Invalid or duplicate contact record ID.");
      contactRecords.push_back(c);
    }
  } catch (const std::exception &e) {
    contactRecords.clear();
    contactLoadError = std::string(e.what()) +
                       " Saved file preserved; contact edits are disabled.";
  }
}
void saveContact(Contact record) {
  if (!contactLoadError.empty())
    throw std::runtime_error(contactLoadError);
  record.validate();
  auto next = contactRecords;
  auto found = std::find_if(next.begin(), next.end(), [&](const Contact &c) {
    return c.id == record.id;
  });
  if (found == next.end())
    next.push_back(record);
  else
    *found = record;
  Json data(cJSON_CreateArray());
  for (auto &c : next) {
    auto j = c.json();
    cJSON_AddItemToArray(data.p, j.p);
    j.p = nullptr;
  }
  auto target = base + L"contacts.json", temporary = target + L".tmp";
  std::ofstream out(std::filesystem::path(temporary), std::ios::binary);
  out << data.dump(true);
  out.flush();
  if (!out)
    throw std::runtime_error("Cannot save contact log.");
  out.close();
  if (!MoveFileExW(temporary.c_str(), target.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    throw std::runtime_error("Cannot replace contact log; original preserved.");
  contactRecords = std::move(next);
  updateContactList();
}
void changePage(int page) {
  selectedPage = page;
  for (auto &control : pageControls)
    ShowWindow(control.handle, control.page == page ? SW_SHOW : SW_HIDE);
  TabCtrl_SetCurSel(pages, page);
  InvalidateRect(pages, nullptr, TRUE);
  updateContactList();
  RECT rect;
  GetClientRect(win, &rect);
  layout(rect.right, rect.bottom);
  InvalidateRect(win, nullptr, TRUE);
}
void applyTheme() {
  for (auto &button : defaultButtonStyles) {
    SetWindowLongPtrW(
        button.first, GWL_STYLE,
        (GetWindowLongPtrW(button.first, GWL_STYLE) & ~BS_TYPEMASK) |
            (settings.theme == "CP" ? BS_OWNERDRAW
                                    : (button.second & BS_TYPEMASK)));
    InvalidateRect(button.first, nullptr, TRUE);
  }
  SendMessageW(history, EM_SETBKGNDCOLOR, 0,
               settings.theme == "CP" ? RGB(18, 12, 38) : RGB(255, 255, 255));
  renderedHistory.clear();
  showHistory();
  for (auto &control : pageControls)
    InvalidateRect(control.handle, nullptr, TRUE);
  // Include shared controls (tabs, Start/Stop and status), not just page items.
  RedrawWindow(win, nullptr, nullptr,
               RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN);
}
struct ContactEditorState {
  Contact record;
  HWND fields[12]{};
  bool done = false;
};
LRESULT CALLBACK contactProc(HWND window, UINT message, WPARAM w, LPARAM l) {
  auto state = reinterpret_cast<ContactEditorState *>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_COMMAND && state) {
    if (LOWORD(w) == IDCANCEL) {
      state->done = true;
      return 0;
    }
    if (LOWORD(w) == IDOK) {
      try {
        auto get = [&](int i) { return text(state->fields[i]); };
        auto record = state->record;
        record.callsign = get(0);
        record.station = get(1);
        record.grid = get(2);
        record.myGrid = get(3);
        record.frequency = get(4);
        record.start = get(5) + " " + get(6);
        record.end = get(7) + " " + get(8);
        record.sent = get(9);
        record.received = get(10);
        record.note = get(11);
        saveContact(record);
        state->done = true;
      } catch (const std::exception &e) {
        MessageBoxW(window, wide(e.what()).c_str(), L"Contact not saved",
                    MB_OK | MB_ICONWARNING);
      }
      return 0;
    }
  }
  if (message == WM_CLOSE && state) {
    state->done = true;
    return 0;
  }
  return DefWindowProcW(window, message, w, l);
}
void contactEditor(bool edit) {
  if (!contactLoadError.empty())
    throw std::runtime_error(contactLoadError);
  ContactEditorState state;
  if (edit) {
    auto index = SendMessageW(contactList, LB_GETCURSEL, 0, 0);
    if (index == LB_ERR)
      throw std::runtime_error("Select a saved contact to edit.");
    state.record = contactRecords.at(size_t(index));
  } else {
    state.record.id = newID();
    state.record.station = settings.call;
    state.record.myGrid = settings.grid;
    state.record.start = state.record.end = Contact::utc(std::time(nullptr));
    auto target = rooms.selected == "radio" ? call(value(TO)) : rooms.selected;
    if (target != "QST" && !target.empty() && target[0] != '#')
      state.record.callsign = target;
    if (frequencyTime > 0 && now() - frequencyTime <= 30) {
      try {
        state.record.frequency = std::to_string(std::stod(catFrequency));
      } catch (...) {
      }
    }
  }
  WNDCLASSW cls{};
  cls.lpfnWndProc = contactProc;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"QSO73ContactEditor";
  cls.hbrBackground = GetSysColorBrush(COLOR_BTNFACE);
  cls.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&cls);
  HWND dialog = CreateWindowExW(
      WS_EX_DLGMODALFRAME, cls.lpszClassName, L"ADIF Contact — UTC / PKT",
      WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, 630, 570, win,
      nullptr, cls.hInstance, nullptr);
  SetWindowLongPtrW(dialog, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(&state));
  auto make = [&](const wchar_t *type, const std::wstring &caption, int id,
                  int x, int y, int width, int height, DWORD style = 0) {
    auto h = CreateWindowExW(
        wcscmp(type, L"EDIT") == 0 ? WS_EX_CLIENTEDGE : 0, type,
        caption.c_str(), WS_CHILD | WS_VISIBLE | style, x, y, width, height,
        dialog, reinterpret_cast<HMENU>(INT_PTR(id)), cls.hInstance, nullptr);
    SendMessageW(h, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    return h;
  };
  const wchar_t *names[] = {L"Contact callsign",
                            L"Station callsign",
                            L"Contact grid (optional)",
                            L"Station grid (optional)",
                            L"Frequency MHz",
                            L"Start date UTC (YYYYMMDD)",
                            L"Start time UTC (HHMMSS)",
                            L"End date UTC (YYYYMMDD)",
                            L"End time UTC (HHMMSS)",
                            L"Report sent (optional)",
                            L"Report received (optional)",
                            L"Notes (ASCII, optional)"};
  auto &c = state.record;
  std::vector<std::string> values{c.callsign,
                                  c.station,
                                  c.grid,
                                  c.myGrid,
                                  c.frequency,
                                  c.start.substr(0, 8),
                                  c.start.substr(9),
                                  c.end.substr(0, 8),
                                  c.end.substr(9),
                                  c.sent,
                                  c.received,
                                  c.note};
  make(L"STATIC",
       L"Review actual QSO times/frequency. Mode is PKT; this does not log "
       L"beacons.",
       0, 15, 12, 590, 32);
  const int order[] = {0, 1, 2, 3, 4, -1, 5, 6, 7, 8, 9, 10, 11};
  for (int slot = 0; slot < 13; ++slot) {
    int i = order[slot], x = 15 + (slot % 2) * 300, y = 52 + (slot / 2) * 58;
    if (i < 0) {
      make(L"STATIC", L"Mode: PKT (band derived from MHz)", 0, x, y + 22, 285,
           26);
      continue;
    }
    int width = i == 11 ? 585 : 285;
    make(L"STATIC", names[i], 0, x, y, width, 20);
    state.fields[i] = make(L"EDIT", wide(values[i]), 1000 + i, x, y + 22, width,
                           26, WS_TABSTOP | ES_AUTOHSCROLL);
    SendMessageW(state.fields[i], EM_SETLIMITTEXT, 512, 0);
  }
  make(L"STATIC",
       L"Export ADIF, then sign/upload using TQSL and your LoTW "
       L"certificate/location.",
       0, 15, 458, 590, 20);
  make(L"BUTTON", L"Save Contact", IDOK, 330, 485, 130, 27,
       WS_TABSTOP | BS_DEFPUSHBUTTON);
  make(L"BUTTON", L"Cancel", IDCANCEL, 475, 485, 125, 27, WS_TABSTOP);
  EnableWindow(win, FALSE);
  ShowWindow(dialog, SW_SHOW);
  SetFocus(state.fields[0]);
  MSG msg;
  while (!state.done) {
    auto result = GetMessageW(&msg, nullptr, 0, 0);
    if (result <= 0) {
      if (!result)
        PostQuitMessage(int(msg.wParam));
      break;
    }
    if (!IsDialogMessageW(dialog, &msg)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
  }
  DestroyWindow(dialog);
  EnableWindow(win, TRUE);
  SetForegroundWindow(win);
}
void exportADIF() {
  if (contactRecords.empty())
    throw std::runtime_error("Save at least one completed contact first.");
  wchar_t path[MAX_PATH] = L"QSO73-contacts.adi";
  OPENFILENAMEW file{};
  file.lStructSize = sizeof(file);
  file.hwndOwner = win;
  file.lpstrFilter = L"ADIF logs\0*.adi\0\0";
  file.lpstrFile = path;
  file.nMaxFile = MAX_PATH;
  file.Flags = OFN_OVERWRITEPROMPT;
  file.lpstrDefExt = L"adi";
  if (GetSaveFileNameW(&file)) {
    auto data = Contact::exportADIF(contactRecords);
    std::ofstream out(std::filesystem::path(path), std::ios::binary);
    out << data;
    out.flush();
    if (!out)
      throw std::runtime_error("Cannot export ADIF.");
    MessageBoxW(win,
                L"ADIF exported. Open it in TQSL to sign and upload to LoTW.",
                L"QSO73", MB_OK);
  }
}
