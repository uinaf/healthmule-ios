# HealthMule: Apple Health to Google Drive

HealthMule incrementally exports an allowlist of Apple Health metrics as daily
JSON records in the user's Google Drive. The iPhone owns export and sync; the
Watch companion shows status and requests sync.

## Product principles

- Private by default: no developer backend, analytics SDK, ads, or third-party
  health-data processor.
- Read-only HealthKit access.
- Least-privilege Google Drive access.
- Idempotent incremental sync, not repeated full exports.
- A missed background run recovers the next time the app opens or runs.
- The JSON contract is the product boundary and stays stable.

## Requirements

### R1: HealthKit authorization

Request read access only for:

- Body mass
- Step count
- Active energy burned
- Basal/resting energy burned
- Resting heart rate
- Heart-rate variability SDNN
- VO₂ max
- Sleep analysis
- Workouts

The setup screen explains each requested type. Request and query only the
enabled subset; enabling a type returns setup to Health access review before
that type is queried. The app works with any subset denied. It never requests
write access.

### R2: Google Drive authorization

Use Google OAuth with only the `drive.file` scope.

On first setup:

1. Sign in with Google.
2. Create an app-owned folder named `Apple Health Sync` in My Drive.
3. Store its immutable Drive folder ID locally.
4. Tell the user they may move that folder anywhere in their Drive; uploads
   continue by folder ID.

Without the local ID cache, rediscover an app-tagged root anywhere in My Drive,
not only under `root`. Accept only a live folder with a My Drive parent, then
recover its `daily` child by the root's ID. Never create a duplicate tree while
the tagged folder is discoverable.

Store OAuth credentials in Keychain. Provide explicit Disconnect and Reconnect
actions.

### R3: Daily export contract

Write one file per local calendar day:

```text
Apple Health Sync/
├── manifest.json
└── daily/
    ├── 2026-07-23.json
    └── 2026-07-24.json
```

Each daily file conforms to this schema:

```json
{
  "schemaVersion": 1,
  "date": "2026-07-23",
  "timeZone": "Europe/Istanbul",
  "generatedAt": "2026-07-23T18:10:00+03:00",
  "metrics": {
    "weightKg": 82.9,
    "steps": 10432,
    "activeEnergyKcal": 1004.2,
    "restingEnergyKcal": 2016.0,
    "restingHeartRateBpm": 58.0,
    "hrvSdnnMs": 47.5,
    "vo2MaxMlKgMin": 41.2,
    "sleepMinutes": 468
  },
  "workouts": [
    {
      "id": "healthkit-uuid",
      "type": "traditionalStrengthTraining",
      "startedAt": "2026-07-23T07:03:00+03:00",
      "endedAt": "2026-07-23T07:59:00+03:00",
      "durationMinutes": 56.0,
      "activeEnergyKcal": 312.0,
      "distanceMeters": null
    }
  ],
  "totals": {
    "workoutMinutes": 56.0,
    "workoutActiveEnergyKcal": 312.0
  },
  "sources": {
    "deviceNames": ["Apple Watch", "iPhone"],
    "sampleCount": 184
  }
}
```

Rules:

- Missing or unauthorized values are `null`; never invent zero.
- Numeric values use SI/metric units shown in the field names.
- Round known decimal measurements to at most two fractional digits before
  semantic comparison and encoding. Start from the shortest round-trip decimal
  of each finite `Double`, and round halves away from zero: `1.005` becomes
  `1.01`, `4.015` becomes `4.02`, `-1.005` becomes `-1.01`. Values just below or
  above a midpoint stay on their side. Steps stay integers; `null` and unknown
  future fields are not rounded.
- Rounding applies to newly aggregated or encoded records. Exported records
  keep their values and semantic digests; an upgrade alone restages nothing.
  When sync rebuilds a day and a rounded value changes, the digest changes and
  the export restages. Historical regeneration needs an explicit user backfill.
- Timestamps are complete ISO 8601 values with a UTC offset and valid calendar
  dates; reject trailing content and out-of-range time components.
- Do not include GPS routes, raw heart-rate series, clinical records,
  medications, symptoms, reproductive data, or free-text metadata.
- Preserve unknown future fields when decoding a previously written record.
- Preserve unknown numeric values exactly up to 38 significant digits, after
  stripping leading and trailing zeroes. Reject wider values before decoding;
  never round them.

### R4: Aggregation semantics

- Steps, active energy, and resting energy: cumulative sum for the local day.
- Weight: latest authorized sample in the local day.
- Resting heart rate and HRV: arithmetic mean of authorized samples in the
  local day.
