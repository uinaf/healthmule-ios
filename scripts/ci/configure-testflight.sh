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
api_key_path="${credentials_dir}/AuthKey_${HEALTHMULE_APP_STORE_CONNECT_KEY_ID}.p8"
keychain_path="${credentials_dir}/signing.keychain-db"
original_keychains_path="${credentials_dir}/original-keychains.txt"

umask 077
mkdir -p "${credentials_dir}"
[[ ! -e "${original_keychains_path}" ]] || fail "Clean up the previous signing setup first."
security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//' >"${original_keychains_path}.tmp"
mv "${original_keychains_path}.tmp" "${original_keychains_path}"
original_keychains=()
while IFS= read -r keychain; do
  [[ -z "${keychain}" ]] || original_keychains+=("${keychain}")
done <"${original_keychains_path}"

keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "${keychain_password}" "${keychain_path}"
security set-keychain-settings -ut 3600 "${keychain_path}"
security unlock-keychain -p "${keychain_password}" "${keychain_path}"
printf '%s' "${HEALTHMULE_APPLE_DEVELOPMENT_CERTIFICATE_P12_BASE64}" | base64 --decode >"${credentials_dir}/identity.p12"
security import "${credentials_dir}/identity.p12" \
  -k "${keychain_path}" -P "${HEALTHMULE_APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD}" \
  -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "${keychain_password}" "${keychain_path}" >/dev/null
rm "${credentials_dir}/identity.p12"
security find-identity -v -p codesigning "${keychain_path}" | \
  grep -Eq "^[[:space:]]*[0-9]+\\) ${HEALTHMULE_APPLE_DEVELOPMENT_CERTIFICATE_SHA1} \"Apple Development:" ||
  fail "The configured development signing identity is missing, expired, or has no private key."
certificate_details="$(security find-certificate -c 'Apple Development:' -p "${keychain_path}" |
  openssl x509 -noout -subject -fingerprint -sha1 -nameopt sep_multiline,sname)"
grep -Eq "^[[:space:]]*OU=${HEALTHMULE_APPLE_TEAM_ID}$" <<<"${certificate_details}" ||
  fail "The pinned development certificate does not belong to the configured Apple team."
tr -d ':' <<<"${certificate_details}" |
  grep -Eiq "^sha1 Fingerprint=${HEALTHMULE_APPLE_DEVELOPMENT_CERTIFICATE_SHA1}$" ||
  fail "The imported development certificate does not match the pinned fingerprint."
security list-keychains -d user -s "${keychain_path}" "${original_keychains[@]}"
printf '%s\n' "${HEALTHMULE_APP_STORE_CONNECT_API_PRIVATE_KEY}" >"${api_key_path}"

printf '%s\n' \
  "HEALTHMULE_BUNDLE_IDENTIFIER = dev.uinaf.healthmule" \
  "HEALTHMULE_DEVELOPMENT_TEAM = ${HEALTHMULE_APPLE_TEAM_ID}" \
  >Config/Signing.xcconfig

printf '%s\n' \
  "HEALTHMULE_GOOGLE_CLIENT_ID = ${HEALTHMULE_GOOGLE_CLIENT_ID}" \
  "HEALTHMULE_GOOGLE_REDIRECT_SCHEME = ${HEALTHMULE_GOOGLE_REDIRECT_SCHEME}" \
  >Config/Secrets.xcconfig

printf 'HEALTHMULE_APP_STORE_CONNECT_API_KEY_PATH=%s\n' "${api_key_path}" >>"${GITHUB_ENV}"
printf 'HEALTHMULE_SIGNING_KEYCHAIN_PATH=%s\n' "${keychain_path}" >>"${GITHUB_ENV}"
echo "Configured ephemeral TestFlight credentials with the reusable signing identity."
