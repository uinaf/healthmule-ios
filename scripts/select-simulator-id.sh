#!/usr/bin/env bash
set -euo pipefail

compatible_ids="${1:-}"
booted_ids="${2:-}"
requested_id="${3:-}"

contains_line() {
  local lines="$1"
  local candidate="$2"
  grep -Fqx -- "${candidate}" <<< "${lines}"
}

if [[ -n "${requested_id}" ]]; then
  if contains_line "${compatible_ids}" "${requested_id}"; then
    printf '%s\n' "${requested_id}"
    exit 0
  fi

  echo "error: SIMULATOR_UDID is not an available, scheme-compatible iPhone Simulator." >&2
  exit 1
fi

while IFS= read -r candidate; do
  if [[ -n "${candidate}" ]] && contains_line "${booted_ids}" "${candidate}"; then
    printf '%s\n' "${candidate}"
    exit 0
  fi
done <<< "${compatible_ids}"

fallback_id="$(printf '%s\n' "${compatible_ids}" | sed -n '/./{p;q;}')"
if [[ -z "${fallback_id}" ]]; then
  echo "error: No scheme-compatible iPhone Simulator was found." >&2
  exit 1
fi

printf '%s\n' "${fallback_id}"
