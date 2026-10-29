#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
SDK=$(firststep_sdk)
BIN=$(swift build -c release --build-system native --sdk "$SDK" --show-bin-path)
ACTION_TEST=$(mktemp -d)
trap 'rm -rf "$ACTION_TEST"' EXIT
swiftc -sdk "$SDK" -I "$BIN/Modules" "$BIN"/FocusCore.build/*.o Sources/FocusApp/ShortcutAction.swift Sources/FocusApp/GlobalShortcuts.swift Sources/FocusApp/AppModel.swift Tests/ShortcutActionsChecks.swift -o "$ACTION_TEST/checks"
"$ACTION_TEST/checks"
