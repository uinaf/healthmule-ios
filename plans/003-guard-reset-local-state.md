# Plan 003: Give `resetLocalState()` the same epoch and in-flight guards as every other operation

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat db7dd06..HEAD -- HealthMuleApp/App/AppModel.swift`
> If the file changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, treat it as
> a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db7dd06`, 2026-08-02

## Why this matters

`AppModel` protects every long-running operation with two mechanisms: an
entry guard (`guard !operationState.isWorking`) and an epoch captured after the
state is set, re-checked before each commit that follows an `await`. This is how
the app prevents a stale continuation from overwriting a newer operation's
result.

`resetLocalState()` is the only operation with neither. It sets `.working`, then
performs three `await`s, then writes `syncCoordinator`, `syncInitializationError`,
`syncSummary`, `diagnosticsURL` and the terminal `operationState` with no
re-check. Its failure branch unconditionally sets `syncCoordinator = nil`, which
surfaces as "local storage unavailable" even if a concurrently-recovered
coordinator was healthy.

The UI disables the button while an operation is working, so this needs a
non-UI trigger to collide — but background refresh, HealthKit observer flushes,
and Watch-triggered reconciles are exactly that, and they can all fire while a
reset is in flight.

## Current state

File: `HealthMuleApp/App/AppModel.swift`.

The unguarded operation, lines 1048-1078:

```swift
    func resetLocalState() async {
        operationState = .working(
            .localReset,
            "Resetting local sync state"
        )
        do {
            let candidate = if let syncCoordinator {
                syncCoordinator
            } else {
                try makeSyncCoordinator()
            }
            try await candidate.reset()
            let refreshedSummary = try await candidate.summary()
            syncCoordinator = candidate
            syncInitializationError = nil
            syncSummary = refreshedSummary
            diagnosticsURL = nil
            operationState = .succeeded(
                .localReset,
                "Local sync history was reset. Drive files and their stable IDs were kept."
            )
            await diagnostics.record(.localReset)
        } catch {
            syncCoordinator = nil
            syncInitializationError = error.localizedDescription
            operationState = .failed(
                .localReset,
                error.localizedDescription
            )
        }
    }
```

The pattern to match, `prepareDiagnosticsExport()` at lines 1012-1024:

```swift
    func prepareDiagnosticsExport() async {
        guard !operationState.isWorking else {
            return
        }
        let preparingState = OperationState.working(
            .diagnostics,
            "Preparing diagnostics"
        )
        operationState = preparingState
        let expectedOperationEpoch = operationEpoch
        do {
            diagnosticsURL = try await diagnostics.export()
            guard
```

Read `prepareDiagnosticsExport()` in full before writing code — it is the
closest structural sibling and shows exactly how the guard reads after the
`await`.

Also read `reconcileOnce` (around lines 716, 740, 754, 769) for the multi-commit
form, and `settleStaleOperation(ifCurrent:expectedEpoch:)` — several operations
call it to release a superseded state rather than dropping it silently. Decide
which is right here and say why in the commit message.

Why the epoch must be captured **after** the assignment: `operationEpoch` is
bumped inside `operationState`'s `didSet`, so reading it before the assignment
captures the previous generation. Every existing call site assigns first, then
reads. Match that ordering.

Repo conventions:

- `AppModel` is `@MainActor` and `@Observable`; all of this runs on the main
  actor. No locking is involved.
- Never log health values, tokens, record bodies, or raw metadata.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Fast gate | `make verify` | exit 0 |
| Compile | `make build` | exit 0 |
| Full iOS + Simulator gate | `make verify-full` | exit 0, 148+ tests pass |

`make verify-full` requires a full Xcode and the target Simulator **already
booted** — see plan 001.

## Scope

**In scope**:
- `HealthMuleApp/App/AppModel.swift` — only `resetLocalState()`
- `HealthMuleTests/AppConfigurationTests.swift` — new tests

**Out of scope** (do NOT touch):
- Any other operation in `AppModel`. They already have the guards; "while
  you're in there" consistency edits are not part of this plan.
- The `didSet` observers and the epoch mechanism itself.
- `LiveSyncCoordinator.reset()` and its staging-root deletion.
- `error.localizedDescription` appearing in `operationState` here. That is a
  real separate finding (it can surface a staged filename, i.e. a health-activity
  date, in the UI) but it spans 11 sites and belongs in its own plan.

