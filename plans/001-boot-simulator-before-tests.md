# Plan 001: Boot the target Simulator before every Simulator-backed task

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat db7dd06..HEAD -- scripts/ios-project-task.sh scripts/run-simulator.sh scripts/test-infrastructure.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `db7dd06`, 2026-08-02

## Why this matters

`make test`, `make smoke`, and `make verify-full` resolve a Simulator
destination but never boot it. Against a shut-down device the test runner loses
a launch race and **every** UI test fails with
`SBMainWorkspace ... Busy ("Application failed preflight checks")`. This was
reproduced twice on 2026-08-02: 16 tests failed with 0 passed, and the identical
suite passed 148/148 once the device was booted first.

The failure reads exactly like a product regression, so it costs a full
debugging cycle every time it happens. It is also baked into
`.github/workflows/testflight.yml`, where `make verify-full` is the gate that
runs before a release is archived — so the release path is the most likely place
to hit it, on a runner that is always cold.

`scripts/run-simulator.sh` already boots correctly. This plan moves that
two-line pattern into the shared path.

## Current state

Files:

- `scripts/ios-project-task.sh` — dispatches `project|build|test|smoke|run|clean`
  behind the Xcode lock. The `test | smoke` branch resolves a destination and
  execs `xcodebuild test` with **no** boot step.
- `scripts/run-simulator.sh` — the `run` path; already boots and waits.
- `scripts/test-infrastructure.sh` — the contract test that `make verify` runs.

`scripts/ios-project-task.sh`, the `test | smoke` branch as it exists today
(lines 48-73):

```bash
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
```

The proven boot pattern, `scripts/run-simulator.sh:8-9`:

```bash
./scripts/xcrun.sh simctl boot "${simulator_id}" >/dev/null 2>&1 || true
./scripts/xcrun.sh simctl bootstatus "${simulator_id}" -b
```

`booting an already-booted device` is a no-op that exits non-zero, which is why
the `|| true` is there; `bootstatus -b` then blocks until the device is fully
booted.

Note the shape mismatch you must handle: `simulator-destination.sh` returns a
full destination string (`platform=iOS Simulator,id=<UDID>`), not a bare UDID.
`scripts/select-simulator-id.sh` is what returns a bare UDID.

Repo conventions to match:

- Every script starts `#!/usr/bin/env bash` then `set -euo pipefail`.
- Never call `xcrun`/`xcodebuild`/`swift` directly — always the `scripts/`
  wrappers. See `AGENTS.md` "Runner contract".
- Scripts must be executable; `scripts/test-infrastructure.sh` enforces this.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Fast gate | `make verify` | exit 0 |
| Contract test only | `make test-infra` | exit 0 |
| Smoke (needs Xcode + Simulator) | `make smoke` | exit 0 |
| Shell syntax | `bash -n scripts/ios-project-task.sh` | exit 0 |

`make verify` runs on Linux or macOS. `make smoke` needs a full Xcode and
`xcode-select` pointed at it.

## Scope

**In scope**:
- `scripts/ios-project-task.sh`
- `scripts/test-infrastructure.sh`

**Out of scope** (do NOT touch):
- `scripts/run-simulator.sh` — already correct; leave its boot lines in place
  even though they become redundant with the shared path. Removing them risks
  the `run` path and buys nothing.
- `scripts/simulator-destination.sh` and `scripts/select-simulator-id.sh` —
  selection logic is correct and separately tested; only *consume* them.
- `.github/workflows/*.yml` — the fix belongs in the script so every caller
  benefits; do not add boot steps to CI.
- The existing `xcode-select` guard at the top of `ios-project-task.sh` — keep
  it; it handles a different failure.

## Git workflow

- Branch: `advisor/001-boot-simulator-before-tests`
- Conventional commits; match the existing style, e.g.
  `fix(ci): boot the target Simulator before Simulator-backed tasks`
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Extract the selected UDID once and boot it

In the `test | smoke` branch of `scripts/ios-project-task.sh`, resolve the
simulator id **before** building the destination string, boot it, wait for it,
then build the destination from that same id. Producing the id once and reusing
it avoids selecting one device and booting another.

Target shape:

