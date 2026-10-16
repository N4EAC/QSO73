"""Catch misplaced owner-draw flags and startup overlap in the Windows UI."""
from pathlib import Path
import re
source=(Path(__file__).resolve().parents[1]/'src/main.cpp').read_text()
for name,identifier in [('rxVULabel','RXVU'),('txVULabel','TXVU'),('decodingLabel','DECODINGINDICATOR')]:
    match=re.search(r'\b'+name+r'\s*=\s*child\(([^;]+)\);',source)
    assert match,name
    args=[arg.strip() for arg in match[1].split(',')]
    assert len(args)==8 and args[2]==identifier and args[7]=='SS_OWNERDRAW', (name,args)
    if name!='decodingLabel': assert int(args[4])+int(args[6])<=226,name
history=re.search(r'history\s*=\s*child\(MSFTEDIT_CLASS,\s*L"",\s*CHATLOG,\s*300,\s*(\d+)',source)
assert history and int(history[1])>=226,'Transcript overlaps audio meter row on creation'
print('PASS: RX/TX VUs and Decoding request owner drawing with unique IDs; initial transcript leaves meter row visible')

assert 'SetConsoleCtrlHandler(ignoreChildShutdown, TRUE)' in source
assert 'return event == CTRL_C_EVENT || event == CTRL_BREAK_EVENT' in source
assert 'SetConsoleCtrlHandler(nullptr, TRUE)' not in source
assert 'TCN_SELCHANGE' in source and 'changePage(TabCtrl_GetCurSel(pages))' in source
assert 'BS_GROUPBOX' in source and 'Radio frequency' in source
extra=(Path(__file__).resolve().parents[1]/'src/ui_extras.hpp').read_text()
assert 'GetWindowLongPtrW(button.first,GWL_STYLE)&~BS_TYPEMASK' in re.sub(r'\s+', '', extra)
print('PASS: separate UI pages, frequency group, console-break protection and theme changes preserve control visibility')

assert 'CP = Cyberpunk' not in source
assert 'SetWindowSubclass(pages, tabThemeProc, 1, 0)' in source
assert 'WM_PRINTCLIENT' in source and 'DefSubclassProc(tab, message, w, l)' in source
assert 'TabCtrl_GetItemRect(tab, i, &draw.rcItem)' in source
assert 'RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN' in extra
assert 'InvalidateRect(pages, nullptr, TRUE)' in extra
print('PASS: CP tabs paint the entire strip; theme and selection refresh shared tabs; caption removed')

contact=extra.split('LRESULT CALLBACK contactProc(',1)[1].split('void contactEditor(',1)[0]
for message in ['WM_ERASEBKGND','WM_CTLCOLORSTATIC','WM_CTLCOLOREDIT','WM_CTLCOLORBTN','WM_DRAWITEM']:
    assert message in contact, message
assert 'return proc(window, message, w, l)' in contact
assert 'style = (style & ~BS_TYPEMASK) | BS_OWNERDRAW' in extra
print('PASS: contact dialog inherits CP surface, fields, labels and button rendering')

assert '{"Default", "CP", "Crimson"}' in source
assert 'L"Contacts"' in source and 'DIRECTORYLIST' in source and 'FAVORITELIST' in source
assert 'isCustomTheme()' in contact
print('PASS: Crimson uses shared contact rendering; separate directory and favorites controls are created')
