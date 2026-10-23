#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
FREE_CHAT_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$FREE_CHAT_TEST_DIR"' EXIT
swiftc Sources/FocusCore/*.swift Tests/FreeChatChecks.swift -o "$FREE_CHAT_TEST_DIR/free-chat-tests"
"$FREE_CHAT_TEST_DIR/free-chat-tests"
