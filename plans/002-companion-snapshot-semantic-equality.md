# Plan 002: Compare companion snapshots semantically and stop republishing unchanged status

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat db7dd06..HEAD -- HealthMuleShared/CompanionSyncContract.swift HealthMuleWatchApp/Connectivity/CompanionAppModel.swift HealthMuleApp/Watch HealthMuleApp/App/AppModel.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `db7dd06`, 2026-08-02

## Why this matters

Every companion snapshot is stamped with a fresh `generatedAt`, and
`CompanionSyncSnapshot` gets synthesized `Equatable` over all stored properties
— `generatedAt` included. So on the Watch, *every* snapshot comparison is
unconditionally unequal, even when readiness, activity and all three counts are
identical.

That silently defeats the Watch's request-acknowledgement state machine.
`CompanionAppModel.apply()` uses those comparisons to decide whether a
*meaningful* status change arrived after the user tapped Sync. Because any push
looks like a change, `receivedPostRequestSnapshot` gets set by unrelated
traffic, and the "Sync started" confirmation either vanishes immediately or
never appears.

It is made worse by volume: `publishCompanionStatus()` fires from five separate
`didSet` hooks, so one sync pushes 3–5 application contexts. WatchConnectivity
coalesces rapid `updateApplicationContext` calls, so the Watch frequently never
observes the intermediate `.syncing` activity at all.

This is a user-visible correctness bug in the Watch companion, reported as
"sync is wonky, doesn't show actual progress".

## Current state

Files:

- `HealthMuleShared/CompanionSyncContract.swift` — the wire contract shared by
  both apps (built as the `HealthMuleCompanion` SPM product).
- `HealthMuleWatchApp/Connectivity/CompanionAppModel.swift` — Watch-side state
  machine.
- `HealthMuleApp/Watch/PhoneWatchConnectivityCoordinator.swift` — phone-side
  publisher; `publishCurrentStatus()` calls `updateApplicationContext`.
- `HealthMuleApp/Watch/CompanionSnapshotFactory.swift` — maps app state to a
  snapshot; stamps `generatedAt`.
- `HealthMuleApp/App/AppModel.swift` — owns the five `didSet` publish sites.

The type, `HealthMuleShared/CompanionSyncContract.swift:3` and `:21-29`:

```swift
public struct CompanionSyncSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let readiness: Readiness
    public let activity: Activity
    public let canRequestSync: Bool
    public let lastSuccessfulSyncAt: Date?
    public let pendingUploadCount: Int
    public let retryableUploadCount: Int
    public let permanentFailureCount: Int
```

The stamp, `HealthMuleApp/Watch/CompanionSnapshotFactory.swift:5-12`:

```swift
    static func make(
        readiness: SyncReadiness,
        operationState: OperationState,
        summary: SyncSummary,
        now: Date = .now
    ) -> CompanionSyncSnapshot {
        CompanionSyncSnapshot(
            generatedAt: now,
```

The defeated logic, `HealthMuleWatchApp/Connectivity/CompanionAppModel.swift:147-163`:

```swift
    private func apply(_ snapshot: CompanionSyncSnapshot) {
        let changed = snapshot != self.snapshot
        self.snapshot = snapshot
        if
            changed,
            requestBaselineSnapshot != nil,
            snapshot != requestBaselineSnapshot
        {
            receivedPostRequestSnapshot = true
            if deliveryState == .accepted {
                acceptedRequestID = nil
                deliveryState = .idle
                requestBaselineSnapshot = nil
                receivedPostRequestSnapshot = false
            }
        }
    }
```

The five publish sites in `HealthMuleApp/App/AppModel.swift` — lines 32, 40, 48,
61 (all inside `didSet` observers) and 1390 (a `defer`) — all reach:

```swift
    private func publishCompanionStatus() {
        watchConnectivity?.publishCurrentStatus()
    }
```

Repo conventions that apply:

- `HealthMuleCore` and `HealthMuleShared` must stay **Foundation-only and
  deterministic** (`AGENTS.md` "Repo rules"). Do not import anything else into
  the contract file.
- The companion snapshot must never carry health values, account details, Drive
  IDs, tokens, or error strings. Adding a comparison helper must not add fields.
- Core tests use swift-testing (`@Test` / `#expect`) — see
  `Tests/HealthMuleCoreTests/CompanionSyncContractTests.swift`. iOS tests use
  XCTest — see `HealthMuleTests/CompanionSnapshotFactoryTests.swift`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Fast gate (Linux-safe) | `make verify` | exit 0 |
| Core tests only | `make test-core` | all pass |
| Compile app + Watch app | `make build` | exit 0 |
| Full iOS + Simulator gate | `make verify-full` | exit 0, 148+ tests pass |

`make verify-full` requires a full Xcode **and the target Simulator already
booted** — see plan 001. If 001 has not landed, boot it yourself first:
`./scripts/xcrun.sh simctl boot <udid>` then `./scripts/xcrun.sh simctl bootstatus <udid> -b`.

## Scope

**In scope**:
- `HealthMuleShared/CompanionSyncContract.swift`
- `HealthMuleWatchApp/Connectivity/CompanionAppModel.swift`
- `HealthMuleApp/Watch/PhoneWatchConnectivityCoordinator.swift`
- `Tests/HealthMuleCoreTests/CompanionSyncContractTests.swift`
- `HealthMuleTests/CompanionSnapshotFactoryTests.swift`

**Out of scope** (do NOT touch):
- The wire format. Do **not** remove `generatedAt` from the struct or from
  `Codable` — the phone genuinely publishes it and a future consumer may want
  staleness. Only its role in *equality* changes.
