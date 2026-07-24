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
