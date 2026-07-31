#!/usr/bin/env bash
set -euo pipefail

if [[ "${CI:-}" != "true" || "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "error: TestFlight cleanup may only run in GitHub Actions." >&2
  exit 1
fi

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

rm -rf \
  "${RUNNER_TEMP}/health-mule-testflight" \
  "${RUNNER_TEMP}/HealthMule.xcarchive" \
  "${RUNNER_TEMP}/HealthMuleExport"
rm -f \
  "${RUNNER_TEMP}/HealthMuleExportOptions.plist" \
  Config/Secrets.xcconfig \
  Config/Signing.xcconfig

echo "Removed ephemeral TestFlight credentials and build products."
