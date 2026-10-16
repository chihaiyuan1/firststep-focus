#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
swiftc Sources/FocusCore/*.swift Tests/BlockedSitesChecks.swift -o "$TEST_BIN/blocked-sites-checks"
"$TEST_BIN/blocked-sites-checks"
