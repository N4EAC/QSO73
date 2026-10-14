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

swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/HeardQuery.swift Tests/HeardQueryTests.swift -o build/heard-query-tests
build/heard-query-tests /tmp/qso73-heard-mac.txt
clang++ -std=c++17 -O2 -Iwindows/src -Iwindows/vendor/modem73-win/deps windows/tests/heard_query_test.cpp windows/build/cJSON-native.o -o windows/build/heard-query-tests
windows/build/heard-query-tests /tmp/qso73-heard-windows.txt /tmp/qso73-heard-mac.txt
build/heard-query-tests /tmp/qso73-heard-mac.txt /tmp/qso73-heard-windows.txt
clang++ -std=c++17 -O2 -Iwindows/src -Iwindows/vendor/modem73-win/deps windows/tests/link_safety_test.cpp windows/build/cJSON-native.o -o windows/build/link-safety-tests
windows/build/link-safety-tests /tmp/qso73-link-dns-windows.bin
swiftc -swift-version 5 -module-cache-path build/module-cache -framework Network -framework AppKit -framework Combine Sources/Protocol.swift Sources/LinkSafety.swift Tests/LinkSafetyTests.swift -o build/link-safety-tests
build/link-safety-tests /tmp/qso73-link-dns-mac.bin
cmp /tmp/qso73-link-dns-mac.bin /tmp/qso73-link-dns-windows.bin

clang++ -std=c++17 -O2 -Iwindows/vendor/modem73-win Tests/AudioMeterTests.cpp -o windows/build/audio-meter-tests
windows/build/audio-meter-tests
clang++ -std=c++17 -O2 -Iwindows/src -Iwindows/vendor/modem73-win/deps windows/tests/audio_vu_test.cpp windows/build/cJSON-native.o -o windows/build/audio-vu-tests
windows/build/audio-vu-tests

python3 windows/tests/check_ui_contract.py

clang++ -std=c++17 -O2 -Iwindows/src -Iwindows/vendor/modem73-win/deps windows/tests/contact_log_test.cpp windows/build/cJSON-native.o -o windows/build/contact-log-tests
windows/build/contact-log-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/ContactLog.swift Tests/ContactLogTests.swift -o build/contact-log-tests
build/contact-log-tests
cmp /tmp/qso73-contact-mac.adi /tmp/qso73-contact-windows.adi

python3 Tests/check_adif.py
