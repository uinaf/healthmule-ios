# Plan 005: Move the Drive file-ID map out of backed-up `UserDefaults` into protected storage

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat db7dd06..HEAD -- HealthMuleApp/Google/DriveMetadataStore.swift HealthMuleApp/Google/DriveAPIClient.swift HealthMuleApp/App/AppModel.swift Sources/HealthMuleCore/Sync/FileSyncStore.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none (but land plans 001-004 first; this is the riskiest)
- **Category**: security
- **Planned at**: commit `db7dd06`, 2026-08-02

## Why this matters

`DriveMetadataStore` persists a `fileIDs: [String: String]` map into
`UserDefaults.standard`. Its keys have the form `daily:<yyyy-mm-dd>` — one entry
per exported day. `UserDefaults` writes a preferences plist that **is included
in encrypted iCloud and Finder backups by design**.

So a device backup contains a per-day enumeration of exactly which dates the
user exported health data for, plus the Drive object ID for each of those days.
That is a health-activity timeline plus the identifiers needed to fetch the
bodies from Drive.

This contradicts a boundary the repo states explicitly. `docs/ARCHITECTURE.md`
records that the no-backup rule exists because Apple's App Review Guidelines
prohibit storing personal health information in iCloud, and **every file-backed
store honors it** — `FileSyncStore`, `HealthAnchorStore`, `DayBoundaryStore`, and
the background upload bodies all set a protection class and
`isExcludedFromBackup`. `UserDefaults` is the one hole, and the doc's coverage of
`DriveMetadataStore` only claims "IDs contain no record bodies" — it never
addresses the backup surface. This is drift, not a recorded tradeoff.

The same applies, less acutely, to `metrics.enabled` and `backfill.customStart`.

## Current state

Files:

- `HealthMuleApp/Google/DriveMetadataStore.swift` — the store. An actor with a
  fully encapsulated API, which is what makes this tractable.
- `HealthMuleApp/Google/DriveAPIClient.swift` — builds the cache keys.
- `HealthMuleApp/App/AppModel.swift` — composition root (`AppModel.live()`);
  also writes `backfill.customStart` and `metrics.enabled` to
  `UserDefaults.standard`.
- `Sources/HealthMuleCore/Sync/FileSyncStore.swift` — **the pattern to copy**.

The key shape, `HealthMuleApp/Google/DriveAPIClient.swift:370`:

```swift
        let cacheKey = [kind, date].compactMap { $0 }.joined(separator: ":")
```

`kind` is a fixed vocabulary and `date` is `yyyy-mm-dd`, so keys read
`daily:2026-07-23`.

The persistence, `HealthMuleApp/Google/DriveMetadataStore.swift:29-41` and
`:236-241`:

```swift
    private static let stateKeyPrefix = "drive.metadata.v2"

    private let defaults: UserDefaults
    ...
    init(
        defaults: UserDefaults = .standard,
```

```swift
    private func persist(_ state: State, for accountID: String) {
        let key = Self.stateKey(for: accountID)
        states[key] = state
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
```

The load path at `:220-231` reads `defaults.data(forKey:)` and decodes `State`,
caching in the in-memory `states` dictionary.

The protection pattern to copy, `Sources/HealthMuleCore/Sync/FileSyncStore.swift:764-774`:

```swift
    private static func protectAndExcludeFromBackup(_ url: URL) throws {
        ...
                .protectionKey:
        ...
        values.isExcludedFromBackup = true
```

Read that whole function and the write path around `:741-754` — it writes
atomically with `.completeFileProtectionUntilFirstUserAuthentication` and then
applies the protection attributes. Match it exactly.

Note the protection class matters: `DriveMetadataStore` is read on the
background-upload path, which can run while the device is locked, so
`.completeFileProtectionUntilFirstUserAuthentication` (what `FileSyncStore`
uses) is correct. Do **not** use `.complete`.

Repo conventions:

- `Sources/HealthMuleCore` stays Foundation-only. `DriveMetadataStore` lives in
  the app layer, so it may not import the core's private helpers — you will need
  an equivalent local helper, or to make the core's helper internal-shared.
  Prefer a local one in the app layer; do not widen core API for this.
- `AppModel.live()` is the composition root; construct the new storage there.
- Never log the account ID, Drive IDs, or file names. The store already hashes
  the stable user ID for its namespace — preserve that.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Fast gate | `make verify` | exit 0 |
| Compile | `make build` | exit 0 |
| Full iOS + Simulator gate | `make verify-full` | exit 0, 148+ tests pass |
| Drive tests only | see note below | all pass |

`HealthMuleTests/DriveAPIClientTests.swift` is ~5,000 lines and is the main
harness for this subsystem. Run the whole suite via `make verify-full`;
`make verify-full` requires a full Xcode and the target Simulator **already
booted** (plan 001).

## Scope

**In scope**:
- `HealthMuleApp/Google/DriveMetadataStore.swift`
- `HealthMuleApp/App/AppModel.swift` — only the `AppModel.live()` construction
  of `DriveMetadataStore`
- A new file for the protected storage adapter, e.g.
  `HealthMuleApp/Google/DriveMetadataFileStore.swift`
- `HealthMuleTests/DriveAPIClientTests.swift` — migration tests
- `docs/ARCHITECTURE.md` — update the persistence/privacy section

**Out of scope** (do NOT touch):
- `DriveMetadataStore`'s **public API** and its concurrency model. Callers,
  destination-generation logic, and the pending/committed file-ID state machine
  must be unchanged. This is a storage-backend swap, nothing else.
