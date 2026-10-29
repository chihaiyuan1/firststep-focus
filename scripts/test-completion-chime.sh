#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
# Compile only pure data generation and the preferences store; never load/play NSSound.
swiftc Sources/FocusCore/CompletionChime.swift Tests/CompletionChimeChecks.swift -o "$TEST_BIN/completion-chime-tests"
"$TEST_BIN/completion-chime-tests"
