# Plan 004: Delete the unreachable `drive_401` literal and give the failure-code vocabulary one owner

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat db7dd06..HEAD -- HealthMuleApp/Sync/DriveArtifactDestination.swift HealthMuleApp/App/AppModel.swift HealthMuleApp/Diagnostics/DiagnosticsRecorder.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `db7dd06`, 2026-08-02

## Why this matters

Drive failures are described by string codes produced in one file and matched by
string literals in two others, with no shared constant and no test tying them
together. The vocabulary has already drifted: `AppModel` matches `"drive_401"`,
which **no producer can ever emit**.

Today that is harmless — the sibling literal `"drive_reauthorization_required"`
covers the real 401 path — so this is not a live bug. It matters because of the
failure *shape*: if a producer string is ever renamed, reauthorization is
silently never triggered. The user's syncs quietly stop, no reconnect prompt
appears, nothing throws, and no test fails. One dead literal is already evidence
that this drift happens.

## Current state

Three files hold copies of the same vocabulary.

**Producer** — `HealthMuleApp/Sync/DriveArtifactDestination.swift:39-65`, the
only place these codes are created:

```swift
    private static func destinationError(
        for error: DriveAPIError
    ) -> ExportDestinationError {
        switch error {
        case .reauthorizationRequired:
            .reauthorizationRequired(code: "drive_reauthorization_required")
        case .authenticationUnavailable:
            .transient(code: "google_token_refresh")
        case .accountNotReady:
            .transient(code: "drive_account_not_ready")
        case .destinationChanged:
            .transient(code: "drive_destination_changed")
        case .transport(let code):
            .transient(code: "transport_\(code.rawValue)")
        case .remote(let status, let reason, let retryable):
            if retryable {
                .transient(
                    code: "drive_\(status)_\(reason ?? "retryable")"
                )
            } else {
                .permanent(
                    code: "drive_\(status)_\(reason ?? "error")"
                )
            }
        case .invalidResponse:
            .permanent(code: "drive_invalid_response")
        }
    }
```

**Consumer 1** — `HealthMuleApp/App/AppModel.swift:1773-1780`:

```swift
        guard report.failures.contains(where: {
            [
                "drive_401",
                "drive_reauthorization_required",
            ].contains($0.code)
        }) else {
            return false
        }
```

**Consumer 2** — `HealthMuleApp/Diagnostics/DiagnosticsRecorder.swift:14-42`, a
third copy as both raw values and `case` patterns:

```swift
    case accountNotReady = "drive_account_not_ready"
    case destinationChanged = "drive_destination_changed"
    case invalidResponse = "drive_invalid_response"
    case missingDailyDate = "missing_daily_date"
    case reauthorizationRequired = "drive_reauthorization_required"
    case remote = "drive_remote"
    case tokenRefresh = "google_token_refresh"
    case transport = "drive_transport"
    case unknown

    init(_ failure: SyncFailureSummary) {
        switch failure.code {
        case "drive_account_not_ready":
        ...
        case let code where code.hasPrefix("transport_"):
            self = .transport
        case let code where code.hasPrefix("drive_"):
            self = .remote
```

**Why `"drive_401"` is unreachable** — verify this yourself before proceeding:

1. The `.remote` branch always formats `drive_<status>_<reason>`, never bare
   `drive_401`.
2. A 401 never reaches `.remote` at all. `HealthMuleApp/Google/DriveAPIClient.swift`
   (around lines 1166-1172 and 1200-1201) converts every 401 into
   `DriveAPIError.reauthorizationRequired`, which maps to
   `"drive_reauthorization_required"`.

Confirm with:
`grep -n "reauthorizationRequired\|401" HealthMuleApp/Google/DriveAPIClient.swift`

Repo conventions:

- `SyncFailureSummary.code` is a `String` defined in the Foundation-only core
  (`Sources/HealthMuleCore/Sync/SyncModels.swift`). The **core must stay
  Foundation-only and must not learn about Drive** — so the shared vocabulary
  belongs in the app layer, next to `DriveArtifactDestination`, not in the core.
- These codes are recorded in the diagnostics export. Treat the *diagnostics
  output* strings as a compatibility surface: keep the emitted values byte-identical.

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
- `HealthMuleApp/Sync/DriveArtifactDestination.swift`
- `HealthMuleApp/App/AppModel.swift` — only `requireGoogleReconnect(for:expectedEpoch:)`
- `HealthMuleApp/Diagnostics/DiagnosticsRecorder.swift` — only the code-matching
  `init`, not the recorder's allowlist or logging
- `HealthMuleTests/AppConfigurationTests.swift` or
  `HealthMuleTests/DiagnosticsRecorderTests.swift` — new tests

**Out of scope** (do NOT touch):
- `Sources/HealthMuleCore/**`. Do not move the vocabulary into the core, and do
  not change `SyncFailureSummary`. The core must not know Drive exists.