- `Sources/HealthMuleCore/**`.
- `metrics.enabled` and `backfill.customStart`. They have the same problem but
  are a smaller, separable follow-on; moving them here widens the blast radius
  of a MED-risk change. Note them in the maintenance section instead.
- The background upload transport's own file handling — already protected.

## Git workflow

- Branch: `advisor/005-move-drive-metadata-out-of-userdefaults`
- Conventional commits, e.g.
  `fix(security): keep Drive file IDs out of device backups`
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Add a protected file-backed storage adapter

Create a small type with the same read/write shape the store needs today —
"load `Data?` for a key" and "write `Data` for a key" — backed by one JSON file
per account namespace under Application Support, written atomically with
`.completeFileProtectionUntilFirstUserAuthentication` and marked
`isExcludedFromBackup`. Reuse the account-namespace hashing already in
`DriveMetadataStore.accountNamespace(for:)` for the filename so the account ID
never appears on disk.

Define the storage as a protocol with two implementations — the file-backed one
and an in-memory one for tests — so tests do not touch the real filesystem or
the host's defaults.

**Verify**: `make build` → exit 0.

### Step 2: Swap the backend behind the unchanged API

Replace the `defaults` dependency in `DriveMetadataStore` with the new storage
protocol. Keep `states` in-memory caching exactly as-is. The public API must not
change.

Update `AppModel.live()` to construct the file-backed implementation rooted in
the same Application Support directory the staging root uses.

**Verify**: `make build` → exit 0. Then `make verify-full` → exit 0 *before*
adding migration, to confirm the swap alone is behavior-preserving.

### Step 3: Migrate existing installs, once

On first load for an account namespace, if the protected file is absent and a
`drive.metadata.v2.*` key exists in `UserDefaults.standard`, decode it, write it
through to the protected file, then **remove the defaults key**.

This must be idempotent and must never lose file IDs — losing them causes
duplicate Drive files, which is the failure this subsystem exists to prevent.
If the protected write fails, do **not** delete the defaults key.

**Verify**: the migration tests in "Test plan" pass.

### Step 4: Update the documentation

`docs/ARCHITECTURE.md` describes the persistence and privacy boundary and
currently addresses `DriveMetadataStore` only in terms of "IDs contain no record
bodies". Update it to state where the metadata now lives and that it is
protected and backup-excluded.

**Verify**: `make verify` → exit 0 (`test-infrastructure.sh` gates some doc
claims).

## Test plan

Model on the existing destination-generation and file-ID tests in
`HealthMuleTests/DriveAPIClientTests.swift` — find them with
`grep -n "fileIDSnapshot\|PendingFolderTransition" HealthMuleTests/DriveAPIClientTests.swift`.

New cases:

1. **Round-trip**: write state through the store, construct a fresh store over
   the same storage, read back identical file IDs and statuses.
2. **Migration happy path**: seed an in-memory `UserDefaults` (use
   `UserDefaults(suiteName:)`, never `.standard`) with a `drive.metadata.v2.*`
   payload, load, assert IDs are intact, the protected file now holds them, and
   the defaults key is gone.
3. **Migration is idempotent**: run load twice; the second must not fail or
   duplicate.
4. **Migration failure is safe**: with a storage stub whose write throws, assert
   the defaults key is **retained** and no IDs are lost.
5. **No regression in destination transitions**: the existing
   `testPendingFolderTransitionClearsFileIDsAfterStoreReload` (and siblings)
   must pass unchanged — they are the real proof that the state machine survived
   the swap.

**Verification**: `make verify-full` → all pass, including the ~49 existing
Drive tests plus the new ones.

## Done criteria

ALL must hold:

- [ ] `make verify` exits 0
- [ ] `make build` exits 0
- [ ] `make verify-full` exits 0 with no failures; existing Drive tests pass
      unchanged
- [ ] `grep -n "UserDefaults" HealthMuleApp/Google/DriveMetadataStore.swift`
      shows defaults used **only** by the one-time migration read/removal
- [ ] The written metadata file has a protection class and
      `isExcludedFromBackup` set (assert in a test, not by inspection)
- [ ] `DriveMetadataStore`'s public method signatures are unchanged
      (`git diff` shows no call-site changes outside `AppModel.live()`)
- [ ] No file under `Sources/HealthMuleCore/` is modified
- [ ] `docs/ARCHITECTURE.md` describes the new location
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- The excerpts above do not match the live code.
- Any existing Drive test fails after Step 2. That means the swap was not
  behavior-preserving — diagnose, do not adjust the test to pass.
- The migration cannot be made safe against a partial write. Losing file IDs
  causes duplicate Drive files for the user; a design that risks that is worse
  than the backup exposure it fixes.
- You conclude the file-ID map should be folded into `FileSyncStore`'s state
  file. That may well be the better end state, but it merges two independently
  versioned stores and needs its own decision record.

## Maintenance notes

- `metrics.enabled` and `backfill.customStart` remain in `UserDefaults.standard`
  and remain in backups. They leak far less (a metric set and a start date, no
  per-day enumeration) but the same argument applies — worth a follow-on, or an
  explicit note in `docs/ARCHITECTURE.md` stating which keys are accepted in
  backup and why.
- A reviewer should scrutinize the migration path above everything else. The
  storage swap is mechanical; the migration is where user data can be lost.
- The protection class must stay
  `.completeFileProtectionUntilFirstUserAuthentication`. Tightening it to
  `.complete` would break background uploads while the device is locked.
- Deliberately deferred: the OAuth bearer token that background `URLSession`
  serializes to its own task store (a separate, bounded exposure that likely
  needs Drive resumable uploads to fix properly).
