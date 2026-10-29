#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
SDK=$(firststep_sdk)
BIN=$(swift build -c release --build-system native --sdk "$SDK" --show-bin-path)
SHORTCUT_TEST=$(mktemp -d)
trap 'rm -rf "$SHORTCUT_TEST"' EXIT
swiftc -sdk "$SDK" -I "$BIN/Modules" "$BIN"/FocusCore.build/*.o Sources/FocusApp/ShortcutAction.swift Sources/FocusApp/GlobalShortcuts.swift Tests/ShortcutChecks.swift -o "$SHORTCUT_TEST/checks"
"$SHORTCUT_TEST/checks"