- The emitted string values themselves. This is a refactor: every code the app
  produces today must be byte-identical afterward. The **only** removal is the
  unreachable `"drive_401"` match.
- `DriveAPIClient`'s error classification.
- The `DiagnosticsRecorder` allowlist and its `.private(mask: .hash)` logging.

## Git workflow

- Branch: `advisor/004-share-the-drive-failure-code-vocabulary`
- Conventional commits, e.g.
  `refactor(sync): give Drive failure codes a single owner`
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Prove the claim before changing anything

Confirm `"drive_401"` is unreachable using the two checks in "Current state".
If a producer of bare `drive_401` exists, this plan's premise is wrong — STOP.

**Verify**: `grep -rn '"drive_401"' HealthMuleApp` → exactly one match, in
`AppModel.swift`.

### Step 2: Introduce the shared vocabulary

Next to `DriveArtifactDestination`, add a type owning the fixed codes, e.g.:

```swift
enum DriveFailureCode: String {
    case reauthorizationRequired = "drive_reauthorization_required"
    case tokenRefresh = "google_token_refresh"
    case accountNotReady = "drive_account_not_ready"
    case destinationChanged = "drive_destination_changed"
    case invalidResponse = "drive_invalid_response"

    static let transportPrefix = "transport_"
    static let remotePrefix = "drive_"
}
```

The two dynamic forms (`transport_<code>` and `drive_<status>_<reason>`) are not
enum cases; expose them as static factory functions so the format string exists
once.

**Verify**: `make build` → exit 0.

### Step 3: Point the producer at it

Replace the literals in `destinationError(for:)` with the enum's `rawValue` and
the new factories. Emitted strings must not change.

**Verify**: `make build` → exit 0.

### Step 4: Point both consumers at it and delete the dead literal

- `AppModel`: match on `DriveFailureCode.reauthorizationRequired.rawValue` and
  **delete `"drive_401"`**.
- `DiagnosticsRecorder`: use the enum's raw values and prefix constants instead
  of inline literals, keeping its own emitted raw values unchanged.

**Verify**: `grep -rn '"drive_401"' HealthMuleApp` → no matches.

### Step 5: Tests

See "Test plan".

**Verify**: `make verify-full` → exit 0.

## Test plan

Add a table-driven test mapping every `DriveAPIError` case to the code it
produces, and asserting that the reauthorization code is the one `AppModel`
matches on. This is the test whose absence let the drift happen.

Cases to cover, one row each: `.reauthorizationRequired`,
`.authenticationUnavailable`, `.accountNotReady`, `.destinationChanged`,
`.transport`, `.remote(retryable: true)`, `.remote(retryable: false)`,
`.invalidResponse`.

Also assert:

- The code produced for `.reauthorizationRequired` is exactly what
  `requireGoogleReconnect` treats as requiring reconnect. If that guard is
  `private`, either extract the matched set into an internal `static let` on the
  vocabulary type and assert against that, or use `@testable import HealthMule`
  (already used throughout `HealthMuleTests`).
- `DiagnosticSyncFailureCode(_:)` maps each produced code to the expected case —
  this is what pins the third copy.

Place these in `HealthMuleTests/`; model the structure on the existing tests in
`HealthMuleTests/DiagnosticsRecorderTests.swift`.

**Verification**: `make verify-full` → all pass including the new tests.

## Done criteria

ALL must hold:

- [ ] `make verify` exits 0
- [ ] `make build` exits 0
- [ ] `make verify-full` exits 0 with no failures
- [ ] `grep -rn '"drive_401"' HealthMuleApp` returns no matches
- [ ] `grep -rn '"drive_reauthorization_required"' HealthMuleApp` returns exactly
      one match (the enum's raw value)
- [ ] A test exists mapping every `DriveAPIError` case to its produced code
- [ ] No file under `Sources/HealthMuleCore/` is modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- Step 1 shows something *can* produce bare `"drive_401"`.
- Removing a literal changes any string the app emits — the emitted vocabulary
  must be identical apart from the dead match.
- Sharing the vocabulary appears to require importing anything Drive-related
  into `Sources/HealthMuleCore/`, or changing `SyncFailureSummary`.
- An exported diagnostics consumer turns out to pin the exact strings in a way
  this refactor would break.

## Maintenance notes

- The dynamic `drive_<status>_<reason>` form still cannot be exhaustively
  enumerated, so `DiagnosticsRecorder`'s prefix matching stays. Keep the prefix
  in the shared type so the producer and matcher cannot disagree.
- A reviewer should diff the *emitted* strings, not just the code shape: the
  whole point is that behavior is unchanged.
- Deliberately deferred: whether these codes should be a typed value on
  `SyncFailureSummary` rather than a `String`. That would be cleaner but pushes
  Drive vocabulary into the Foundation-only core, which the repo rules forbid;
  it would need a different design.
