#!/usr/bin/env bash
set -euo pipefail

destination="$(./scripts/simulator-destination.sh)"
simulator_id="${destination##*=}"
derived_data=".artifacts/DerivedData"

./scripts/xcrun.sh simctl boot "${simulator_id}" >/dev/null 2>&1 || true
./scripts/xcrun.sh simctl bootstatus "${simulator_id}" -b
/usr/bin/open -a Simulator --args -CurrentDeviceUDID "${simulator_id}"

./scripts/xcodebuild.sh build \
  -quiet \
  -project HealthMule.xcodeproj \
  -scheme HealthMule \
  -destination "${destination}" \
  -derivedDataPath "${derived_data}" \
  -disableAutomaticPackageResolution \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=-

app_path="$(
  find "${derived_data}/Build/Products" -path "*/Debug-iphonesimulator/HealthMule.app" -print -quit
)"

if [[ -z "${app_path}" ]]; then
  echo "error: HealthMule.app was not found after the build." >&2
  exit 1
fi

bundle_id="$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${app_path}/Info.plist"
)"
if [[ -z "${bundle_id}" ]]; then
  echo "error: HealthMule.app has no CFBundleIdentifier." >&2
  exit 1
fi

./scripts/xcrun.sh simctl install "${simulator_id}" "${app_path}"
./scripts/xcrun.sh simctl launch "${simulator_id}" "${bundle_id}"
