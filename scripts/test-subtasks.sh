#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc Sources/FocusCore/*.swift Tests/SubtaskChecks.swift -o "$TEST_BIN/subtasks"
"$TEST_BIN/subtasks"
