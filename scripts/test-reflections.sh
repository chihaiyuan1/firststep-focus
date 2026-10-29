#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
REFLECTION_TEST_BIN=$(mktemp -d)
trap 'rm -rf "$REFLECTION_TEST_BIN"' EXIT
swiftc Sources/FocusCore/SessionReflection.swift Tests/SessionReflectionChecks.swift -o "$REFLECTION_TEST_BIN/reflection-tests"
"$REFLECTION_TEST_BIN/reflection-tests"
