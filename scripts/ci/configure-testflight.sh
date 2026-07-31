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
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APP_STORE_CONNECT_API_PRIVATE_KEY:?APP_STORE_CONNECT_API_PRIVATE_KEY is required}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID is required}"
: "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID is required}"
: "${GOOGLE_CLIENT_ID:?GOOGLE_CLIENT_ID is required}"
: "${GOOGLE_REDIRECT_SCHEME:?GOOGLE_REDIRECT_SCHEME is required}"

[[ "${APPLE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] ||
  fail "APPLE_TEAM_ID must be a 10-character Apple team identifier."
[[ "${APP_STORE_CONNECT_KEY_ID}" =~ ^[A-Z0-9]{10}$ ]] ||
  fail "APP_STORE_CONNECT_KEY_ID must be a 10-character key identifier."
[[ "${APP_STORE_CONNECT_ISSUER_ID}" =~ ^[0-9a-fA-F-]{36}$ ]] ||
  fail "APP_STORE_CONNECT_ISSUER_ID must be an issuer UUID."
[[ "${GOOGLE_CLIENT_ID}" =~ ^[A-Za-z0-9._-]+$ ]] ||
  fail "GOOGLE_CLIENT_ID contains unsupported xcconfig characters."
[[ "${GOOGLE_REDIRECT_SCHEME}" =~ ^[A-Za-z][A-Za-z0-9.+-]*$ ]] ||
  fail "GOOGLE_REDIRECT_SCHEME is not a valid URL scheme."
grep -Fq -- "-----BEGIN PRIVATE KEY-----" <<<"${APP_STORE_CONNECT_API_PRIVATE_KEY}" ||
  fail "APP_STORE_CONNECT_API_PRIVATE_KEY is not an App Store Connect private key."
grep -Fq -- "-----END PRIVATE KEY-----" <<<"${APP_STORE_CONNECT_API_PRIVATE_KEY}" ||
  fail "APP_STORE_CONNECT_API_PRIVATE_KEY is incomplete."

credentials_dir="${RUNNER_TEMP}/health-mule-testflight"
api_key_path="${credentials_dir}/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"

umask 077
mkdir -p "${credentials_dir}"
printf '%s\n' "${APP_STORE_CONNECT_API_PRIVATE_KEY}" >"${api_key_path}"

printf '%s\n' \
  "HEALTH_MULE_BUNDLE_IDENTIFIER = dev.uinaf.healthmule" \
  "HEALTH_MULE_DEVELOPMENT_TEAM = ${APPLE_TEAM_ID}" \
  >Config/Signing.xcconfig

printf '%s\n' \
  "GOOGLE_CLIENT_ID = ${GOOGLE_CLIENT_ID}" \
  "GOOGLE_REDIRECT_SCHEME = ${GOOGLE_REDIRECT_SCHEME}" \
  >Config/Secrets.xcconfig

printf 'APP_STORE_CONNECT_API_KEY_PATH=%s\n' "${api_key_path}" >>"${GITHUB_ENV}"
echo "Configured ephemeral TestFlight credentials."
