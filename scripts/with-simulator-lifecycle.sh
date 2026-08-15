#!/usr/bin/env bash
set -euo pipefail

simulator_id="${1:-}"
if [[ -z "${simulator_id}" || "$#" -lt 2 ]]; then
  echo "usage: $0 <simulator-udid> <command> [args...]" >&2
  exit 64
fi
shift

is_booted() {
  ./scripts/xcrun.sh simctl list devices available |
    ./scripts/parse-booted-iphone-ids.sh |
    grep -Fqx -- "${simulator_id}"
}

if is_booted; then
  exec "$@"
fi

if ! ./scripts/xcrun.sh simctl boot "${simulator_id}"; then
  if is_booted; then
    exec "$@"
  fi
  echo "error: Failed to boot Simulator ${simulator_id}." >&2
  exit 1
fi

simulator_owned=1
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "${simulator_owned}" == "1" ]]; then
    if ! ./scripts/xcrun.sh simctl shutdown "${simulator_id}"; then
      echo "warning: Failed to shut down owned Simulator ${simulator_id}." >&2
    fi
  fi
  exit "${status}"
}
trap cleanup EXIT

./scripts/xcrun.sh simctl bootstatus "${simulator_id}" -b
"$@"
