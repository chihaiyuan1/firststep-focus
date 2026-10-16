#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc Sources/FocusCore/*.swift Tests/FocusCoreTests/FocusCoreTests.swift -o "$TEST_BIN/core-tests"
"$TEST_BIN/core-tests"
