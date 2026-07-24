# Health Relay — Apple Health to Google Drive

Status: implementation-ready v1 specification
Target: native iPhone app
Suggested stack: Swift 6, SwiftUI, HealthKit, Google Drive API v3
Minimum deployment target: iOS 18

## Problem

Apple Health's built-in full export is manual, large, and unsuitable for an
ongoing personal fitness project. Build a private iPhone app that reads a small
allowlist of fitness metrics, normalizes them into stable daily JSON records,
and incrementally uploads those records to a user-controlled Google Drive
folder. A separate trusted agent can then ingest the records into a calorie,
weight, and training tracker without receiving unrelated medical data.

## Product Principles

- Private by default: no developer backend, analytics SDK, ads, or third-party
  health-data processor.
- Read-only HealthKit access.
- Least-privilege Google Drive access.
- Idempotent incremental sync rather than repeated full exports.
- A missed background run is recoverable the next time the app opens or runs.
- The on-disk JSON contract is the product boundary and must remain stable.

## Requirements

### R1 — HealthKit Authorization

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

The setup screen must explain each requested type. Request and query only the
currently enabled subset; enabling a new type must return setup to Health access
review before that type is queried. The app must still function when any subset
is denied. It must never request write access.

### R2 — Google Drive Authorization

Use Google OAuth with the `drive.file` scope. Do not request unrestricted Drive
access.

On first setup:

1. Sign in with Google.
2. Create an app-owned folder named `Apple Health Sync` in My Drive.
3. Store its immutable Drive folder ID locally.
4. Tell the user they may move that folder anywhere in their Drive; uploads
   continue by folder ID.

If the local ID cache is unavailable, rediscover an app-tagged root across My
Drive without assuming it remains directly under `root`. Accept only a live
folder that still has a My Drive parent, then recover its `daily` child by the
root's immutable ID. Do not create a duplicate tree while that tagged folder is
discoverable.

Store OAuth credentials in Keychain. Provide explicit Disconnect and Reconnect
actions.

### R3 — Daily Export Contract

Write one file per local calendar day:

```text
Apple Health Sync/
├── manifest.json
└── daily/
    ├── 2026-07-23.json
    └── 2026-07-24.json
```

Each daily file must conform to this schema:

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
    "workoutMinutes": 83.0,
    "workoutActiveEnergyKcal": 475.0
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
- Known decimal measurements are rounded to the nearest value with at most two
  fractional digits, with exact half values rounded away from zero, before
  semantic comparison and encoding. Steps remain integers; `null` and unknown
  future fields are not quantized.
- All timestamps are ISO 8601 with UTC offset.
- Do not include GPS routes, raw heart-rate series, clinical records,
  medications, symptoms, reproductive data, or free-text metadata.
- Preserve unknown future fields when decoding a previously written record.
- Preserve unknown numeric values exactly when their coefficient has at most 38
  significant decimal digits after insignificant leading and trailing zeroes
  are removed. Reject wider values before decoding instead of rounding them.

### R4 — Aggregation Semantics

- Steps, active energy, and resting energy: cumulative sum for the local day.
- Weight: latest authorized sample in the local day.
- Resting heart rate and HRV: arithmetic mean of authorized samples in the
  local day.
- VO₂ max: latest authorized sample on or before the end of the local day;
  include `null` when none exists in the selected history window. Include the
  selected carry-forward sample in source provenance without double-counting
  its UUID. Older staged records do not widen the active selected-history
  boundary after the user narrows the range.
- Sleep: sum asleep-stage intervals for the sleep session ending on that local
  date. Exclude `awake` and `inBed`; de-duplicate overlapping intervals. Source
  names and sample counts must exclude earlier sessions read only to identify
  the selected session. Use a bounded look-ahead and do not publish a fragment
  until the maximum inter-fragment gap has elapsed, so a pre-midnight fragment
  cannot also be exported as part of the following day's session.
- Workouts: export each authorized `HKWorkout` once by UUID. Derive daily
  workout totals from the rounded values in the exported workout list.
- Use HealthKit statistics queries for cumulative metrics so multiple sources
  are de-duplicated according to HealthKit semantics.

### R5 — Incremental and Idempotent Sync

- Keep an `HKQueryAnchor` per sample type in local application support storage.
- Use `HKObserverQuery` to learn that a type changed, then
  `HKAnchoredObjectQuery` to fetch deltas.
- Recompute and upsert the affected local dates.
- For sleep additions, edits, and deletions, also recompute the following local
  date as the bounded plausible session-ending day; preserve the sample's
  direct-date mapping so deletions can apply the same rule after relaunch.
- On every sync, also recompute a rolling three-day reconciliation window to
  capture late sleep, workout, or device synchronization without crossing the
  selected first export day.
- Upsert the existing Drive file instead of creating duplicates.
- A repeated sync with unchanged HealthKit data must produce the same semantic
  record and no duplicate Drive file.
- If upload fails, persist a retry item locally with exponential backoff.
- If artifact bytes are committed but their state revision is not, recover the
  pending revision on the next attempt without requiring a process restart.
- Never advance an anchor past data that has not been durably staged locally.
- Retain a deleted sample's UUID-to-date mapping until the anchor that consumed
  that deletion is durably written.

### R6 — Manifest

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

