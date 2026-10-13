#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache -framework Network Sources/Protocol.swift Sources/RigController.swift Sources/SettingsProfile.swift Sources/RadioMacros.swift Sources/Beacon.swift Tests/Modem73ProtocolTests.swift -o build/modem73-protocol-tests
build/modem73-protocol-tests
swiftc -swift-version 5 -module-cache-path build/module-cache -framework Network -framework Combine -framework AVFoundation Sources/Protocol.swift Sources/EngineInstallation.swift Sources/EmbeddedEngine.swift Sources/RigController.swift Sources/Modem.swift Sources/PSKReporter.swift Sources/Ping.swift Sources/Beacon.swift Sources/ChatRooms.swift Sources/ChannelAnnouncements.swift Sources/CallsignList.swift Sources/RigTelemetry.swift Tests/Modem73NetworkTests.swift -o build/modem73-network-tests
python3 Tests/modem73_simulator.py
clang++ -std=c++17 -O2 -I vendor/modem73 -I vendor/modem73/deps/aicodix/dsp -I vendor/modem73/deps/aicodix/code -I vendor/modem73/deps/aicodix/modem Tests/dsp_roundtrip.cc -o build/dsp-roundtrip
build/dsp-roundtrip > build/dsp-test.log 2>&1
rg '^PASS:' build/dsp-test.log
swiftc -swift-version 5 -module-cache-path build/module-cache -framework Network Sources/Protocol.swift Sources/RigController.swift Tests/RigControllerTests.swift -o build/rig-controller-tests
python3 Tests/run_rig_tests.py
clang++ -std=c++17 -O2 -I vendor/modem73 Tests/audio_route_probe.cc vendor/modem73/deps/miniaudio.o -o build/audio-route-probe
build/audio-route-probe

swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/EngineInstallation.swift Tests/EngineInstallationTests.swift -o build/engine-installation-tests
build/engine-installation-tests vendor/modem73/modem73
clang++ -std=c++17 -O2 -I vendor/modem73 Tests/ax25_metadata.cc -o build/ax25-metadata-tests
build/ax25-metadata-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/Beacon.swift Tests/BeaconTests.swift -o build/beacon-tests
build/beacon-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/ChatRooms.swift Tests/ChatRoomsTests.swift -o build/chat-rooms-tests
build/chat-rooms-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/ChatRooms.swift Sources/ChannelAnnouncements.swift Tests/ChannelAnnouncementTests.swift -o build/channel-announcement-tests
build/channel-announcement-tests
swiftc -swift-version 5 -module-cache-path build/module-cache -framework Network Sources/Protocol.swift Sources/RigController.swift Sources/RadioModels.swift Tests/RadioModelTests.swift -o build/radio-model-tests
build/radio-model-tests
python3 - <<'PY'
from pathlib import Path
Path('build/LayoutApp.swift').write_text(Path('Sources/App.swift').read_text().replace('@main struct QSO73App', 'struct QSO73App'))
PY
swiftc -swift-version 5 -module-cache-path build/module-cache -framework SwiftUI -framework AppKit -framework AVFoundation -framework Network $(rg --files Sources | rg '\.swift$' | rg -v '^Sources/App.swift$') build/LayoutApp.swift Tests/ChatLayoutTests.swift -o build/chat-layout-tests
build/chat-layout-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/RigTelemetry.swift Tests/RigTelemetryTests.swift -o build/rig-telemetry-tests
build/rig-telemetry-tests

swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Protocol.swift Sources/Ping.swift Tests/PingTests.swift -o build/ping-tests
build/ping-tests

clang -c vendor/modem73/deps/cJSON.c -o build/decoder-cJSON.o
clang++ -std=c++17 -pthread Tests/DecoderControlTests.cpp build/decoder-cJSON.o -o build/decoder-control-tests
build/decoder-control-tests

swiftc -swift-version 5 -module-cache-path build/module-cache -framework Network -framework Combine Sources/Protocol.swift Sources/PSKReporter.swift Tests/PSKReporterTests.swift -o build/psk-reporter-tests
build/psk-reporter-tests /tmp/qso73-psk-mac.bin

swiftc -swift-version 5 -module-cache-path build/module-cache -framework Network -framework Combine Sources/Protocol.swift Sources/PSKReporter.swift Tests/PSKReporterTransportTests.swift -o build/psk-transport-tests
python3 Tests/run_psk_transport.py
