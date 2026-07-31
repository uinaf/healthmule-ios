#!/usr/bin/env bash
set -euo pipefail

declared_file="${1:-project.yml}"
lock_file="${2:-HealthRelay.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "${declared_file}" ]] ||
  fail "app dependency declaration file is missing."
[[ -f "${lock_file}" ]] ||
  fail "app dependency lock file is missing."

declared_version="$(
  /usr/bin/ruby -ryaml -e '
    path = ARGV.fetch(0)
    yaml = File.read(path)
    supports_keywords = YAML.method(:safe_load).parameters.any? do |kind, _|
      kind == :key
    end
    document =
      if supports_keywords
        YAML.safe_load(
          yaml,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false,
          filename: path
        )
      else
        YAML.safe_load(yaml, [], [], false, path)
      end
    package = document.fetch("packages", {}).fetch("GoogleSignIn", nil)
    version = package.is_a?(Hash) ? package["exactVersion"] : nil
    abort "missing" unless version.is_a?(String) && !version.empty?
    puts version
  ' "${declared_file}" 2>/dev/null
)" || fail "GoogleSignIn exactVersion is missing."

locked_version="$(
  /usr/bin/ruby -rjson -e '
    document = JSON.parse(File.read(ARGV.fetch(0)))
    pins = document.fetch("pins", []).select do |pin|
      pin["identity"] == "googlesignin-ios"
    end
    abort "invalid-count" unless pins.length == 1
    version = pins.first.fetch("state", {})["version"]
    abort "missing-version" unless version.is_a?(String) && !version.empty?
    puts version
  ' "${lock_file}" 2>/dev/null
)" || fail "GoogleSignIn lock must contain exactly one versioned pin."

[[ "${declared_version}" == "${locked_version}" ]] ||
  fail "GoogleSignIn declaration and lock versions differ."

if [[ "${APP_DEPENDENCY_PRINT_VERSION:-0}" == "1" ]]; then
  printf '%s\n' "${declared_version}"
else
  printf 'GoogleSignIn %s declaration and lock match.\n' "${declared_version}"
fi
