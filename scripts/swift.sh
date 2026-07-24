#!/usr/bin/env bash
set -euo pipefail

if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  developer_dir="$(xcode-select -p)"
else
  developer_dir=""
  for xcode_app in /Applications/Xcode.app /Applications/Xcode-*.app; do
    candidate="${xcode_app}/Contents/Developer"
    if [[ -x "${candidate}/usr/bin/xcodebuild" ]]; then
      developer_dir="${candidate}"
      break
    fi
  done
fi

if [[ -z "${developer_dir}" ]]; then
  echo "error: A full Xcode installation is required." >&2
  exit 1
fi

export DEVELOPER_DIR="${developer_dir}"
module_cache="${TMPDIR:-/private/tmp}/health-relay-module-cache"
mkdir -p "${module_cache}/clang" "${module_cache}/swiftpm"
export CLANG_MODULE_CACHE_PATH="${module_cache}/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${module_cache}/swiftpm"
exec xcrun swift "$@"
