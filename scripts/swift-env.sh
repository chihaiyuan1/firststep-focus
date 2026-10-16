#!/bin/bash
# Select the active SDK; FIRSTSTEP_SWIFT_SDK can override it for development.
firststep_sdk() {
    local selected_sdk
    selected_sdk="${FIRSTSTEP_SWIFT_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
    if [[ -d "$selected_sdk" ]]; then selected_sdk="$(cd "$selected_sdk" && pwd -P)"; fi
    # Some standalone Swift 6.4 CLT installations ship an SDK 27 without SwiftUI macros.
    # Prefer a compatible sibling SDK only in that specific installation layout.
    if [[ -z "${FIRSTSTEP_SWIFT_SDK:-}" && "$selected_sdk" == *MacOSX27* && -d "$(dirname "$selected_sdk")/MacOSX26.5.sdk" ]]; then
        selected_sdk="$(dirname "$selected_sdk")/MacOSX26.5.sdk"
    fi
    if [[ ! -d "$selected_sdk" ]]; then
        printf 'macOS SDK not found: %s\n' "$selected_sdk" >&2
        return 1
    fi
    printf '%s\n' "$selected_sdk"
}
