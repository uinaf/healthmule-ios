#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ "${CI:-}" == "true" && "${GITHUB_ACTIONS:-}" == "true" ]] ||
  fail "TestFlight credentials may only be configured in GitHub Actions."

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"

./scripts/ci/validate-testflight-configuration.sh

credentials_dir="${RUNNER_TEMP}/healthmule-testflight"
api_key_path="${credentials_dir}/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"

umask 077
mkdir -p "${credentials_dir}"
printf '%s\n' "${APP_STORE_CONNECT_API_PRIVATE_KEY}" >"${api_key_path}"

printf '%s\n' \
  "HEALTHMULE_BUNDLE_IDENTIFIER = dev.uinaf.healthmule" \
  "HEALTHMULE_DEVELOPMENT_TEAM = ${APPLE_TEAM_ID}" \
  >Config/Signing.xcconfig

printf '%s\n' \
  "GOOGLE_CLIENT_ID = ${GOOGLE_CLIENT_ID}" \
  "GOOGLE_REDIRECT_SCHEME = ${GOOGLE_REDIRECT_SCHEME}" \
  >Config/Secrets.xcconfig

printf 'APP_STORE_CONNECT_API_KEY_PATH=%s\n' "${api_key_path}" >>"${GITHUB_ENV}"
echo "Configured ephemeral TestFlight credentials."
