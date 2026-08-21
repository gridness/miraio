#!/bin/zsh

# THROWAWAY PROTOTYPE runner. Builds outside the repository and launches the
# macOS visual-system prototype from prototype/macos-visual-system.
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
build_dir=/tmp/miraio-visual-system-prototype-build
variant=${1:-A}
screen=${2:-catalogue}
language=${3:-EN}

xcodebuild \
  -project "${repo_dir}/miraio.xcodeproj" \
  -scheme miraio \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${build_dir}" \
  CODE_SIGNING_ALLOWED=NO \
  build

open -n "${build_dir}/Build/Products/Debug/miraio.app" \
  --args \
  --prototype-variant "${variant}" \
  --prototype-screen "${screen}" \
  --prototype-language "${language}"
