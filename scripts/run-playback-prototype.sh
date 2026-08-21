#!/bin/zsh

# THROWAWAY PROTOTYPE runner. Builds outside the repository and launches the
# macOS playback-experience prototype from prototype/native-playback-subtitles.
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h}
build_dir=/tmp/miraio-playback-prototype

xcodebuild \
  -project "${repo_dir}/miraio.xcodeproj" \
  -scheme miraio \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${build_dir}" \
  CODE_SIGNING_ALLOWED=NO \
  build

open -n "${build_dir}/Build/Products/Debug/miraio.app"
