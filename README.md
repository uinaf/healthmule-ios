# HealthMule

An iPhone and Apple Watch app that exports a small, read-only set of Apple
Health metrics as daily JSON files in your Google Drive.

- The iPhone reads HealthKit, holds the Google grant, and uploads to Drive.
- The Watch shows sanitized sync status and can request a sync.
- No developer backend, analytics, ads, or telemetry.

## Quick start

Requires full Xcode with the iOS 26 and watchOS 26 SDKs and Simulator
runtimes, and Swift 6.

```sh
make project
make run
make verify
```

[Contributing](CONTRIBUTING.md) lists the other targets.
[Google OAuth setup](docs/GOOGLE_OAUTH.md) connects a real Drive account.

## Privacy

- HealthKit access is read-only and limited to the types in
  [`HealthMetric`](HealthMuleApp/HealthKit/HealthMetric.swift).
- Google access uses only the `drive.file` scope.
- Logs and diagnostics carry no health values, OAuth tokens, exported records,
  or raw HealthKit metadata.
- Local health staging uses file protection and is excluded from backups.

## Website

The [website](https://healthmule.uinaf.dev),
[privacy policy](https://healthmule.uinaf.dev/privacy/), and
[terms](https://healthmule.uinaf.dev/terms/) are static files in `website/`,
served by the Worker in [wrangler.jsonc](wrangler.jsonc). Preview:

```sh
python3 -m http.server 8765 --directory website
```

## Documentation

- [Google OAuth setup](docs/GOOGLE_OAUTH.md)
- [Physical-device checklist](docs/DEVICE_TESTING.md)
- [Security reporting](https://github.com/uinaf/.github/blob/main/SECURITY.md)
- [MIT License](LICENSE)
