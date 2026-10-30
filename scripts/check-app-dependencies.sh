#!/usr/bin/env bash
set -euo pipefail

declared_file="${1:-project.yml}"
lock_file="${2:-HealthMule.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "${declared_file}" ]] ||
  fail "app dependency declaration file is missing."
[[ -f "${lock_file}" ]] ||
  fail "app dependency lock file is missing."

# Plain awk keeps `make verify` free of anything beyond Swift and POSIX tools.
declared_version="$(
  awk '
    /^[^[:space:]#]/ { in_packages = ($0 ~ /^packages:/); in_package = 0; next }
    in_packages && /^  [^[:space:]#]/ { in_package = ($0 ~ /^  GoogleSignIn:[[:space:]]*$/); next }
    in_package && /^    exactVersion:/ {
      sub(/^    exactVersion:[[:space:]]*/, ""); gsub(/["\047[:space:]]/, ""); print
    }
  ' "${declared_file}"
)"
[[ "${declared_version}" =~ ^[0-9]+(\.[0-9]+)*$ ]] ||
  fail "GoogleSignIn exactVersion is missing."

locked_version="$(
  awk '
    /"identity"[[:space:]]*:/ { in_pin = ($0 ~ /"googlesignin-ios"/) }
    in_pin && /"version"[[:space:]]*:/ {
      sub(/.*"version"[[:space:]]*:[[:space:]]*"/, ""); sub(/".*/, ""); print
    }
  ' "${lock_file}"
)"
[[ "${locked_version}" =~ ^[0-9]+(\.[0-9]+)*$ ]] ||
  fail "GoogleSignIn lock must contain exactly one versioned pin."

[[ "${declared_version}" == "${locked_version}" ]] ||
  fail "GoogleSignIn declaration and lock versions differ."

printf 'GoogleSignIn %s declaration and lock match.\n' "${declared_version}"
