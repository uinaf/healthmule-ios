# HealthMule

HealthMule is an open-source iPhone and Apple Watch app that exports a small,
read-only selection of Apple Health metrics as stable daily JSON files in your
Google Drive.

- The iPhone owns HealthKit access, Google authorization, protected local
  staging, and Drive uploads.
- The Watch companion displays sanitized sync status and can request a sync
  while the phone is reachable.
- There is no developer backend, analytics, ads, or telemetry.

Simulator fixtures cover app presentation and deterministic contracts. Use the
[physical-device checklist](docs/DEVICE_TESTING.md) for HealthKit, real Drive
uploads, background execution, and paired-Watch delivery. Release acceptance
status lives in [Notion](https://app.notion.com/p/3e5e75710b5281999cc8c6a31e5a9e5c).

## Quick start

Requirements:

- A full Xcode installation with the iOS 26 and watchOS 26 SDKs
- Matching iOS and watchOS Simulator runtimes for app builds and launches
- Swift 6

`make project` provisions the pinned [XcodeGen](https://github.com/yonaskolb/XcodeGen)
under `.artifacts/toolchain`; do not install it separately.

Generate the project and launch the phone app in the first available iPhone
Simulator. Xcode also builds and embeds the Watch companion:

```sh
make project
make run
```

Set `SIMULATOR_UDID` to target a specific available simulator:

```sh
SIMULATOR_UDID=<simulator-udid> make run
```

Capture deterministic UI states and a test summary:

```sh
make harness
```

Artifacts go under `.artifacts/agent-harness`. Set `HEALTHMULE_HARNESS_OUTPUT`
to choose another directory.

Google credentials are optional for the default build and automated tests.
Follow [Google OAuth setup](docs/GOOGLE_OAUTH.md) to connect a Drive account.

## Develop and validate

Run `make verify` for the fast required gate. App and UI changes also need an
appropriate Xcode or Simulator check. The complete command matrix and pull
request expectations live in [Contributing](CONTRIBUTING.md).

Release setup and TestFlight operations live in
[Notion](https://app.notion.com/p/3e5e75710b5281999cc8c6a31e5a9e5c).

## Website

The public [website](https://healthmule.uinaf.dev),
[privacy policy](https://healthmule.uinaf.dev/privacy/), and
[terms](https://healthmule.uinaf.dev/terms/) are static files in `website/`.
There is no build step or application server. Preview with
`python3 -m http.server 8765 --directory website`.

[wrangler.jsonc](wrangler.jsonc) owns the Worker asset configuration.
Deployment credentials and hostname ownership live in the
[website runbook](https://app.notion.com/p/3e5e75710b5281999cc8c6a31e5a9e5c).

## Privacy boundary

- HealthKit access is read-only and limited to the types in the product spec.
- Google access uses the narrow `drive.file` scope.
- Health values, OAuth tokens, exported records, and raw HealthKit metadata must
  never appear in logs or diagnostics.
- Local health staging, anchors, and saved day boundaries use file protection
  and are excluded from device backups.

## Documentation

- [Google OAuth setup](docs/GOOGLE_OAUTH.md)
- [Physical-device acceptance testing](docs/DEVICE_TESTING.md)
- [Architecture and privacy boundaries](docs/ARCHITECTURE.md)
- [Product and export contract](docs/specs/healthkit-drive-exporter.md)
- [Security reporting](https://github.com/uinaf/.github/blob/main/SECURITY.md)

## License

HealthMule is available under the [MIT License](LICENSE).
