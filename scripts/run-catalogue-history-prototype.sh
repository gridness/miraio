#!/bin/zsh

# THROWAWAY PROTOTYPE runner. Builds outside the repository and launches the
# macOS Catalogue/Watch History IA prototype from
# prototype/catalogue-watch-history-ia.
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
build_dir=/tmp/miraio-catalogue-history-prototype
variant=${1:-A}
scenario=${2:-catalogue}

xcodebuild \
  -project "${repo_dir}/miraio.xcodeproj" \
  -scheme miraio \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${build_dir}" \
  CODE_SIGNING_ALLOWED=NO \
  build

open -n "${build_dir}/Build/Products/Debug/miraio.app" \
  --args --prototype-variant "${variant}" --prototype-scenario "${scenario}"