## Git workflow

- Branch: `advisor/003-guard-reset-local-state`
- Conventional commits, e.g.
  `fix(sync): guard resetLocalState against concurrent operations`
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Add the entry guard

Add `guard !operationState.isWorking else { return }` as the first statement,
matching `prepareDiagnosticsExport()`.

**Verify**: `make build` → exit 0.

### Step 2: Capture and re-check the epoch

- Hoist the working state into a local (`let resettingState = OperationState.working(.localReset, "Resetting local sync state")`), assign it, then
  `let expectedOperationEpoch = operationEpoch`.
- Before the success commits, re-check
  `operationEpoch == expectedOperationEpoch && operationState == resettingState`.
  If the check fails, do not write `syncCoordinator`, `syncSummary`,
  `diagnosticsURL`, or the terminal state.
- Apply the same re-check in the `catch` branch **before** setting
  `syncCoordinator = nil`. A stale failure must not tear down a coordinator that
  a newer operation successfully recovered.

Decide deliberately whether a superseded reset should call
`settleStaleOperation(ifCurrent:expectedEpoch:)` like `reconcileOnce` does, or
simply return. Note the choice in the commit message.

**Verify**: `make build` → exit 0.

### Step 3: Tests

See "Test plan".

**Verify**: `make verify-full` → exit 0.

## Test plan

`AppModel`'s only initializer is `private`, and `AppModel.live()` is its sole
caller, so **no test currently constructs an `AppModel`** — verify this yourself
with `grep -rn "AppModel(" HealthMuleTests Tests`. That is a real obstacle to
testing this directly, and building a construction seam is a larger piece of
work that is deliberately not in this plan.

Given that, cover what is reachable:

1. In `HealthMuleTests/AppConfigurationTests.swift`, test the *pure* pieces the
   guard depends on — that `OperationState.isWorking` is true for
   `.working(.localReset, _)`, so the entry guard actually blocks. Model on the
   existing `OperationState` tests already in that file (find them with
   `grep -n "OperationState" HealthMuleTests/AppConfigurationTests.swift`).
2. Assert the ordering invariant that makes the epoch work — that assigning
   `operationState` bumps `operationEpoch` — if an existing test does not
   already cover it.

If, while reading, you find the file already contains an `AppModel` test seam
that this plan's author missed, use it and write a real concurrency
characterization test instead: start a reset, let a second operation supersede
it mid-flight, and assert the reset does not clobber the newer terminal state.

**Verification**: `make verify-full` → all pass, including the new tests.

## Done criteria

ALL must hold:

- [ ] `make verify` exits 0
- [ ] `make build` exits 0
- [ ] `make verify-full` exits 0 with no failures
- [ ] `resetLocalState()` contains `guard !operationState.isWorking`
- [ ] `resetLocalState()` reads `operationEpoch` into a local **after** the
      `operationState` assignment, and re-checks it before every commit in both
      the success and the `catch` branch
- [ ] Only `AppModel.swift` and `AppConfigurationTests.swift` are modified
      (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- `resetLocalState()` does not match the excerpt above.
- Adding the entry guard breaks an existing test — that would mean something
  intentionally resets during another operation, which is a design question,
  not a bug to guard away.
- You conclude a proper test requires making `AppModel.init` internal or
  introducing protocols for its collaborators. That is a real and worthwhile
  piece of work, but it is a separate plan; report it rather than starting it.

## Maintenance notes

- Any new `AppModel` operation must follow the same shape: entry guard, assign
  state, capture epoch, re-check before each post-`await` commit. There is no
  mechanical enforcement of this — it is convention only, which is how
  `resetLocalState()` drifted in the first place.
- A reviewer should check the `catch` branch specifically. The success path is
  the obvious one; the failure path setting `syncCoordinator = nil` is the
  damaging one.
- Deliberately deferred: an `AppModel` construction seam and characterization
  tests for the three epoch domains (`operationEpoch`, `googleTransitionEpoch`,
  `healthRefreshEpoch`) — the highest-value testing work in this codebase, and
  a prerequisite for any refactor of the Google connection lifecycle.
