#!/bin/zsh

set -euo pipefail

prototype_dir="${0:A:h}"
libass_prefix="$(brew --prefix libass 2>/dev/null || true)"

if [[ -z "$libass_prefix" ]]; then
  echo "libass is required. Install it with: brew install libass" >&2
  exit 1
fi

export LIBASS_PREFIX="$libass_prefix"
export DYLD_LIBRARY_PATH="$libass_prefix/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

cd "$prototype_dir"
swift run ASSRendererBoundaryPrototype
