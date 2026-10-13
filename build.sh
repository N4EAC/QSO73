#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
engine_source=vendor/modem73
bundle="${QSO73_BUNDLE_PATH:-build/QSO73.app}"
mkdir -p build/module-cache "$bundle/Contents/MacOS" "$bundle/Contents/Resources/Licenses"
# Headless engine: SwiftUI supplies the UI; no Homebrew runtime libraries.
# Avoid -march=native so the bundle is not tied to this Mac's CPU extensions.
make -B -C "$engine_source" CC="clang -mmacosx-version-min=13.0" UI_FLAGS= NCURSES_LIBS= NCURSES_PREFIX= ARCHFLAGS= HIDAPI_LIBS= HAMLIB_LIBS= CXXFLAGS='-std=c++17 -O3 -Wall -Wextra -mmacosx-version-min=13.0 -DMODEM73_VERSION="2.4.2"' -j2
cp "$engine_source/modem73" "$bundle/Contents/MacOS/modem73"
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -O -module-cache-path build/module-cache -framework SwiftUI -framework AppKit -framework AVFoundation -framework Network Sources/*.swift -o "$bundle/Contents/MacOS/QSO73"
cp Info.plist "$bundle/Contents/Info.plist"
cp Assets/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cp "$engine_source/LICENSE" "$bundle/Contents/Resources/Licenses/modem73.txt"
for library in dsp code modem; do
    cp "$engine_source/deps/aicodix/$library/LICENSE" "$bundle/Contents/Resources/Licenses/aicodix-$library.txt"
done
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/"
codesign --force --sign - --identifier org.qso73.preview.modem73 "$bundle/Contents/MacOS/modem73"
codesign --force --sign - "$bundle"
echo "Built: $(pwd)/$bundle"
