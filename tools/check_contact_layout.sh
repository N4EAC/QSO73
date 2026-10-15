#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
# Keep the real MainView; only remove its application entry point for this test.
sed 's/@main struct QSO73App/struct QSO73App/' Sources/App.swift > build/ContactLayoutApp.swift
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/module-cache -framework SwiftUI -framework AppKit -framework AVFoundation -framework Network $(rg --files Sources -g '*.swift' | rg -v '^Sources/App.swift$') build/ContactLayoutApp.swift Tests/ContactLayoutTests.swift -o build/contact-layout-tests
build/contact-layout-tests
