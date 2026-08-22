#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/miraio-channel-audit.XXXXXX")"
trap 'rm -rf "$scratch_directory"' EXIT

build_number="${MIRAIO_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
common_arguments=(
    -project miraio.xcodeproj
    -scheme Miraio
    -destination 'platform=macOS,arch=arm64'
    CODE_SIGNING_ALLOWED=NO
    "MIRAIO_BUILD_NUMBER=$build_number"
)

xcodebuild "${common_arguments[@]}" -configuration Homebrew -showBuildSettings > "$scratch_directory/homebrew.txt"
xcodebuild "${common_arguments[@]}" -configuration Store -showBuildSettings > "$scratch_directory/store.txt"

shared_keys=(
    ARCHS
    CODE_SIGN_ENTITLEMENTS
    CURRENT_PROJECT_VERSION
    ENABLE_APP_SANDBOX
    ENABLE_HARDENED_RUNTIME
    ENABLE_OUTGOING_NETWORK_CONNECTIONS
    MACOSX_DEPLOYMENT_TARGET
    MARKETING_VERSION
    PRODUCT_BUNDLE_IDENTIFIER
    PRODUCT_NAME
    SDKROOT
    SUPPORTED_PLATFORMS
    SWIFT_ACTIVE_COMPILATION_CONDITIONS
)

setting() {
    local key="$1"
    local file="$2"
    awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }' "$file"
}

for key in "${shared_keys[@]}"; do
    homebrew_value="$(setting "$key" "$scratch_directory/homebrew.txt")"
    store_value="$(setting "$key" "$scratch_directory/store.txt")"
    if [[ "$homebrew_value" != "$store_value" ]]; then
        echo "channel audit failed: $key differs ($homebrew_value != $store_value)" >&2
        exit 1
    fi
done

echo "Homebrew and Store product settings are equivalent"