```bash
  test | smoke)
    simulator_id="$(
      ./scripts/select-simulator-id.sh \
        "$(./scripts/xcodebuild.sh -project HealthMule.xcodeproj -scheme HealthMule -showdestinations |
            sed -nE '/platform:iOS Simulator.*name:iPhone/ s/.*id:([^,}]+).*/\1/p' |
            sed -E 's/^[[:space:]]+|[[:space:]]+$//g')" \
        "$(./scripts/xcrun.sh simctl list devices available |
            ./scripts/parse-booted-iphone-ids.sh)" \
        "${SIMULATOR_UDID:-}"
    )"
    ./scripts/xcrun.sh simctl boot "${simulator_id}" >/dev/null 2>&1 || true
    ./scripts/xcrun.sh simctl bootstatus "${simulator_id}" -b
    destination="platform=iOS Simulator,id=${simulator_id}"
```

If duplicating that selection pipeline inline feels wrong, the cleaner option is
to add a `--id-only` mode (or a sibling `scripts/select-destination-id.sh`) that
`simulator-destination.sh` also consumes, so the pipeline exists once. Either is
acceptable; prefer whichever leaves one copy of the selection logic.

**Verify**: `bash -n scripts/ios-project-task.sh` → exit 0.

### Step 2: Pin the behavior in the contract test

`scripts/test-infrastructure.sh` currently asserts nothing about booting. Add an
assertion that the Simulator-backed path boots before invoking `xcodebuild test`
— a static check is sufficient and keeps `make verify` runnable on Linux.

Add near the other `scripts/` assertions:

```bash
boot_line="$(grep -nF 'simctl bootstatus' scripts/ios-project-task.sh | head -1 | cut -d: -f1)"
test_line="$(grep -nF 'xcodebuild.sh test' scripts/ios-project-task.sh | head -1 | cut -d: -f1)"
[[ -n "${boot_line}" && -n "${test_line}" && "${boot_line}" -lt "${test_line}" ]] ||
  fail "Simulator-backed tasks must boot the target device before running xcodebuild test."
```

**Verify**: `make test-infra` → exit 0.

### Step 3: Confirm the real path still works

**Verify**: `make verify` → exit 0.

**Verify**: with all simulators shut down
(`./scripts/xcrun.sh simctl shutdown all`), run `make smoke` → exit 0. This is
the regression this plan exists to prevent: before the change, a cold device
fails; after it, the task boots and waits.

## Test plan

There is no unit-test target for shell scripts; `scripts/test-infrastructure.sh`
is the repo's contract-test mechanism and Step 2 extends it. Model the new
assertion on the existing ordering check in the same file, which asserts that
`make run` opens the Simulator before launching:

```bash
open_line="$(grep -nF "/usr/bin/open -a Simulator --args -CurrentDeviceUDID" scripts/run-simulator.sh | cut -d: -f1)"
launch_line="$(grep -nF 'simctl launch "${simulator_id}"' scripts/run-simulator.sh | cut -d: -f1)"
[[ -n "${open_line}" && -n "${launch_line}" && "${open_line}" -lt "${launch_line}" ]] ||
  fail "make run must open the selected Simulator before launching the app."
```

The empirical proof is Step 3's cold-device `make smoke`.

## Done criteria

ALL must hold:

- [ ] `make verify` exits 0
- [ ] `make test-infra` exits 0 and fails if the boot line is removed (check by
      temporarily deleting it, re-running, and restoring)
- [ ] `make smoke` exits 0 starting from `simctl shutdown all`
- [ ] `grep -c 'simctl bootstatus' scripts/ios-project-task.sh` returns at least 1
- [ ] Only `scripts/ios-project-task.sh` and `scripts/test-infrastructure.sh`
      are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- The `test | smoke` branch does not match the excerpt above.
- `make smoke` still fails on a cold device after the boot lines are added —
  that means the race has a second cause and needs fresh diagnosis, not more
  retries.
- `xcode-select -p` points at CommandLineTools. `make smoke` will exit 78 with
  instructions; that fix needs `sudo` and is the operator's to run, not yours.
- Making the selection logic single-copy appears to require changing
  `select-simulator-id.sh`'s contract (its arguments are asserted by
  `scripts/test-infrastructure.sh`).

## Maintenance notes

- If a future change adds another Simulator-backed task to
  `scripts/ios-project-task.sh`, it must boot too — the Step 2 assertion only
  covers the first `xcodebuild test` occurrence.
- A reviewer should check that the simulator id is resolved exactly once and
  that the booted device is the same one passed in `-destination`.
- Deliberately deferred: removing the now-redundant boot from
  `run-simulator.sh`, and adding DerivedData caching to the macOS CI job (a
  separate DX finding).
