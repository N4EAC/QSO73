#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p windows/build build/module-cache
clang -c windows/vendor/modem73-win/deps/cJSON.c -o windows/build/cJSON-native.o
clang++ -std=c++17 -O2 -Iwindows/src -Iwindows/vendor/modem73-win/deps windows/tests/protocol_test.cpp windows/build/cJSON-native.o -o windows/build/protocol-tests
windows/build/protocol-tests windows/build/windows-fixtures.hex
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/ChatRooms.swift windows/tests/MacInterop.swift -o windows/build/mac-interop
windows/build/mac-interop windows/build/windows-fixtures.hex windows/build/mac-fixtures.hex
windows/build/protocol-tests verify windows/build/mac-fixtures.hex
clang++ -std=c++17 -O2 -I windows/vendor/modem73-win -I windows/vendor/modem73-win/deps/aicodix/dsp -I windows/vendor/modem73-win/deps/aicodix/code -I windows/vendor/modem73-win/deps/aicodix/modem Tests/dsp_roundtrip.cc -o windows/build/dsp-tests
windows/build/dsp-tests > windows/build/dsp-test.log 2>&1
rg '^PASS:' windows/build/dsp-test.log
python3 windows/tests/check_phy.py

rigctld -l > windows/build/hamlib-models-test.txt
clang++ -std=c++17 -O2 -Iwindows/src -Iwindows/vendor/modem73-win/deps windows/tests/rig_settings_test.cpp windows/build/cJSON-native.o -o windows/build/rig-settings-tests
windows/build/rig-settings-tests windows/build/hamlib-models-test.txt

clang++ -std=c++17 -O2 -Iwindows/src windows/tests/activity_text_test.cpp -o windows/build/activity-text-tests
windows/build/activity-text-tests

clang++ -std=c++17 -O2 -Iwindows/src -Iwindows/vendor/modem73-win/deps windows/tests/ping_test.cpp windows/build/cJSON-native.o -o windows/build/ping-tests
windows/build/ping-tests windows/build/ping-windows.txt
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/Ping.swift Tests/PingTests.swift -o build/ping-tests
build/ping-tests windows/build/ping-windows.txt windows/build/ping-mac.txt
windows/build/ping-tests verify windows/build/ping-mac.txt

clang++ -std=c++17 -pthread Tests/DecoderControlTests.cpp windows/build/cJSON-native.o -o build/decoder-control-tests
build/decoder-control-tests

clang++ -std=c++17 -O2 -Iwindows/src -Iwindows/vendor/modem73-win/deps windows/tests/psk_reporter_test.cpp windows/build/cJSON-native.o -o windows/build/psk-reporter-tests
windows/build/psk-reporter-tests /tmp/qso73-psk-windows.bin
swiftc -swift-version 5 -module-cache-path build/module-cache -framework Network -framework Combine Sources/Protocol.swift Sources/PSKReporter.swift Tests/PSKReporterTests.swift -o build/psk-reporter-tests
build/psk-reporter-tests /tmp/qso73-psk-mac.bin
python3 Tests/check_psk_ipfix.py /tmp/qso73-psk-mac.bin /tmp/qso73-psk-windows.bin
