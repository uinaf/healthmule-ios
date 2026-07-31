#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

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
[[ "${APP_STORE_CONNECT_ISSUER_ID}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] ||
  fail "APP_STORE_CONNECT_ISSUER_ID must be a canonical issuer UUID."

client_id_suffix=.apps.googleusercontent.com
[[ "${GOOGLE_CLIENT_ID}" == ?*"${client_id_suffix}" ]] ||
  fail "GOOGLE_CLIENT_ID must be a configured iOS OAuth client ID."
client_id_prefix="${GOOGLE_CLIENT_ID%"${client_id_suffix}"}"
expected_redirect_scheme="com.googleusercontent.apps.${client_id_prefix}"
[[ "${GOOGLE_REDIRECT_SCHEME}" == "${expected_redirect_scheme}" ]] ||
  fail "GOOGLE_REDIRECT_SCHEME must be the reversed GOOGLE_CLIENT_ID."
[[ "${GOOGLE_REDIRECT_SCHEME}" != *-example ]] ||
  fail "GOOGLE_REDIRECT_SCHEME must not use the example placeholder."

grep -Fq -- "-----BEGIN PRIVATE KEY-----" <<<"${APP_STORE_CONNECT_API_PRIVATE_KEY}" ||
  fail "APP_STORE_CONNECT_API_PRIVATE_KEY is not an App Store Connect private key."
grep -Fq -- "-----END PRIVATE KEY-----" <<<"${APP_STORE_CONNECT_API_PRIVATE_KEY}" ||
  fail "APP_STORE_CONNECT_API_PRIVATE_KEY is incomplete."