- VO₂ max: latest authorized sample on or before the end of the local day, or
  `null` when none exists in the selected history window. Include the
  carried-forward sample in provenance once by UUID. Older staged records never
  widen the selected history after the user narrows it.
- Sleep: sum asleep-stage intervals of the session ending on that local date.
  Exclude `awake` and `inBed`; de-duplicate overlaps. Source names and sample
  counts exclude earlier sessions read only to find the selected one. Use a
  bounded look-ahead, and hold a fragment until the maximum inter-fragment gap
  has passed, so a pre-midnight fragment never also lands on the next day.
- Workouts: export each authorized `HKWorkout` once by UUID. Derive daily
  workout totals from the rounded values in the exported workout list.
- Use HealthKit statistics queries for cumulative metrics, so HealthKit
  de-duplicates multiple sources.

### R5: Incremental and idempotent sync

- Keep an `HKQueryAnchor` per sample type in local application support storage.
- Use `HKObserverQuery` to learn that a type changed, then
  `HKAnchoredObjectQuery` to fetch deltas.
- Recompute and upsert the affected local dates.
- For sleep additions, edits, and deletions, also recompute the next local
  date as the plausible session-ending day; keep the sample's direct-date
  mapping so deletions apply the same rule after relaunch.
- Every sync also recomputes a rolling three-day window, for late sleep,
  workouts, or device sync, without crossing the selected first export day.
- Upsert the existing Drive file instead of creating duplicates.
- A repeated sync with unchanged HealthKit data must produce the same semantic
  record and no duplicate Drive file.
- If upload fails, persist a retry item locally with exponential backoff.
- If artifact bytes commit but their state revision does not, recover the
  pending revision on the next attempt, without a process restart.
- Never advance an anchor past data that has not been durably staged locally.
- Retain a deleted sample's UUID-to-date mapping until the anchor that consumed
  that deletion is durably written.

### R6: Manifest

Maintain `manifest.json`:

```json
{
  "schemaVersion": 1,
  "exporterVersion": "1.0.0",
  "timeZone": "Europe/Istanbul",
  "lastSuccessfulSyncAt": "2026-07-23T18:10:03+03:00",
  "earliestDate": "2026-07-01",
  "latestDate": "2026-07-23",
  "recordCount": 23
}
```

Update the manifest only after all daily-file uploads in that sync succeed.

### R7: Initial backfill

During onboarding, let the user choose:

- Last 30 days
- Last 90 days
- Custom start date

Default to 30 days. Process the backfill in day-sized batches and show
progress. It resumes after interruption without duplicating records.

### R8: Background behavior

- Enable HealthKit background delivery for the allowlisted data types.
- Register observer queries at app launch.
- Use `BGAppRefreshTask` as a fallback reconciliation trigger.
- Use a background `URLSession` for pending Drive uploads.
- Background timing is best-effort; the UI must never promise an exact schedule.
- Record bounded, privacy-safe receipts of automatic reconciliation
  opportunities and scheduling outcomes. Receipts show only what the app
  attempted or observed; they never imply cadence or future runs.
- Opening the app always triggers a reconciliation and retry pass.

### R9: User interface

**Home** and **Settings** are the only permanent tabs. Four product surfaces:

1. **Setup**, a Home drill-in:
   - HealthKit authorization state
   - Google connection state
   - Drive folder name and open-in-Drive action
   - Backfill range
2. **Status**, the Home summary and detail rows:
   - Last successful sync
   - Latest exported date
   - Pending upload count
   - Per-metric permission/last-sample status
   - Latest automatic activity and its relative time
3. **Sync**, a Home repair and activity drill-in:
   - Sync Now
   - Retry Failed Uploads
   - Rebuild Last 3 Days
   - Automatic/background receipts and schedule-request outcomes
4. **Settings**:
   - Metric toggles within the approved allowlist
   - Export diagnostics
   - Disconnect Google
   - Reset local sync state
   - Move accessible HealthMule Drive exports to Trash, with separate confirmation

Initial loading reserves the final layout and never flashes a persisted
failure before bootstrap restores current state. Automatic outcomes stay in the
activity surfaces, not in transient banners over the app shell. Completed setup
steps may collapse; incomplete steps stay expanded and actionable.

Resetting local state never deletes Drive data without a separate destructive
confirmation.

### R10: Diagnostics and privacy

- Log only allowlisted sync lifecycle events, counts, durations, and redacted
  error classifications.
