"""Confirm the two pinned engines use identical PHY and fragmentation code."""
from pathlib import Path
root=Path(__file__).resolve().parents[2]
a=root/'vendor/modem73'; b=root/'windows/vendor/modem73-win'
files=[p.relative_to(a) for directory in ('phy','deps/aicodix') for p in (a/directory).rglob('*') if p.is_file() and p.suffix in ('.hh','.h','.cc')]
# Fragmenter/Reassembler live in kiss_tnc.hh, which also includes OS-specific config.
for file in files:
    assert (b/file).read_bytes()==(a/file).read_bytes(),f'PHY differs: {file}'
def fragment_code(path):
    text=path.read_text(); return text[text.index('namespace Frag'):]
assert fragment_code(a/'kiss_tnc.hh')==fragment_code(b/'kiss_tnc.hh')
print(f'PASS: {len(files)} PHY/DSP files and fragmentation definitions match the Mac engine')
