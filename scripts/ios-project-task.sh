#!/usr/bin/env bash
set -euo pipefail

if [[ "${HEALTHMULE_XCODE_LOCKED:-}" != "1" ]]; then
  echo "error: Run iOS project tasks through scripts/with-xcode-lock.sh." >&2
  exit 1
fi

task="${1:-}"
case "${task}" in
  project | build | test | smoke | harness | run | clean) ;;
  *)
    echo "usage: $0 {project|build|test|smoke|harness|run|clean}" >&2
    exit 64
    ;;
esac

case "${task}" in
  test | smoke | harness | run)
    # xcodebuild spawns its Simulator helpers through xcode-select rather than
    # DEVELOPER_DIR, so the wrappers cannot compensate for a CommandLineTools
    # selection the way they do for plain builds.
    selected="$(/usr/bin/xcode-select -p 2>/dev/null || echo unknown)"
    if [[ ! -x "${selected}/usr/bin/simctl" ]]; then
      suggested=""
      for xcode_app in /Applications/Xcode.app /Applications/Xcode-*.app; do
        if [[ -x "${xcode_app}/Contents/Developer/usr/bin/xcodebuild" ]]; then
          suggested="${xcode_app}"
          break
        fi
      done
      echo "error: make ${task} needs xcode-select to point at a full Xcode." >&2
      echo "       Currently selected: ${selected}" >&2
      if [[ -n "${suggested}" ]]; then
        echo "       Fix it with: sudo xcode-select -s ${suggested}" >&2
      else
        echo "       No full Xcode found under /Applications; install one first." >&2
      fi
      echo "       'make verify' and 'make build' work without this." >&2
      exit 78
    fi
    ;;
esac

./scripts/generate-project.sh

case "${task}" in
  project)
    exit 0
    ;;
  build)
    exec ./scripts/xcodebuild.sh build \
      -quiet \
      -project HealthMule.xcodeproj \
      -scheme HealthMule \
      -destination "generic/platform=iOS Simulator" \
      -derivedDataPath .artifacts/DerivedData \
      CODE_SIGNING_ALLOWED=NO
    ;;
  test | smoke)
    destination="$(./scripts/simulator-destination.sh)"
    simulator_id="${destination##*=}"
    set --
    if [[ "${task}" == "smoke" ]]; then
      set -- \
        "$@" \
        "-only-testing:HealthMuleUITests/HealthMuleUITests/testAppShellUsesFocusedNavigation"
    fi

    exec ./scripts/with-simulator-lifecycle.sh \
      "${simulator_id}" \
      ./scripts/xcodebuild.sh test \
      -quiet \
      -project HealthMule.xcodeproj \
      -scheme HealthMule \
      "$@" \
      -destination "${destination}" \
      -derivedDataPath .artifacts/DerivedData \
      CODE_SIGNING_ALLOWED=YES \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY=-
    ;;
  harness)
    destination="$(./scripts/simulator-destination.sh)"
    simulator_id="${destination##*=}"
    output_root="${HEALTHMULE_HARNESS_OUTPUT:-.artifacts/agent-harness}"
    run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    run_directory="${output_root}/run-${run_id}"
    result_bundle="${run_directory}/HealthMuleHarness.xcresult"
    attachments_directory="${run_directory}/attachments"

    mkdir -p "${run_directory}"

    set +e
    ./scripts/with-simulator-lifecycle.sh \
      "${simulator_id}" \
      ./scripts/xcodebuild.sh test \
      -quiet \
      -project HealthMule.xcodeproj \
      -scheme HealthMule \
      "-only-testing:HealthMuleUITests/HealthMuleUITests/testAgentHarnessCapturesCriticalStates" \
      -destination "${destination}" \
      -derivedDataPath .artifacts/DerivedData \
      -resultBundlePath "${result_bundle}" \
      CODE_SIGNING_ALLOWED=YES \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY=-
    test_status=$?
    set -e

    postprocess_status=0
    if [[ ! -d "${result_bundle}" ]]; then
      postprocess_status=1
    elif ! mkdir -p "${attachments_directory}"; then
      postprocess_status=1
    else
      if ! ./scripts/xcrun.sh xcresulttool get test-results summary \
        --path "${result_bundle}" \
        --compact >"${run_directory}/summary.json"; then
        postprocess_status=1
      fi
      if ! ./scripts/xcrun.sh xcresulttool export attachments \
        --path "${result_bundle}" \
        --output-path "${attachments_directory}"; then
        postprocess_status=1
      fi
    fi

    printf 'HealthMule harness artifacts: %s\n' "$(cd "${run_directory}" && pwd)"
    if (( test_status != 0 )); then
      exit "${test_status}"
    fi
    exit "${postprocess_status}"
    ;;
  run)
    exec ./scripts/run-simulator.sh
    ;;
  clean)
    exec ./scripts/xcodebuild.sh clean \
      -project HealthMule.xcodeproj \
      -scheme HealthMule \
      -derivedDataPath .artifacts/DerivedData
    ;;
esac
