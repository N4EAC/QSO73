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
