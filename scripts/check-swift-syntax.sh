#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

swift_files=()
while IFS= read -r -d '' swift_file; do
  swift_files+=("${swift_file}")
done < <(
  find HealthMuleApp HealthMuleShared HealthMuleWatchApp \
    HealthMuleTests HealthMuleUITests \
    -type f \
    -name '*.swift' \
    -print0
)

if [[ "${#swift_files[@]}" -eq 0 ]]; then
  echo "error: No app or iOS test Swift sources were found." >&2
  exit 1
fi

HEALTHMULE_SWIFT_TOOL=swiftc \
  ./scripts/swift.sh -frontend -parse "${swift_files[@]}"
