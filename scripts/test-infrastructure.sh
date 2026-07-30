#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

for task in project build test smoke run; do
  expected="./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh ${task}"
  actual="$(make --no-print-directory --dry-run "${task}")"
  [[ "${actual}" == "${expected}" ]] ||
    fail "make ${task} must run exactly one complete task behind the Xcode lock."
done

for script in \
  scripts/check-swift-syntax.sh \
  scripts/check-app-dependencies.sh \
  scripts/install-xcodegen.sh \
  scripts/ios-project-task.sh \
  scripts/parse-booted-iphone-ids.sh \
  scripts/run-simulator.sh \
  scripts/select-simulator-id.sh \
  scripts/simulator-destination.sh \
  scripts/swift.sh \
  scripts/with-xcode-lock.sh; do
  /bin/bash -n "${script}"
done

./scripts/check-app-dependencies.sh

dependency_fixture_dir="$(
  mktemp -d "${TMPDIR:-/tmp}/health-relay-dependencies.XXXXXX"
)"
trap 'rm -rf "${dependency_fixture_dir}"' EXIT
declared_fixture="${dependency_fixture_dir}/project.yml"
lock_fixture="${dependency_fixture_dir}/Package.resolved"

write_declared_fixture() {
  version="${1:-}"
  if [[ -n "${version}" ]]; then
    cat >"${declared_fixture}" <<EOF
packages:
  GoogleSignIn:
    url: https://github.com/google/GoogleSignIn-iOS
    exactVersion: ${version}
EOF
  else
    cat >"${declared_fixture}" <<'EOF'
packages:
  HealthRelayCore:
    path: .
EOF
  fi
}

write_lock_fixture() {
  first_version="${1:-}"
  second_version="${2:-}"
  {
    printf '{"pins":['
    if [[ -n "${first_version}" ]]; then
      printf '{"identity":"googlesignin-ios","state":{"version":"%s"}}' \
        "${first_version}"
    fi
    if [[ -n "${second_version}" ]]; then
      printf ',{"identity":"googlesignin-ios","state":{"version":"%s"}}' \
        "${second_version}"
    fi
    printf ']}\n'
  } >"${lock_fixture}"
}

write_declared_fixture "9.2.0"
write_lock_fixture "9.2.0"
./scripts/check-app-dependencies.sh \
  "${declared_fixture}" \
  "${lock_fixture}" >/dev/null

write_lock_fixture "9.1.0"
if ./scripts/check-app-dependencies.sh \
  "${declared_fixture}" \
  "${lock_fixture}" >/dev/null 2>&1; then
  fail "The app dependency check must reject version drift."
fi

write_declared_fixture
write_lock_fixture "9.2.0"
if ./scripts/check-app-dependencies.sh \
  "${declared_fixture}" \
  "${lock_fixture}" >/dev/null 2>&1; then
  fail "The app dependency check must reject a missing declaration."
fi

write_declared_fixture "9.2.0"
write_lock_fixture
if ./scripts/check-app-dependencies.sh \
  "${declared_fixture}" \
  "${lock_fixture}" >/dev/null 2>&1; then
  fail "The app dependency check must reject a missing pin."
fi

write_lock_fixture "9.2.0" "9.2.0"
if ./scripts/check-app-dependencies.sh \
  "${declared_fixture}" \
  "${lock_fixture}" >/dev/null 2>&1; then
  fail "The app dependency check must reject duplicate pins."
fi

grep -Fq "platform: watchOS" project.yml ||
  fail "The project must keep the watchOS companion target."
grep -Fq "INFOPLIST_KEY_WKCompanionAppBundleIdentifier" project.yml ||
  fail "The watchOS target must remain paired to the iPhone app."
grep -Fq "HealthRelayShared HealthRelayWatchApp" scripts/check-swift-syntax.sh ||
  fail "The fast syntax gate must include the Watch companion sources."
