#!/usr/bin/env bash
set -euo pipefail

# XcodeGen mutates the project while every Xcode task shares one DerivedData
# directory. Serialize the complete generate -> select -> build/test/run unit.
lock_file="${TMPDIR:-/private/tmp}/health-mule-xcode.lock"

exec /usr/bin/lockf -k -t 180 "${lock_file}" \
  /usr/bin/env HEALTH_MULE_XCODE_LOCKED=1 "$@"
