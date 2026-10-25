# Physical-device checklist

Simulator runs prove the app shell and deterministic contracts only. Use a real
iPhone for HealthKit, background, and real Drive behavior, and a paired Watch
for background Watch Connectivity. Record results in
[Notion](https://app.notion.com/p/3e5e75710b5281999cc8c6a31e5a9e5c), tied to
the tested build.

| Behavior | Simulator | Needs |
| --- | --- | --- |
| App shell, `make harness` | yes | none |
| Export and sync contracts | `make test-core` | none |
| HealthKit authorization and queries | fixtures only | iPhone |
| Aggregation, staging, Drive upload | fixtures, mocked Drive | iPhone |
| Background observer delivery | no | iPhone |
| Protected files, process-surviving uploads | no | iPhone |
| Watch sync request | `canRequestSync` is false | paired Watch |
| Background Watch snapshot delivery | no | paired Watch |

## Setup

Needs iOS 26+, watchOS 26+ for companion checks, an Apple Development team,
and a [Google iOS client](GOOGLE_OAUTH.md) whose bundle ID matches the build.

```sh
make verify-full
cp Config/Signing.xcconfig.example Config/Signing.xcconfig   # set bundle ID and team
make project
```

Open `HealthMule.xcodeproj`, confirm the HealthKit and Background Delivery
capabilities, and run on the iPhone. The Watch app installs with the bundle ID
plus `.watchkitapp`. Use a disposable Drive account for destructive or
failure-injection checks, never live health exports.

## Onboarding and permissions

- [ ] A fresh install shows the Home and Settings tabs.
- [ ] Setup, Sync details, and per-metric Health Data drill-ins return to Home; the tab bar never covers content.
- [ ] The app requests read-only HealthKit access, never write.
- [ ] Disable Sleep and Body Mass before the first request: the sheet omits both, their cards say Not included, and no observer or query runs for them.
- [ ] Enable one afterward: setup says Review needed, the type says Not requested, and sync excludes it until the follow-up request completes.
- [ ] Grant all types: the status screen shows readable samples.
- [ ] Deny one type: the UI says "No readable data", never that access was denied.
- [ ] Make the authorization-status query fail: the UI shows Check failed, not Request complete. A previously completed request keeps querying visible types; a never-completed one stays blocked.
- [ ] Connect Google: `Apple Health Sync` and its `daily` folder are found or created.
- [ ] Move the root folder within My Drive and relaunch: the app finds it by ID or app properties.
- [ ] Trash the root or `daily` folder and Try Drive Again: a new tree gets every local day and a fresh manifest; nothing uploads to the old folder.
- [ ] Switch Google accounts: every staged day and a fresh manifest publish before Up to date. Switch back: no duplicate files.

## Foreground sync

- [ ] A 30-day backfill creates one JSON file per date plus a manifest.
- [ ] Backfill progress counts days while staging, then files while uploading; it never sits at 100% through the upload.
- [ ] Retry pending uploads shows upload progress.
- [ ] A second sync without source changes creates no duplicate and no semantic rewrite.
- [ ] Adding or editing a workout updates only affected dates and the manifest.
- [ ] Missing or unreadable values are explicit `null`.
- [ ] Steps from both iPhone and Watch are not double-counted.
- [ ] Overlapping sleep intervals are unioned.
- [ ] Workouts are de-duplicated; totals are deterministic.
- [ ] Exports contain no routes, raw heart-rate samples, or unapproved fields.
- [ ] The manifest updates only after every daily file succeeds.

## Watch companion

- [ ] Before the first snapshot, the Watch says Waiting for iPhone and offers Retry iPhone; never Ready, never an endless spinner.
- [ ] The Watch shows only readiness, sync activity, last-success time, and queue counts: no health values, account details, Drive IDs, or error strings.
- [ ] Pending, retryable, and blocked work each show as a separate nonzero row, beside Last confirmed.
- [ ] With the iPhone reachable, Sync reports the request accepted before reconciliation finishes.
- [ ] Without reachability, Sync is unavailable and the headline says Phone Unavailable, never Up to Date.
- [ ] A snapshot older than 30 minutes shows as out of date with its last confirmed time and counts, never Up to Date.
- [ ] After reachability returns, a new request publishes a fresh snapshot.
- [ ] Leave the Watch app; after background delivery, the latest snapshot appears on reopen.

## Background

- [ ] With the app backgrounded, a new Health sample eventually updates its daily record.
- [ ] An app-refresh task records one Background refresh receipt; the schedule row says Submitted, Existing request kept, or a closed failure reason.
- [ ] Interrupting connectivity during an upload causes a retry of the same operation, with no duplicate files.
- [ ] Switch accounts or replace the folder tree while an upload waits for connectivity: the new destination is not Connected until the old transfer gets a definitive HTTP response. If draining times out, Drive stays unavailable for retry. Reconnecting the unchanged destination keeps its transfer scheduled.
- [ ] With connectivity down for over 15 seconds, the visible sync returns to pending while the background transfer stays scheduled.
- [ ] Locking the device during staging handles protected files safely after first unlock.
- [ ] Terminating the app during an upload lets the transfer reconcile after relaunch.
- [ ] After a force-quit, nothing promises background execution before the next launch.

Simulate a refresh task during development from LLDB. This does not prove
observer delivery, surviving uploads, or relaunch recovery
([Apple](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development)).

```text
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"dev.uinaf.healthmule.refresh"]
```

## Privacy and resilience

- [ ] Console logs hold no health values, OAuth tokens, Drive file bodies, or raw HealthKit metadata.
- [ ] Shared diagnostics stay bounded and redacted.
- [ ] Outbox, anchor, day-boundary, and activity-receipt files use data protection and are excluded from backups.
- [ ] The activity-receipt file holds at most 20 entries with no health values, record bodies, metadata, tokens, account details, or Drive IDs.
- [ ] Disconnect or reset never deletes Drive exports.
- [ ] Cancelling each destructive Settings confirmation changes nothing. Move Drive Exports to Trash moves only tagged exports, leaves other files and folders, and disconnects Google.
- [ ] Interrupt that cleanup midway and relaunch: uploads stay paused; explicit sign-in republishes the preserved records.
- [ ] Revoking Google access leads to a recoverable Reconnect state.
- [ ] Sign in, kill the app before the queue resumes, relaunch: restored credentials unblock the queued reauthorization work.
- [ ] Launching offline shows a temporary Google failure; going online and foregrounding restores it without a new grant.

## Evidence

Record app version or commit, iOS version, permission combination, foreground
or background state, and result. Strip health values, account and device
identifiers, and tokens from screenshots and diagnostics.
