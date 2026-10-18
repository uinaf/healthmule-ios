#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ "${CI:-}" == "true" && "${GITHUB_ACTIONS:-}" == "true" ]] ||
  fail "TestFlight uploads may only run in GitHub Actions."

if [[ "${HEALTHMULE_XCODE_LOCKED:-}" != "1" ]]; then
  exec ./scripts/with-xcode-lock.sh "$0"
fi

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER is required}"
: "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is required}"
: "${HEALTHMULE_APPLE_TEAM_ID:?HEALTHMULE_APPLE_TEAM_ID is required}"
: "${HEALTHMULE_SIGNING_KEYCHAIN_PATH:?Signing keychain is required}"
: "${HEALTHMULE_APPLE_DEVELOPMENT_CERTIFICATE_SHA1:?Development certificate fingerprint is required}"
: "${HEALTHMULE_APP_STORE_CONNECT_API_KEY_PATH:?HEALTHMULE_APP_STORE_CONNECT_API_KEY_PATH is required}"
: "${HEALTHMULE_APP_STORE_CONNECT_ISSUER_ID:?HEALTHMULE_APP_STORE_CONNECT_ISSUER_ID is required}"
: "${HEALTHMULE_APP_STORE_CONNECT_KEY_ID:?HEALTHMULE_APP_STORE_CONNECT_KEY_ID is required}"

[[ -s "${HEALTHMULE_APP_STORE_CONNECT_API_KEY_PATH}" ]] ||
  fail "The App Store Connect private key file is missing."

security find-identity -v -p codesigning "${HEALTHMULE_SIGNING_KEYCHAIN_PATH}" | \
  grep -Eq "^[[:space:]]*[0-9]+\\) ${HEALTHMULE_APPLE_DEVELOPMENT_CERTIFICATE_SHA1} \"Apple Development:" ||
  fail "The reusable development signing identity is unavailable; refusing to create a replacement."

archive_path="${RUNNER_TEMP}/HealthMule.xcarchive"
export_path="${RUNNER_TEMP}/HealthMuleExport"
export_options_path="${RUNNER_TEMP}/HealthMuleExportOptions.plist"
build_number="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"

provisioning_options=(
  -allowProvisioningUpdates
  -authenticationKeyPath "${HEALTHMULE_APP_STORE_CONNECT_API_KEY_PATH}"
  -authenticationKeyID "${HEALTHMULE_APP_STORE_CONNECT_KEY_ID}"
  -authenticationKeyIssuerID "${HEALTHMULE_APP_STORE_CONNECT_ISSUER_ID}"
)

./scripts/generate-project.sh

./scripts/xcodebuild.sh archive \
  -hideShellScriptEnvironment \
  -project HealthMule.xcodeproj \
  -scheme HealthMule \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${archive_path}" \
  "${provisioning_options[@]}" \
  -showBuildTimingSummary \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  OTHER_CODE_SIGN_FLAGS="--keychain \"${HEALTHMULE_SIGNING_KEYCHAIN_PATH}\"" \
  DEVELOPMENT_TEAM="${HEALTHMULE_APPLE_TEAM_ID}" \
  CURRENT_PROJECT_VERSION="${build_number}"

for signed_app in \
  "${archive_path}/Products/Applications/HealthMule.app" \
  "${archive_path}/Products/Applications/HealthMule.app/Watch/HealthMuleWatch.app"; do
  certificate_prefix="${RUNNER_TEMP}/healthmule-testflight/$(basename "${signed_app}")-certificate-"
  codesign --display --extract-certificates="${certificate_prefix}" "${signed_app}" >/dev/null
  openssl x509 -inform DER -in "${certificate_prefix}0" -noout -fingerprint -sha1 |
    tr -d ':' |
    grep -Eiq "^sha1 Fingerprint=${HEALTHMULE_APPLE_DEVELOPMENT_CERTIFICATE_SHA1}$" ||
    fail "The archived app or Watch app is not signed with the pinned development certificate."
done

archive_info="${archive_path}/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "${archive_info}")"
archived_build="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "${archive_info}")"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "${archive_info}")"

plutil -create xml1 "${export_options_path}"
plutil -insert destination -string upload "${export_options_path}"
plutil -insert manageAppVersionAndBuildNumber -bool false "${export_options_path}"
plutil -insert method -string app-store-connect "${export_options_path}"
plutil -insert signingStyle -string automatic "${export_options_path}"
plutil -insert teamID -string "${HEALTHMULE_APPLE_TEAM_ID}" "${export_options_path}"
plutil -insert uploadSymbols -bool true "${export_options_path}"

./scripts/xcodebuild.sh -exportArchive \
  -hideShellScriptEnvironment \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist "${export_options_path}" \
  "${provisioning_options[@]}"

cat >>"${GITHUB_STEP_SUMMARY}" <<EOF
## TestFlight upload accepted

- Version: ${version} (${archived_build})
- Bundle ID: ${bundle_identifier}
- Commit: ${GITHUB_SHA:-unknown}

App Store Connect processing continues after this job succeeds.
EOF
