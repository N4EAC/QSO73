#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
sed 's/@main struct QSO73App/struct QSO73App/' Sources/App.swift > build/ChatScrollApp.swift
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path build/module-cache -framework SwiftUI -framework AppKit -framework AVFoundation -framework Network $(rg --files Sources -g '*.swift' | rg -v '^Sources/App.swift$') build/ChatScrollApp.swift Tests/ChatScrollTests.swift -o build/chat-scroll-tests
build/chat-scroll-tests
