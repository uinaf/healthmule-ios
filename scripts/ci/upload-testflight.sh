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
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APP_STORE_CONNECT_API_KEY_PATH:?APP_STORE_CONNECT_API_KEY_PATH is required}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID is required}"
: "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID is required}"

[[ -s "${APP_STORE_CONNECT_API_KEY_PATH}" ]] ||
  fail "The App Store Connect private key file is missing."

archive_path="${RUNNER_TEMP}/HealthMule.xcarchive"
export_path="${RUNNER_TEMP}/HealthMuleExport"
export_options_path="${RUNNER_TEMP}/HealthMuleExportOptions.plist"
build_number="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"

./scripts/generate-project.sh

./scripts/xcodebuild.sh archive \
  -hideShellScriptEnvironment \
  -project HealthMule.xcodeproj \
  -scheme HealthMule \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${archive_path}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${APP_STORE_CONNECT_API_KEY_PATH}" \
  -authenticationKeyID "${APP_STORE_CONNECT_KEY_ID}" \
  -authenticationKeyIssuerID "${APP_STORE_CONNECT_ISSUER_ID}" \
  -showBuildTimingSummary \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
  CURRENT_PROJECT_VERSION="${build_number}"

archive_info="${archive_path}/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "${archive_info}")"
archived_build="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "${archive_info}")"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "${archive_info}")"

plutil -create xml1 "${export_options_path}"
plutil -insert destination -string upload "${export_options_path}"
plutil -insert manageAppVersionAndBuildNumber -bool false "${export_options_path}"
plutil -insert method -string app-store-connect "${export_options_path}"
plutil -insert signingStyle -string automatic "${export_options_path}"
plutil -insert teamID -string "${APPLE_TEAM_ID}" "${export_options_path}"
plutil -insert uploadSymbols -bool true "${export_options_path}"

./scripts/xcodebuild.sh -exportArchive \
  -hideShellScriptEnvironment \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist "${export_options_path}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${APP_STORE_CONNECT_API_KEY_PATH}" \
  -authenticationKeyID "${APP_STORE_CONNECT_KEY_ID}" \
  -authenticationKeyIssuerID "${APP_STORE_CONNECT_ISSUER_ID}"

{
  echo "## TestFlight upload accepted"
  echo
  echo "- Version: ${version} (${archived_build})"
  echo "- Bundle ID: ${bundle_identifier}"
  echo "- Commit: ${GITHUB_SHA:-unknown}"
  echo
  echo "App Store Connect processing continues after this job succeeds."
} >>"${GITHUB_STEP_SUMMARY}"
