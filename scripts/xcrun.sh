#!/usr/bin/env bash
set -euo pipefail

if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  exec xcrun "$@"
fi

for xcode_app in /Applications/Xcode.app /Applications/Xcode-*.app; do
  developer_dir="${xcode_app}/Contents/Developer"
  if [[ -x "${developer_dir}/usr/bin/xcodebuild" ]]; then
    export DEVELOPER_DIR="${developer_dir}"
    exec xcrun "$@"
  fi
done

echo "error: A full Xcode installation is required." >&2
exit 1
