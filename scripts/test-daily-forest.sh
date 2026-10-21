#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc Sources/FocusCore/*.swift Tests/DailyForestChecks.swift -o "$TEST_BIN/forest-tests"
"$TEST_BIN/forest-tests"
