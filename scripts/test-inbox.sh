#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc Sources/FocusCore/*.swift Tests/InboxChecks.swift -o "$TEST_BIN/inbox-checks"
"$TEST_BIN/inbox-checks"
