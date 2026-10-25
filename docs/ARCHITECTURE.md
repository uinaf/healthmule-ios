# Architecture

Invariants the code must keep. [`HealthMuleCore`](../Sources/HealthMuleCore)
owns schema, aggregation, and durable sync with Foundation only.
[`HealthMuleShared`](../HealthMuleShared) owns companion messages.
[`HealthMuleApp`](../HealthMuleApp) adapts HealthKit, Drive, and background
execution; [`AppModel`](../HealthMuleApp/App/AppModel.swift) wires them.

## Export and sync

1. A daily artifact has identity `daily:<yyyy-mm-dd>` and path
   `daily/<yyyy-mm-dd>.json`; the manifest has identity `manifest`. A date's
   stored timezone stays authoritative when it is restaged.
2. Missing metrics and optional workout values encode as JSON `null`.
3. Unknown fields survive decode, update, and re-encode.
4. Semantic equality ignores `generatedAt` and collection order, so HealthKit
   floating-point noise never creates a revision.
5. A manifest is staged only when every local daily revision is current
   remotely.
6. Transient failures back off exponentially with jitter, and automatic
   triggers respect the retry date; only explicit Retry bypasses it.
   Authorization failures resume only after credentials are restored.
   Permanent failures stay blocked and never show as retryable.
7. A new Google account or replacement folder tree is a new destination.
   Before it syncs, every local day is marked pending, manifest state and the
   last-success time are cleared, and the full snapshot republishes.
8. `LiveSyncCoordinator` runs reconciliation, observer staging, uploads, and
   reset through one FIFO single-flight gate. All triggers, Watch requests
   included, feed this one path.
9. Daily bytes are written before their state revision commits. If the commit
   fails, the next attempt detects the mismatch and restores the retry item.

### Sync store migration and rollback

