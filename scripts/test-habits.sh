#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
HABIT_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$HABIT_TEST_DIR"' EXIT
swiftc Sources/FocusCore/Habit.swift Sources/FocusCore/HabitReminder.swift Sources/FocusCore/HabitStore.swift Tests/HabitChecks.swift -o "$HABIT_TEST_DIR/habit-tests"
"$HABIT_TEST_DIR/habit-tests"
