#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

fail() {
    echo "foundation audit failed: $*" >&2
    exit 1
}

expected_products='["Anime365Client","MiraioASSRenderer","MiraioApplication","MiraioArtwork","MiraioCredentials","MiraioDomain","MiraioPlayback","MiraioWatchHistory"]'
expected_graph='{"Anime365Client":["MiraioApplication","MiraioDomain"],"MiraioASSRenderer":["MiraioDomain","MiraioPlayback"],"MiraioApplication":["MiraioDomain"],"MiraioArtwork":["MiraioApplication","MiraioDomain"],"MiraioCredentials":["MiraioApplication","MiraioDomain"],"MiraioDomain":[],"MiraioPlayback":["MiraioApplication","MiraioDomain"],"MiraioWatchHistory":["MiraioApplication","MiraioDomain"]}'

package_description="$(swift package --disable-sandbox --package-path Packages/MiraioCore dump-package)"
actual_products="$(jq -c '[.products[].name] | sort' <<<"$package_description")"
[[ "$actual_products" == "$expected_products" ]] || fail "the shared package products changed: $actual_products"

actual_graph="$(jq -c -S '[.targets[] | select(.type == "regular") | {key: .name, value: [.dependencies[].byName[0]] | sort}] | from_entries' <<<"$package_description")"
[[ "$actual_graph" == "$expected_graph" ]] || fail "package dependencies no longer point inward: $actual_graph"

if rg -n '^import (AppKit|SwiftUI|UIKit)$|NotificationCenter|NSApplication|UIApplication' Packages/MiraioCore/Sources; then
    fail "shared targets contain platform presentation or lifecycle observation"
fi

[[ ! -e miraio/Item.swift ]] || fail "the starter Item model still exists"
if rg -n '\bItem\b|Add Item|Select an item' miraio miraioTests miraioUITests; then
    fail "starter Item behavior remains"
fi

application_products="$(rg -c 'productType = "com.apple.product-type.application"' miraio.xcodeproj/project.pbxproj)"
[[ "$application_products" == "1" ]] || fail "expected exactly one application product, found $application_products"

if rg -n 'iphoneos|iphonesimulator|xros|xrsimulator|TARGETED_DEVICE_FAMILY' miraio.xcodeproj/project.pbxproj; then
    fail "the Xcode application project still declares an iOS or xrOS destination"
fi

plutil -lint miraio/Miraio.entitlements >/dev/null
entitlement_count="$(plutil -p miraio/Miraio.entitlements | rg -c '=>')"
[[ "$entitlement_count" == "2" ]] || fail "baseline entitlements must contain exactly two capabilities"
[[ "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw miraio/Miraio.entitlements)" == "true" ]] || fail "App Sandbox is not enabled"
[[ "$(plutil -extract 'com\.apple\.security\.network\.client' raw miraio/Miraio.entitlements)" == "true" ]] || fail "outgoing network access is not enabled"

version="$(tr -d '[:space:]' < version.txt)"
configured_version="$(awk -F ' = ' '/^MIRAIO_MARKETING_VERSION = / { split($2, value, " "); print value[1] }' Configurations/Version.xcconfig)"
manifest_version="$(jq -r '.["."]' .release-please-manifest.json)"
[[ "$version" == "$configured_version" ]] || fail "version.txt and Xcode version configuration disagree"
[[ "$version" == "$manifest_version" ]] || fail "version.txt and Release Please manifest disagree"
[[ -f CHANGELOG.md ]] || fail "CHANGELOG.md is missing"

rg -q 'fetch-depth: 0' .github/workflows/ci.yml || fail "CI must fetch mainline history"
rg -q 'git rev-list --count origin/main' .github/workflows/ci.yml || fail "CI build numbers must use mainline commit count"

echo "foundation audit passed"
