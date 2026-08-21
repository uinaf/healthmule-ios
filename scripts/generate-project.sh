#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

# CI pins XcodeGen because it rewrites the whole project file. A different
# locally installed version silently regenerates a different project, so the
# pinned installer owns the local path too.
pinned_version="$(
  sed -n 's/^xcodegen_version="\(.*\)"$/\1/p' scripts/install-xcodegen.sh
)"
if [[ -z "${pinned_version}" ]]; then
  echo "error: scripts/install-xcodegen.sh no longer declares a pinned version." >&2
  exit 1
fi

pinned_root="${HEALTHMULE_XCODEGEN_ROOT:-.artifacts/toolchain/xcodegen-${pinned_version}}"
pinned_binary="${pinned_root}/xcodegen/bin/xcodegen"
cache_path="${HEALTHMULE_XCODEGEN_CACHE:-.artifacts/xcodegen/project-cache.json}"

if [[ ! -x "${pinned_binary}" ]]; then
  # Only ever delete the directory this script installs, never the root itself:
  # HEALTHMULE_XCODEGEN_ROOT is operator-supplied and may be a shared cache.
  rm -rf "${pinned_root:?}/xcodegen"
  mkdir -p "${pinned_root}"
  ./scripts/install-xcodegen.sh "${pinned_root}" >/dev/null
fi

mkdir -p "$(dirname "${cache_path}")"
exec "${pinned_binary}" generate \
  --spec project.yml \
  --use-cache \
  --cache-path "${cache_path}"
