#!/usr/bin/env bash
set -euo pipefail

if [[ "${HEALTHMULE_XCODE_LOCKED:-}" != "1" ]]; then
  echo "error: Run iOS project tasks through scripts/with-xcode-lock.sh." >&2
  exit 1
fi

task="${1:-}"
case "${task}" in
  project | build | test | smoke | run | clean) ;;
  *)
    echo "usage: $0 {project|build|test|smoke|run|clean}" >&2
    exit 64
    ;;
esac

case "${task}" in
  test | smoke | run)
    # xcodebuild spawns its Simulator helpers through xcode-select rather than
    # DEVELOPER_DIR, so the wrappers cannot compensate for a CommandLineTools
    # selection the way they do for plain builds.
    if ! /usr/bin/xcrun --find simctl >/dev/null 2>&1; then
      selected="$(/usr/bin/xcode-select -p 2>/dev/null || echo unknown)"
      echo "error: make ${task} needs xcode-select to point at a full Xcode." >&2
      echo "       Currently selected: ${selected}" >&2
      echo "       Fix it with: sudo xcode-select -s /Applications/Xcode.app" >&2
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
    set --
    if [[ "${task}" == "smoke" ]]; then
      set -- \
        "$@" \
        "-only-testing:HealthMuleUITests/HealthMuleUITests/testAppShellUsesFocusedNavigation"
    fi

    exec ./scripts/xcodebuild.sh test \
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
