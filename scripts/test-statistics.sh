#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc Sources/FocusCore/*.swift Tests/FocusStatisticsChecks.swift -o "$TEST_BIN/statistics-tests"
"$TEST_BIN/statistics-tests"
