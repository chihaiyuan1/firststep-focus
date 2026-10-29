#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f Sources/FocusApp/HabitModel.swift ]; then echo 'FAIL: HabitModel feature is not implemented'; exit 1; fi
source scripts/swift-env.sh
HABIT_MODEL_SDK=$(firststep_sdk)
HABIT_MODEL_TMP=$(mktemp -d)
trap 'rm -rf "$HABIT_MODEL_TMP"' EXIT
swiftc -O -sdk "$HABIT_MODEL_SDK" -emit-library -emit-module -module-name FocusCore Sources/FocusCore/*.swift -o "$HABIT_MODEL_TMP/libFocusCore.dylib" -emit-module-path "$HABIT_MODEL_TMP/FocusCore.swiftmodule"
swiftc -O -sdk "$HABIT_MODEL_SDK" -I "$HABIT_MODEL_TMP" -L "$HABIT_MODEL_TMP" -lFocusCore -Xlinker -rpath -Xlinker "$HABIT_MODEL_TMP" Sources/FocusApp/AppModel.swift Sources/FocusApp/HabitModel.swift Sources/FocusApp/HabitReminderController.swift Tests/HabitModelChecks.swift -o "$HABIT_MODEL_TMP/checks"
"$HABIT_MODEL_TMP/checks"
