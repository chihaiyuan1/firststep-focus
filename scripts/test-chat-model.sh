#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
SDK=$(firststep_sdk)
BIN=$(swift build -c release --build-system native --sdk "$SDK" --show-bin-path)
CHAT_TEST=$(mktemp -d)
trap 'rm -rf "$CHAT_TEST"' EXIT
swiftc -sdk "$SDK" -I "$BIN/Modules" "$BIN"/FocusCore.build/*.o "$BIN"/FocusAI.build/*.o Sources/FocusApp/ChatModel.swift Sources/FocusApp/AIModel.swift Tests/ChatModelChecks.swift -o "$CHAT_TEST/checks"
"$CHAT_TEST/checks"
