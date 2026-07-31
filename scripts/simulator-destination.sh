#!/usr/bin/env bash
set -euo pipefail

available_simulator_ids="$(
  ./scripts/xcodebuild.sh \
    -project HealthMule.xcodeproj \
    -scheme HealthMule \
    -showdestinations |
    sed -nE '/platform:iOS Simulator.*name:iPhone/ s/.*id:([^,}]+).*/\1/p' |
    sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
)"

booted_simulator_ids="$(
  ./scripts/xcrun.sh simctl list devices available |
    ./scripts/parse-booted-iphone-ids.sh
)"

simulator_id="$(
  ./scripts/select-simulator-id.sh \
    "${available_simulator_ids}" \
    "${booted_simulator_ids}" \
    "${SIMULATOR_UDID:-}"
)"

echo "platform=iOS Simulator,id=${simulator_id}"
