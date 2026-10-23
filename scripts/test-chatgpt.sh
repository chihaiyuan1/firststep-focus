#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
CHATGPT_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$CHATGPT_TEST_DIR"' EXIT
swiftc -sdk "$(firststep_sdk)" -target "$(uname -m)-apple-macosx13.0" Sources/FocusAI/*.swift Tests/ChatGPTChecks.swift -o "$CHATGPT_TEST_DIR/chatgpt-checks"
"$CHATGPT_TEST_DIR/chatgpt-checks"
