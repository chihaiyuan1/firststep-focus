#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_BIN"' EXIT
for suite in PlanningChecks TimeLinkChecks WeeklyReviewChecks HourlyFocusChecks VersionProtectionChecks; do
  swiftc Sources/FocusCore/*.swift "Tests/$suite.swift" -o "$TEST_BIN/$suite"
  "$TEST_BIN/$suite"
done