if grep -R -E \
  '^(@preconcurrency )?import (HealthKit|GoogleSignIn)' \
  HealthRelayShared HealthRelayWatchApp; then
  fail "The Watch companion must not own HealthKit or Google dependencies."
else
  forbidden_import_status=$?
  [[ "${forbidden_import_status}" -eq 1 ]] ||
    fail "The Watch companion dependency scan failed."
fi

expected_fast_verify=$'./scripts/test-infrastructure.sh\n./scripts/check-swift-syntax.sh\n./scripts/swift.sh test --parallel --disable-sandbox'
actual_fast_verify="$(make --no-print-directory --dry-run verify)"
[[ "${actual_fast_verify}" == "${expected_fast_verify}" ]] ||
  fail "make verify must remain the fast infrastructure and core-test gate."

expected_full_verify="${expected_fast_verify}"$'\n./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh test'
actual_full_verify="$(make --no-print-directory --dry-run verify-full)"
[[ "${actual_full_verify}" == "${expected_full_verify}" ]] ||
  fail "make verify-full must extend the fast gate with the complete iOS test task."

parsed_booted_ids="$(
  printf '%s\n' \
    '    iPhone 17 Pro (22222222-2222-2222-2222-222222222222) (Booted) ' \
    '    iPhone 17 (11111111-1111-1111-1111-111111111111) (Shutdown) ' \
    '    iPad Pro (33333333-3333-3333-3333-333333333333) (Booted) ' |
    ./scripts/parse-booted-iphone-ids.sh
)"
[[ "${parsed_booted_ids}" == "22222222-2222-2222-2222-222222222222" ]] ||
  fail "Booted-device parsing must accept simctl's trailing whitespace and ignore other states."

grep -Fq "./scripts/generate-project.sh" scripts/ios-project-task.sh ||
  fail "The locked task runner must generate the project."
grep -Fq 'destination="$(./scripts/simulator-destination.sh)"' scripts/ios-project-task.sh ||
  fail "The locked task runner must resolve test destinations."

compatible_ids=$'11111111-1111-1111-1111-111111111111\n22222222-2222-2222-2222-222222222222'
selected="$(
  ./scripts/select-simulator-id.sh \
    "${compatible_ids}" \
    "22222222-2222-2222-2222-222222222222"
)"
[[ "${selected}" == "22222222-2222-2222-2222-222222222222" ]] ||
  fail "Simulator selection must prefer an already-booted compatible iPhone."

selected="$(
  ./scripts/select-simulator-id.sh \
    "${compatible_ids}" \
    "22222222-2222-2222-2222-222222222222" \
    "11111111-1111-1111-1111-111111111111"
)"
[[ "${selected}" == "11111111-1111-1111-1111-111111111111" ]] ||
  fail "SIMULATOR_UDID must override the booted-device preference."

selected="$(
  ./scripts/select-simulator-id.sh \
    "${compatible_ids}" \
    "33333333-3333-3333-3333-333333333333"
)"
[[ "${selected}" == "11111111-1111-1111-1111-111111111111" ]] ||
  fail "Simulator selection must fall back to the first compatible iPhone."

if ./scripts/select-simulator-id.sh \
  "${compatible_ids}" \
  "" \
  "33333333-3333-3333-3333-333333333333" >/dev/null 2>&1; then
  fail "Simulator selection must reject an incompatible explicit override."
fi

open_line="$(grep -nF "/usr/bin/open -a Simulator --args -CurrentDeviceUDID" scripts/run-simulator.sh | cut -d: -f1)"
launch_line="$(grep -nF 'simctl launch "${simulator_id}"' scripts/run-simulator.sh | cut -d: -f1)"
[[ -n "${open_line}" && -n "${launch_line}" && "${open_line}" -lt "${launch_line}" ]] ||
  fail "make run must open the selected Simulator before launching the app."

if grep -Fq "brew install xcodegen" .github/workflows/verify.yml; then
  fail "CI must not install an unpinned Homebrew XcodeGen formula."