### R7 — Initial Backfill

During onboarding, let the user choose:

- Last 30 days
- Last 90 days
- Custom start date

Default to 30 days. Process the backfill in bounded day-sized batches and show
progress. It must resume after interruption without duplicating records.

### R8 — Background Behavior

- Enable HealthKit background delivery for the allowlisted data types.
- Register observer queries at app launch.
- Use `BGAppRefreshTask` as a fallback reconciliation trigger.
- Use a background `URLSession` for pending Drive uploads.
- Background timing is best-effort; the UI must never promise an exact schedule.
- Opening the app always triggers a reconciliation and retry pass.

### R9 — User Interface

The app has four small screens:

1. **Setup**
   - HealthKit authorization state
   - Google connection state
   - Drive folder name and open-in-Drive action
   - Backfill range
2. **Status**
   - Last successful sync
   - Latest exported date
   - Pending upload count
   - Per-metric permission/last-sample status
3. **Sync**
   - Sync Now
   - Retry Failed Uploads
   - Rebuild Last 3 Days
4. **Settings**
   - Metric toggles within the approved allowlist
   - Export diagnostics
   - Disconnect Google
   - Reset local sync state

Resetting local state must not delete Drive data without a separate destructive
confirmation.

### R10 — Diagnostics and Privacy

- Log sync lifecycle, counts, durations, Drive file IDs, and error codes.
- Never log health values, OAuth tokens, file contents, or raw HealthKit
  metadata.
- Provide an in-app Share Diagnostics action that exports redacted JSON.
- Use `OSLog` privacy annotations.
- No telemetry leaves the device except the selected normalized records sent to
  the user's Google Drive.

## Architecture

Suggested modules:

```text
App/
├── UI/
├── HealthKitClient/
├── Aggregation/
├── ExportSchema/
├── DriveClient/
├── SyncEngine/
├── Persistence/
└── Diagnostics/
```

Key interfaces:

```swift
protocol HealthDataReading {
    func authorize() async throws
    func dailyRecord(for date: Date, calendar: Calendar) async throws
        -> DailyHealthRecord
    func changedDates() async throws -> Set<Date>
}

protocol ExportDestination {
    func upsert(record: DailyHealthRecord) async throws
    func update(manifest: ExportManifest) async throws
}

actor SyncEngine {
    func initialBackfill(from startDate: Date) async
    func reconcile(trigger: SyncTrigger) async
    func retryPendingUploads() async
}
```

Use dependency injection so aggregation and sync logic can be tested without
HealthKit or Google.

## Drive Upload Rules

- Daily JSON files are expected to stay well below 5 MB; use multipart uploads.
- Search for the file by exact name within the configured parent folder once,
  then cache its Drive file ID.
- Update by file ID on later syncs.
- Treat HTTP 401 as reauthorization required.
- Retry 408, 429, and 5xx with exponential backoff and jitter.
- Do not retry other 4xx responses indefinitely.
- Serialize uploads to prevent two background triggers racing on the manifest.

## Conformance Fixtures

Commit language-independent fixtures under `Tests/Fixtures/`:

- `multiple-sources.json`: steps from Watch and iPhone do not double count.
- `overlapping-sleep.json`: overlapping sleep stages produce one duration.
- `missing-permissions.json`: denied metrics serialize as `null`.
- `late-workout.json`: a workout arriving two days late updates that day.
- `timezone-change.json`: travel does not rename already exported dates.
- `idempotent-sync.json`: two identical syncs produce one Drive file.
- `failed-upload.json`: anchor and manifest behavior remain recoverable.

The fixture format may use simplified sample objects rather than archived
HealthKit instances, but expected output must be exact JSON.

## Acceptance Criteria

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
- AC10: `xcodebuild test` succeeds from a clean checkout with documented setup.

## Constraints

- HealthKit and background delivery must be tested on a physical iPhone; the
  simulator is insufficient for the end-to-end proof.
- iOS controls background launch timing. The app guarantees eventual
  reconciliation, not a fixed export time.
- Google OAuth client configuration and Apple signing entitlements are supplied
  at build time and never committed as secrets.
- The repository and exported schema must not contain a personal email address,
  Drive folder ID, OAuth token, or other user-specific credential.
- Existing exported dates retain their original local-date filenames after a
  timezone change; the rolling reconciliation window uses the current timezone
  only for newly affected samples.

## Non-goals

- Calorie or macro tracking inside the iPhone app.
- Medical advice, diagnosis, alerts, or interpretation.
- Writing any data back to Apple Health.
- Continuous heart-rate streaming.
- GPS route export.
- Android support.
- A hosted backend, multi-user accounts, or public sharing.
- Perfectly timed background synchronization.

## Implementation Order

1. Define Codable schema, fixtures, and aggregation tests.
2. Implement HealthKit authorization and foreground daily queries.
3. Implement local staging, anchors, and the three-day reconciliation engine.
4. Add Google OAuth, Drive folder creation, and idempotent upserts.
5. Add onboarding, status UI, manual sync, and diagnostics.
6. Add observer queries, background delivery, app refresh, and background
   uploads.
7. Run physical-device conformance tests and reconcile code/spec differences.

## Upstream References

- [Setting up HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)
- [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Executing observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries)
- [Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
- [Google Drive uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
