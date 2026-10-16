#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
SDK=$(firststep_sdk)
BIN=$(swift build -c release --build-system native --sdk "$SDK" --show-bin-path)
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc -sdk "$SDK" -I "$BIN/Modules" "$BIN"/FocusCore.build/*.o Sources/FocusApp/AppModel.swift Tests/AppModelChecks.swift -o "$TEST_BIN/model-tests"
"$TEST_BIN/model-tests"
