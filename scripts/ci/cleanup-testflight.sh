#!/usr/bin/env bash
set -euo pipefail

if [[ "${CI:-}" != "true" || "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "error: TestFlight cleanup may only run in GitHub Actions." >&2
  exit 1
fi

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

credentials_dir="${RUNNER_TEMP}/healthmule-testflight"
keychain_path="${credentials_dir}/signing.keychain-db"
cleanup_status=0
if [[ -f "${credentials_dir}/original-keychains.txt" ]]; then
  original_keychains=()
  while IFS= read -r keychain; do
    [[ -z "${keychain}" ]] || original_keychains+=("${keychain}")
  done <"${credentials_dir}/original-keychains.txt"
  security list-keychains -d user -s "${original_keychains[@]}" || cleanup_status=1
fi
if [[ -e "${keychain_path}" ]]; then
  security delete-keychain "${keychain_path}" || cleanup_status=1
fi

rm -rf \
  "${RUNNER_TEMP}/healthmule-testflight" \
  "${RUNNER_TEMP}/HealthMule.xcarchive" \
  "${RUNNER_TEMP}/HealthMuleExport"
rm -f \
  "${RUNNER_TEMP}/HealthMuleExportOptions.plist" \
  Config/Secrets.xcconfig \
  Config/Signing.xcconfig

echo "Removed ephemeral TestFlight credentials and build products."
exit "${cleanup_status}"
