"""Verify pinned Hamlib distribution and recursive portable DLL closure."""
from pathlib import Path
import hashlib, re, subprocess, zipfile, sys
root=Path(__file__).resolve().parents[1]
package=root/'dist/QSO73-Windows'
with zipfile.ZipFile(root/'vendor/hamlib/hamlib-w64-4.7.2.zip') as official:
    count=0
    for item in official.infolist():
        if item.is_dir():continue
        relative=Path(item.filename).relative_to('hamlib-w64-4.7.2')
        assert (package/'hamlib'/relative).read_bytes()==official.read(item),relative
        count+=1
    print(f'PASS: {count} official Hamlib runtime/documentation files preserved unchanged')
for filename in ('hamlib-4.7.2.tar.gz','libusb-1.0.24.tar.bz2'):
    assert (package/'hamlib/source'/filename).read_bytes()==(root/'vendor/hamlib'/filename).read_bytes()
objdump=sys.argv[1] if len(sys.argv)>1 else 'x86_64-w64-mingw32-objdump'
system={'advapi32.dll','comdlg32.dll','gdi32.dll','iphlpapi.dll','kernel32.dll','msvcrt.dll','ole32.dll','oleaut32.dll','rpcrt4.dll','setupapi.dll','shell32.dll','user32.dll','version.dll','winmm.dll','ws2_32.dll','bcrypt.dll','crypt32.dll','winhttp.dll'}
count=0
for file in package.rglob('*'):
    if file.suffix.lower() not in ('.exe','.dll'):continue
    output=subprocess.check_output([objdump,'-p',str(file)],text=True)
    assert 'pei-x86-64' in output,file
    files={p.name.lower() for p in file.parent.iterdir()}
    for dll in re.findall(r'DLL Name:\s*(\S+)',output):
        name=dll.lower()
        assert name in files or name in system or name.startswith('api-ms-win-'),f'{file}: missing {dll}'
    count+=1
print(f'PASS: {count} Windows x64 executables/DLLs have complete adjacent/system dependency closure')
print('PASS: complete corresponding Hamlib/libusb source archives included')