`FileSyncStore` uses a v2 index of SHA-256 digests and byte counts;
`daily/<date>.json` is the only copy of record content. Recovery migrates a v1
index, saves it once as `sync-state.v1.json`, then publishes v2 atomically.
Older builds cannot read v2. To roll back, restore that frozen v1 copy, which
holds only pre-migration revisions, or delete the index and recover from the
artifact files. Decision record:
[Notion](https://app.notion.com/p/3e5e75710b5281999cc8c6a31e5a9e5c).

### Reconciliation scope

- Stage every affected date durably before committing its `HKQueryAnchor`.
- Each pass covers today and up to two previous days, never before the
  selected start, plus anchored change dates and missing days in the range.
- The selected start persists as a local `yyyy-MM-dd` date, so "Last 30 days"
  does not slide at midnight or while traveling. If a timezone change puts it
  ahead of today, reconciliation waits instead of moving it back.
- Backfill persists one day at a time and resumes from missing dates.
  Observer staging and Retry also fill gaps in the selected range.
- Settings locks metric and history controls during visible work. Each
  accepted change schedules one serialized follow-up pass.
- A metric selection change rebuilds every local date, so values of disabled
  metrics are scrubbed before the next upsert.
- A bumped export-contract revision restages every date once and requeues it
  for upsert by Drive ID, without deleting local recovery state.
- Cancellation is checked between pages, samples, and metrics, and throws
  before a batch is staged or committed.

## HealthKit

- Request an empty write set and only the enabled subset of the
  [spec's read types](specs/healthkit-drive-exporter.md#r1-healthkit-authorization).
  A newly enabled type returns setup to **Review needed** before any query,
  observer, or export includes it.
- HealthKit never reveals read denial; `authorizationStatus(for:)` covers
  writes only. Never present "Request complete" or a readable-type count as
  proof of granted reads; a denied or empty type shows **No readable data**.
- Metric switches control the app's own selection; they never claim to revoke
  system permissions.
- Register observers first in bootstrap, only for enabled, requested types.
- `HealthAnchorStore` keeps one anchor per metric plus a UUID-to-date index for
  `HKDeletedObject`. Persist new sample mappings before the anchor; keep
  deletion mappings until that anchor is durable.
- Each metric stores its query boundary with its anchor. Widening history
  resets that anchor and replays.
- Concurrent observer uploads share one drain: requests during an upload cause
  at most one follow-up pass.
- Bootstrap resolves Health request state before replaying uploads unblocked by
  restored Google credentials.
- The active selected start bounds VO₂ carry-forward, even after narrowing the
  range.
- Foreground refresh keeps the last known authorization and metric results
  until new ones arrive; it never swaps them for placeholders or re-expands
  completed setup cards.
- Active work and user-initiated results show as banners; automatic results go
  to activity history only. A failed user retry keeps its specific error.

### Day boundaries

`DayBoundaryStore` persists the timezone and exact start and end first used for
a date, so travel never reinterprets or renames an exported day. New boundaries
reach memory only after their atomic write succeeds.

### Sleep

- Queries add a 24-hour lookback and a four-hour look-ahead.
- A cluster is not exported until four hours pass after its latest fragment,
  so a pre-midnight fragment never lands on two dates.
- A sleep change rebuilds its overlapped dates plus the next plausible
  session-ending date; deletion replay applies the same rule.
- Provenance counts only the cluster ending on the exported day.

## Google Drive identity

**Connected** requires all of:

1. GoogleSignIn restored or obtained `drive.file`.
2. Google supplied a stable user ID.
3. The managed root and `daily` folders were recovered or created for that
   account.
4. No newer disconnect or account switch superseded the activation.

Sync also needs protected local staging; if it fails, Google stays Connected
while Home and Sync report a storage error.

- File and folder IDs are cached per account in `DriveMetadataStore`, keyed by
  the SHA-256 of the stable user ID; the raw ID is never a key or logged.
- Discovery uses private `appProperties` `healthMuleKind` and
  `healthMuleDate`. Root discovery searches all of My Drive, so a moved tree is
  recovered, not duplicated. `daily` discovery stays under the verified root.
- Folders are validated by MIME type, trash state, and parent on discovery
  only; uploads use the activation's folder IDs.
- Creates supply Drive-generated IDs, so an ambiguous retry resolves as success
  or `409 Conflict`. Updates `PATCH` by file ID.
- A generated ID is `pendingCreate` until a definitive success marks it
  `committed`. A validation `404` reuses a pending ID but replaces a committed
  one after rediscovery.
- The destination namespace is a SHA-256 of account, root, and `daily` IDs. A
  change resets only upload state, behind the single-flight gate; local files
  and anchors stay. Generation-checked cache writes stop a stale upload from
  restoring cleared IDs.
- `AppModel` epochs every connection transition, so a late response from an
  older account changes nothing.

### Reset and trash

- **Reset Local Sync State** keeps Drive IDs and day boundaries, clears anchors,
  staged records, the local manifest, and retry state, then rebuilds the
  selected range. It never deletes Drive files.
- **Disconnect** revokes access and signs out; it never deletes Drive files.
- **Move Drive Exports to Trash** finds every accessible tagged daily export and
  manifest before trashing any, and leaves folders and other files alone.
  Uploads drain first. A persisted pause blocks automatic Google restore until
  explicit sign-in. Success disconnects Google; failure reports the count and
  keeps the pause.

## Drive transport

- Metadata calls use an in-process session; multipart uploads use a background
  `URLSession` with protected, backup-excluded body files. Task descriptions
  hold only opaque SHA-256 keys and a local filename.
- Changing the destination invalidates client state, then drains old-key tasks
  to a definitive HTTP response before publishing. Client cancellation never
  proves Drive rejected an upload. Only a drain timeout leaves the destination
  unavailable for retry. Tasks for an unchanged key survive reconnect.
- Identical in-process operations share one transfer; others run in FIFO
  reservation order. Upserts reserve a FIFO lane per account, destination, and
  artifact before their first suspension, so two calls never mint competing
  file IDs.
- Reconciliation waits at most 15 seconds on a scheduled transfer, then
  records a retryable timeout and releases the gate without cancelling it.
- A transfer that finishes without its waiter is retried with the same file ID
  and reconciled idempotently.
- The first upload `401` refreshes the token and retries once; a second `401`
  requires reauthorization. Retry and reauthorization rules:
  `DriveAPIError.isRetryable` in
  [`DriveAPIClient.swift`](../HealthMuleApp/Google/DriveAPIClient.swift).

## Watch companion

- `CompanionSyncSnapshot` carries readiness, sync activity, timestamps, and
  queue counts only.
- Snapshot equality ignores `generatedAt`; a timestamp-only change neither
  republishes nor completes a request. Publishing writes application context
  and queues a user-info transfer after cancelling the outstanding one.
  Activation and pairing changes invalidate the publication cache.
- `CompanionStatusModel`: a snapshot is current for 30 minutes; a future
  timestamp has unknown freshness; last success and queue counts stay shown
  when stale or unreachable.
- `CompanionRequestLifecycle` settles reply and snapshot in either order; the
  Watch keeps a 10-second accepted-state fallback. The next valid snapshot
  clears a stale delivery failure.

## Background execution

Background work is eventual and system-controlled. HealthKit observers are the
primary signal; `BGAppRefreshTask` is a fallback; a cold launch restores
services through the same bootstrap gate.

- Each automatic opportunity writes a receipt before it starts and closes it
  after; a receipt left running becomes `interrupted` on next load. Receipt
  writes never affect sync success.
- Receipts prove only an observed opportunity or a scheduling request, never
  cadence.
- If the refresh request is already pending, keep it; otherwise submit without
  cancelling. A task invocation schedules exactly once.

## Progress

Reconciliation reports **Staging** (days) then **Uploading** (daily artifacts).
The manifest publish is unreported, since whether it is due is known only after
every daily upload settles. Progress carries counts and an optional date only.

## Persistence and privacy

| Data | Storage | Rule |
| --- | --- | --- |
| OAuth credentials | GoogleSignIn Keychain | Never log, export, or copy tokens |
| Drive IDs | Per-account `UserDefaults` via `DriveMetadataStore` | Private in diagnostics |
| Destination namespace | SHA-256 digest in `UserDefaults` | No raw IDs |
| Metric and backfill choices | `UserDefaults` | No health values |
| Anchors, UUID index, day boundaries, staging, activity receipts | `Application Support/HealthMule/` | Complete-until-first-authentication protection; excluded from backup |
| Diagnostics | Memory plus an explicit share file | A closed event enum is the allowlist |

- Activity receipts: at most 20, with closed values and counts only. Corrupt
  state is reported, never overwritten.
- The no-backup rule follows Apple's
  [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
  ban on health data in iCloud.
- The privacy manifest declares Health and Fitness data as linked and used only
  for app functionality, and keeps the `UserDefaults` required-reason entry.