fi
if grep -Fq "./scripts/install-xcodegen.sh" .github/workflows/verify.yml; then
  fail "Fast CI must not install Xcode-only tooling."
fi
checkout_action="actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
for workflow in \
  .github/workflows/verify.yml \
  .github/workflows/full-verify.yml \
  .github/workflows/dependency-watch.yml; do
  grep -Fq "uses: ${checkout_action}" "${workflow}" ||
    fail "${workflow} must pin the supported Node 24 checkout action."
done
grep -Fq "uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9" .github/workflows/verify.yml ||
  fail "Fast CI must pin the Swift build cache action."
grep -Fq "id: swift-build-cache" .github/workflows/verify.yml ||
  fail "Fast CI must expose exact cache-hit state."
grep -Eq '^[[:space:]]+path:[[:space:]]+\.build[[:space:]]*$' .github/workflows/verify.yml ||
  fail "Fast CI must cache only the local Swift build directory."
grep -Fq "key: verify-swift-build-v1-" .github/workflows/verify.yml ||
  fail "Fast CI must keep a versioned Swift build cache key."
grep -Fq '${{ github.event.repository.name }}' .github/workflows/verify.yml ||
  fail "Fast CI must scope path-bound Swift build caches to the repository name."
grep -Fq "'Package.resolved', 'Sources/**', 'Tests/**', 'Makefile', 'scripts/swift.sh'" .github/workflows/verify.yml ||
  fail "Fast CI must invalidate its build cache for every SwiftPM input."
grep -Fq 'HEALTH_RELAY_MODULE_CACHE: ${{ github.workspace }}/.build/module-cache' .github/workflows/verify.yml ||
  fail "Fast CI must keep Swift module caches inside the cached build directory."
grep -Fq "if: steps.swift-build-cache.outputs.cache-hit == 'true'" .github/workflows/verify.yml ||
  fail "Exact cache hits must use the no-rebuild verification path."
grep -Fq "make test-infra check-app-syntax" .github/workflows/verify.yml ||
  fail "Exact cache hits must still run infrastructure and app syntax checks."
grep -Fq "./scripts/swift.sh test --skip-build --parallel --disable-sandbox" .github/workflows/verify.yml ||
  fail "Exact cache hits must run the complete cached Swift test bundle."
grep -Fq "if: steps.swift-build-cache.outputs.cache-hit != 'true'" .github/workflows/verify.yml ||
  fail "Cache misses must use the canonical build-and-test path."
grep -Eq '^[[:space:]]+runs-on:[[:space:]]+ubuntu-24\.04[[:space:]]*$' .github/workflows/verify.yml ||
  fail "Fast CI must use the Linux runner."
grep -Eq '^[[:space:]]+timeout-minutes:[[:space:]]+5[[:space:]]*$' .github/workflows/verify.yml ||
  fail "Fast CI must stay capped at five minutes."
grep -Eq '^[[:space:]]+run:[[:space:]]+make verify[[:space:]]*$' .github/workflows/verify.yml ||
  fail "Fast CI must call the canonical fast gate."
grep -Fq "./scripts/install-xcodegen.sh" .github/workflows/full-verify.yml ||
  fail "Full CI must use the checksum-verifying XcodeGen installer."
grep -Eq '^  workflow_dispatch:[[:space:]]*$' .github/workflows/full-verify.yml ||
  fail "Full CI must remain manually dispatched."
if grep -Eq '^  (pull_request|push|schedule):' .github/workflows/full-verify.yml; then
  fail "Full CI must not run automatically."
fi
grep -Eq '^[[:space:]]+run:[[:space:]]+make verify-full[[:space:]]*$' .github/workflows/full-verify.yml ||
  fail "Full CI must call the explicit full gate."
grep -Eq 'xcodegen_sha256="[0-9a-f]{64}"' scripts/install-xcodegen.sh ||
  fail "The XcodeGen installer must pin a SHA-256 digest."
