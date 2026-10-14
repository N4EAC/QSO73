#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
CXX=${CXX:-x86_64-w64-mingw32-g++}
CC=${CC:-x86_64-w64-mingw32-gcc}
WINDRES=${WINDRES:-x86_64-w64-mingw32-windres}
mkdir -p build dist/QSO73-Windows/engine dist/QSO73-Windows/licenses
make -C vendor/modem73-win -j2 CXX="$CXX" CC="$CC" WINDRES="$WINDRES" UI_FLAGS= VERSION=2.4.2
"$CC" -O2 -c vendor/modem73-win/deps/cJSON.c -o build/cJSON.o
"$WINDRES" assets/QSO73.rc -o build/QSO73-res.o
"$CXX" -std=c++17 -O2 -Wall -Wextra -static -municode -mwindows -Isrc -Ivendor/modem73-win/deps src/main.cpp build/cJSON.o build/QSO73-res.o -lwinhttp -lws2_32 -lole32 -lcomdlg32 -lgdi32 -o dist/QSO73-Windows/QSO73.exe
# Verify and unpack the pinned official Hamlib package, including adjacent DLLs.
(cd vendor/hamlib && sha256sum -c SHA256SUMS.txt)
mkdir -p build/hamlib dist/QSO73-Windows/hamlib/source
unzip -q -o vendor/hamlib/hamlib-w64-4.7.2.zip -d build/hamlib
cp -R build/hamlib/hamlib-w64-4.7.2/. dist/QSO73-Windows/hamlib/
cp vendor/hamlib/hamlib-4.7.2.tar.gz vendor/hamlib/libusb-1.0.24.tar.bz2 dist/QSO73-Windows/hamlib/source/
cp vendor/hamlib/SHA256SUMS.txt dist/QSO73-Windows/hamlib/source/
printf 'Hamlib 4.7.2 official Windows binaries, unchanged. Corresponding Hamlib and libusb source archives are included here. Hamlib build instructions: unpack hamlib-4.7.2.tar.gz and see README.w64 and INSTALL. libusb DLL version: 1.0.24.11584. No PATH modification or system installation is required.\n' > dist/QSO73-Windows/hamlib/source/README.txt
"$CXX" -std=c++17 -O2 -Wall -Wextra -static -municode src/activity-console.cpp -o dist/QSO73-Windows/QSO73-Activity.exe
cp vendor/modem73-win/modem73.exe dist/QSO73-Windows/engine/
mkdir -p dist/QSO73-Windows/docs
cp README.md dist/QSO73-Windows/START-HERE.md
if [[ -f ../USER_MANUAL.md ]]; then cp ../USER_MANUAL.md dist/QSO73-Windows/docs/; fi
if [[ -f ../docs/QSO73-User-Manual.pdf ]]; then
    cp ../docs/QSO73-User-Manual.pdf dist/QSO73-Windows/docs/
elif [[ -f ../output/pdf/QSO73-User-Manual.pdf ]]; then
    cp ../output/pdf/QSO73-User-Manual.pdf dist/QSO73-Windows/docs/
fi
cp TEST_RESULTS.md dist/QSO73-Windows/TEST_RESULTS.md
cp ../CHAT_PROTOCOL.md dist/QSO73-Windows/
cp THIRD_PARTY_NOTICES.md dist/QSO73-Windows/
cp licenses/* dist/QSO73-Windows/licenses/
cp vendor/modem73-win/LICENSE dist/QSO73-Windows/licenses/modem73-win.txt
for lib in code dsp modem; do cp "vendor/modem73-win/deps/aicodix/$lib/LICENSE" "dist/QSO73-Windows/licenses/aicodix-$lib.txt"; done
cp vendor/modem73-win/deps/hidapi/LICENSE* dist/QSO73-Windows/licenses/ 2>/dev/null || true
cp vendor/modem73-win/deps/miniaudio.h dist/QSO73-Windows/licenses/miniaudio-source-and-license.h
cp vendor/modem73-win/deps/cJSON.h dist/QSO73-Windows/licenses/cJSON-source-and-license.h
printf 'QSO73 Windows test 8\nHamlib: official Windows x64 4.7.2, bundled CAT lifecycle\nmodem73-win: ed2a06b21ae2f2eef57e75dcf65013c298da7d6f + QSO73 shutdown, AX.25 sender metadata and UTF-8 manifest patches\n' > dist/QSO73-Windows/BUILD.txt
if command -v zip >/dev/null; then # Archive only distributable files, never portable settings or test logs.
    package_tmp=$(mktemp -d)
    mkdir -p "$package_tmp/QSO73-Windows"
    cp -R dist/QSO73-Windows/{QSO73.exe,QSO73-Activity.exe,engine,hamlib,licenses,docs,START-HERE.md,CHAT_PROTOCOL.md,THIRD_PARTY_NOTICES.md,TEST_RESULTS.md,BUILD.txt} "$package_tmp/QSO73-Windows/"
    (cd "$package_tmp" && zip -q -r QSO73-0.4.12-windows-x64-test8.zip QSO73-Windows)
    mv "$package_tmp/QSO73-0.4.12-windows-x64-test8.zip" dist/
    rm -rf "$package_tmp"; fi
printf 'Portable folder: %s/dist/QSO73-Windows\n' "$PWD"