- `HealthMuleWatchApp/Connectivity/CompanionAppModel.swift`'s `activate()`
  ordering and its `sendMessage` call site. Those are candidate causes of a
  separate, unresolved Watch crash under active investigation with a pending
  crash log. Changing them here would confound that diagnosis.
- The five `didSet` observers themselves in `AppModel.swift` — de-duplicate
  inside the coordinator, not by removing publish triggers.
- `CompanionSnapshotFactory`'s mapping logic.

## Git workflow

- Branch: `advisor/002-companion-snapshot-semantic-equality`
- Conventional commits, e.g.
  `fix(watch): compare companion snapshots semantically`
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Add a semantic projection to the contract

In `HealthMuleShared/CompanionSyncContract.swift`, add a nested `Semantics`
value that carries every field **except** `generatedAt`, plus a computed
`semantics` property. Keep `Equatable` on the outer type as-is (removing it
would change other call sites); add the projection alongside.

```swift
    /// Everything a reader can act on. `generatedAt` is excluded: it changes on
    /// every publish, so including it makes equality meaningless.
    public struct Semantics: Equatable, Sendable {
        public let schemaVersion: Int
        public let readiness: Readiness
        public let activity: Activity
        public let canRequestSync: Bool
        public let lastSuccessfulSyncAt: Date?
        public let pendingUploadCount: Int
        public let retryableUploadCount: Int
        public let permanentFailureCount: Int
    }

    public var semantics: Semantics { ... }
```

**Verify**: `make test-core` → all pass (nothing should break yet).

### Step 2: Compare on the projection in the Watch state machine

In `CompanionAppModel.apply(_:)`, replace the two whole-value comparisons with
projection comparisons:

- `let changed = snapshot != self.snapshot`
  → `let changed = snapshot.semantics != self.snapshot?.semantics`
- `snapshot != requestBaselineSnapshot`
  → `snapshot.semantics != requestBaselineSnapshot?.semantics`

Note the optional handling: `self.snapshot` is `CompanionSyncSnapshot?`, so
`self.snapshot?.semantics` is `Semantics?` and comparing a non-optional to an
optional is valid and correctly reports "changed" on the first snapshot.

**Verify**: `make build` → exit 0.

### Step 3: Skip publishing an unchanged snapshot

In `PhoneWatchConnectivityCoordinator`, keep the last published `Semantics` and
return early from `publishCurrentStatus()` when the new snapshot's projection
equals it. The coordinator is `@MainActor`, so a plain stored property is safe.

Reset that cached value whenever the session changes state such that the Watch
may have missed a context — at minimum in `activate()` and in
`sessionWatchStateDidChange`, so a newly paired or reinstalled Watch still
receives a full snapshot.

**Verify**: `make build` → exit 0.

### Step 4: Regression tests

See "Test plan".

**Verify**: `make verify` → exit 0, then `make verify-full` → exit 0.

## Test plan

**`Tests/HealthMuleCoreTests/CompanionSyncContractTests.swift`** (swift-testing,
runs on Linux in the required gate) — add:

1. Two snapshots differing **only** in `generatedAt` have equal `semantics` and
   unequal `==`. This is the exact defect; assert both halves so a future change
   that reintroduces `generatedAt` into the projection fails here.
2. Two snapshots differing in `activity` (and separately in
   `pendingUploadCount`) have unequal `semantics`.
3. `semantics` round-trips unchanged through
   `CompanionPayloadCodec.message(snapshot:)` → `.snapshot(from:)`.

Model these on the existing `@Test` functions in that file.

**`HealthMuleTests/CompanionSnapshotFactoryTests.swift`** (XCTest) — add:

4. Two `CompanionSnapshotFactory.make(...)` calls with identical inputs but
   different `now:` values produce equal `semantics`. The factory takes
   `now: Date = .now`, so pass explicit dates — do not rely on wall-clock.

**Verification**: `make test-core` → all pass including 3 new tests;
`make verify-full` → all pass including the new XCTest.

There is no watchOS test target, so `apply()` cannot be unit-tested directly;
Step 2's correctness rides on the contract tests plus `make build`. Do not
create a watch test target in this plan.

## Done criteria

ALL must hold:

- [ ] `make verify` exits 0
- [ ] `make build` exits 0 (app and embedded Watch app compile)
- [ ] `make verify-full` exits 0 with no failures
- [ ] `grep -n "snapshot != self.snapshot" HealthMuleWatchApp/Connectivity/CompanionAppModel.swift`
      returns no matches
- [ ] `grep -c "semantics" HealthMuleShared/CompanionSyncContract.swift` returns at least 2
- [ ] The four new tests above exist and pass
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- `apply(_:)` or the snapshot struct does not match the excerpts above.
- Suppressing republishes in Step 3 makes any existing test fail — that would
  mean something depends on the publish cadence, which needs a decision rather
  than a workaround.
- You find yourself needing to change `CompanionSnapshotFactory`'s mapping or
  the `didSet` observers to make this work.
- You conclude `generatedAt` should be removed from the wire format. That is a
  schema change requiring a `schemaVersion` bump and is explicitly out of scope.

## Maintenance notes

- Any field added to `CompanionSyncSnapshot` in future must also be added to
  `Semantics`, or changes to it will stop reaching the Watch. Test 1 above does
  not catch that — consider it when reviewing a contract change.
- A reviewer should confirm the Step 3 cache is reset on re-pair/reinstall; a
  stale cache there means a Watch that never receives its first snapshot, which
  is a worse failure than the one being fixed.
- Deliberately deferred: the Watch crash on tapping Sync (separate
  investigation, pending crash log), and the absence of a watchOS test target
  (tracked in `docs/ARCHITECTURE.md` "Remaining integration gaps").