- Never log health values, OAuth tokens, file contents, Drive identifiers,
  account identifiers, local paths, or raw HealthKit metadata.
- Provide an in-app Share Diagnostics action that exports redacted JSON.
- Use `OSLog` privacy annotations.
- No telemetry leaves the device except the selected normalized records sent to
  the user's Google Drive.

### R11: Apple Watch companion

A paired watchOS companion:

- displays only sanitized readiness, sync activity, last-success time, and
  pending and failure counts;
- combines snapshot freshness, activation, reachability, queue state, and
  request delivery, so stale or unreachable data never claims Up to Date;
- shows a waiting or retry state before the first valid snapshot;
- sends Sync Now only while the iPhone is reachable, acknowledges accepted
  requests promptly, and clears obsolete delivery failures on a later valid
  snapshot;
- never stores or receives OAuth tokens, Google account details, Drive IDs,
  exported records, raw health metadata, or health values.

The iPhone alone queries HealthKit, stages locally, holds Google OAuth, and
uploads to Drive. Watch requests enter the existing idempotent reconciliation
path; there is no second sync engine.

## Architecture

Aggregation and sync logic is deterministic and Foundation-only. HealthKit,
Google Drive, and Watch Connectivity sit behind injected adapters, so core
tests need neither HealthKit nor Google. Invariants:
[Architecture](../ARCHITECTURE.md).

## Drive upload rules

Use multipart uploads and immutable file IDs. Tagged-file discovery and
Drive-generated create IDs prevent duplicate logical files after ambiguous
responses ([Google Drive identity](../ARCHITECTURE.md#google-drive-identity)).
Serialize reconciliation so competing triggers cannot race the manifest.

`DriveAPIError` in
[`DriveAPIClient.swift`](../../HealthMuleApp/Google/DriveAPIClient.swift)
classifies retryable, reauthorization, and permanent failures. Background
uploads refresh and retry the first `401` once; a repeated `401` requires
reauthorization.

## Conformance fixtures

Commit language-independent fixtures under `Tests/Fixtures/`:

- `overlapping-sleep.json`: overlapping sleep stages produce one duration.
- `missing-permissions.json`: denied metrics serialize as `null`.
- `late-workout.json`: a workout arriving two days late updates that day.
- `timezone-change.json`: travel does not rename already exported dates.
- `idempotent-sync.json`: two identical syncs produce one Drive file.
- `failed-upload.json`: anchor and manifest behavior remain recoverable.

Fixtures may use simplified sample objects instead of archived HealthKit
instances; expected output is exact JSON.

## Acceptance criteria

- AC1: A fresh install can authorize HealthKit, connect Google, and create its
  Drive folder without a developer-operated server.
- AC2: A 30-day backfill produces exactly one valid JSON record per local day
  (today minus 29 calendar days through today, inclusive) and one manifest,
  including days whose readable metric values are all `null`.
- AC3: Running Sync Now twice without new data creates no duplicate files and
  does not change semantic record content.
- AC4: New steps or a completed workout update the affected daily file after an
  observer/background/foreground reconciliation.
- AC5: Denying any individual HealthKit type does not block other exports and
  produces `null` for the denied metric.
- AC6: Route data, raw heart-rate series, and non-allowlisted health types never
  appear in exported files or logs.
- AC7: Upload interruption survives app termination and completes on a later
  retry without losing staged data.
- AC8: All aggregation fixtures pass in unit tests without an iOS device.
- AC9: HealthKit authorization, observer delivery, and a real Drive upload pass
  an on-device integration test.
- AC10: `make verify-full` succeeds from a clean checkout with the documented
  Xcode and booted-Simulator setup.
- AC11: A paired Watch truthfully distinguishes missing, stale, unreachable,
  and current phone state; displays only sanitized status; and can request a
  sync while the iPhone is reachable without receiving health or credential
  payloads.
- AC12: The deterministic Simulator harness covers startup loading, active
  sync, visible failure, blocked uploads, automatic activity, setup, settings,
  dark mode, and accessibility text without real health or credential data.

## Constraints

- HealthKit and background delivery need a physical iPhone for end-to-end
  proof.
- iOS controls background timing. The app guarantees eventual reconciliation,
  not a fixed export time.
- Google OAuth client configuration and Apple signing entitlements are supplied
  at build time and never committed as secrets.
- The repository and exported schema hold no personal email address, Drive
  folder ID, OAuth token, or other user-specific credential.
- Exported dates keep their original local-date filenames after a timezone
  change; the rolling window uses the current timezone only for newly affected
  samples.
