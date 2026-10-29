#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
SDK=$(firststep_sdk)
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc -sdk "$SDK" -parse-as-library -whole-module-optimization -emit-module -emit-object -module-name FocusCore Sources/FocusCore/*.swift -emit-module-path "$TEST_BIN/FocusCore.swiftmodule" -o "$TEST_BIN/FocusCore.o"
swiftc -sdk "$SDK" -I "$TEST_BIN" "$TEST_BIN/FocusCore.o" Sources/FocusApp/AppModel.swift Tests/ReflectionModelChecks.swift -o "$TEST_BIN/reflection-model"
"$TEST_BIN/reflection-model"
