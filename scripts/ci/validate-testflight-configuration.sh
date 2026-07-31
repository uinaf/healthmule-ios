#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

: "${HEALTHMULE_APPLE_TEAM_ID:?HEALTHMULE_APPLE_TEAM_ID is required}"
: "${HEALTHMULE_APP_STORE_CONNECT_API_PRIVATE_KEY:?HEALTHMULE_APP_STORE_CONNECT_API_PRIVATE_KEY is required}"
: "${HEALTHMULE_APP_STORE_CONNECT_ISSUER_ID:?HEALTHMULE_APP_STORE_CONNECT_ISSUER_ID is required}"
: "${HEALTHMULE_APP_STORE_CONNECT_KEY_ID:?HEALTHMULE_APP_STORE_CONNECT_KEY_ID is required}"
: "${HEALTHMULE_GOOGLE_CLIENT_ID:?HEALTHMULE_GOOGLE_CLIENT_ID is required}"
: "${HEALTHMULE_GOOGLE_REDIRECT_SCHEME:?HEALTHMULE_GOOGLE_REDIRECT_SCHEME is required}"

[[ "${HEALTHMULE_APPLE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] ||
  fail "HEALTHMULE_APPLE_TEAM_ID must be a 10-character Apple team identifier."
[[ "${HEALTHMULE_APP_STORE_CONNECT_KEY_ID}" =~ ^[A-Z0-9]{10}$ ]] ||
  fail "HEALTHMULE_APP_STORE_CONNECT_KEY_ID must be a 10-character key identifier."
[[ "${HEALTHMULE_APP_STORE_CONNECT_ISSUER_ID}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] ||
  fail "HEALTHMULE_APP_STORE_CONNECT_ISSUER_ID must be a canonical issuer UUID."

client_id_suffix=.apps.googleusercontent.com
[[ "${HEALTHMULE_GOOGLE_CLIENT_ID}" == ?*"${client_id_suffix}" ]] ||
  fail "HEALTHMULE_GOOGLE_CLIENT_ID must be a configured iOS OAuth client ID."
client_id_prefix="${HEALTHMULE_GOOGLE_CLIENT_ID%"${client_id_suffix}"}"
expected_redirect_scheme="com.googleusercontent.apps.${client_id_prefix}"
[[ "${HEALTHMULE_GOOGLE_REDIRECT_SCHEME}" == "${expected_redirect_scheme}" ]] ||
  fail "HEALTHMULE_GOOGLE_REDIRECT_SCHEME must be the reversed HEALTHMULE_GOOGLE_CLIENT_ID."
[[ "${HEALTHMULE_GOOGLE_REDIRECT_SCHEME}" != *-example ]] ||
  fail "HEALTHMULE_GOOGLE_REDIRECT_SCHEME must not use the example placeholder."

grep -Fq -- "-----BEGIN PRIVATE KEY-----" <<<"${HEALTHMULE_APP_STORE_CONNECT_API_PRIVATE_KEY}" ||
  fail "HEALTHMULE_APP_STORE_CONNECT_API_PRIVATE_KEY is not an App Store Connect private key."
grep -Fq -- "-----END PRIVATE KEY-----" <<<"${HEALTHMULE_APP_STORE_CONNECT_API_PRIVATE_KEY}" ||
  fail "HEALTHMULE_APP_STORE_CONNECT_API_PRIVATE_KEY is incomplete."
