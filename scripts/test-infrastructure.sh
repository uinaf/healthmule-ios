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
  scripts/install-xcodegen.sh \
  scripts/ios-project-task.sh \
  scripts/parse-booted-iphone-ids.sh \
  scripts/run-simulator.sh \
  scripts/select-simulator-id.sh \
  scripts/simulator-destination.sh \
  scripts/with-xcode-lock.sh; do
  /bin/bash -n "${script}"
done

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
grep -Fq "./scripts/install-xcodegen.sh" .github/workflows/verify.yml ||
  fail "CI must use the checksum-verifying XcodeGen installer."
grep -Eq 'xcodegen_sha256="[0-9a-f]{64}"' scripts/install-xcodegen.sh ||
  fail "The XcodeGen installer must pin a SHA-256 digest."
