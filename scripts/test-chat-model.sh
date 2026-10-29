#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
SDK=$(firststep_sdk)
CHAT_TEST=$(mktemp -d)
trap 'rm -rf "$CHAT_TEST"' EXIT
swiftc -sdk "$SDK" -emit-module -emit-library -module-name FocusCore Sources/FocusCore/*.swift -o "$CHAT_TEST/libFocusCore.dylib" -emit-module-path "$CHAT_TEST/FocusCore.swiftmodule"
swiftc -sdk "$SDK" -emit-module -emit-library -module-name FocusAI Sources/FocusAI/*.swift -o "$CHAT_TEST/libFocusAI.dylib" -emit-module-path "$CHAT_TEST/FocusAI.swiftmodule"
swiftc -sdk "$SDK" -I "$CHAT_TEST" -L "$CHAT_TEST" -lFocusCore -lFocusAI Sources/FocusApp/ChatModel.swift Sources/FocusApp/AIModel.swift Tests/ChatModelChecks.swift -o "$CHAT_TEST/checks"
"$CHAT_TEST/checks"
