# HealthMule

HealthMule is an open-source iOS 18 app paired with a lightweight watchOS 11 companion.
It turns a small, read-only allowlist of Apple Health metrics into stable daily
JSON records in a user-controlled Google Drive folder.

The repository contains the SwiftUI app, deterministic export and aggregation
core, read-only HealthKit daily provider, protected local staging and retry
queue, Google OAuth, and an idempotent Drive destination. Foreground sync
combines anchored changes with a rolling three-day reconciliation and a
resumable selected-range backfill. Metric switches limit HealthKit queries and
rebuild existing records to scrub disabled fields. The Apple Watch companion
shows sanitized sync status and can request a sync while the iPhone is
reachable; the iPhone remains the only HealthKit, Google credential, and
Drive-upload owner.

The full sync path is implemented, but its platform integrations still need
acceptance proof with a configured Google OAuth client, a real Drive account,
and HealthKit on a physical iPhone. Multipart Drive bodies are staged as
protected, backup-excluded files and uploaded through a background
`URLSession`; a matching SwiftUI background task reconnects the session after a
system relaunch and lets the durable sync queue reconcile the result.

## Quick start

Requirements:

- A full Xcode installation with the iOS 18 and watchOS 11 SDKs
- Matching iOS and watchOS Simulator runtimes for app builds and launches
- Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

CI downloads the official XcodeGen release pinned in
`scripts/install-xcodegen.sh` and verifies its published SHA-256 digest before
use. Local development can use any compatible `xcodegen` on `PATH`.

Generate the project and launch the phone app in the first available iPhone
Simulator. Xcode also builds and embeds the Watch companion:

```sh
brew install xcodegen
make project
make run
```

Set `SIMULATOR_UDID` to target a specific available simulator:

```sh
SIMULATOR_UDID=<simulator-udid> make run
```

The default build intentionally has no Google credentials. The UI and automated
tests work in that state. Follow [Google OAuth setup](docs/GOOGLE_OAUTH.md) when
you are ready to connect a Drive account.

## Validation

```sh
make test-core  # Foundation-only export, sync, and companion-message contracts
make test-infra # Static checks for the serialized Xcode and CI tool contracts
make build      # Unsigned iOS build including the embedded Watch app
make test       # App unit tests and Simulator UI tests
make smoke      # Launches only the app-shell UI smoke test
make verify      # Fast CI: infrastructure + Swift syntax + core tests
make verify-full # Complete Xcode app, unit, and Simulator UI gate
```

Run `make clean` to remove SwiftPM and Xcode build products managed by these
commands.

Required CI checks infrastructure, parses all app and iOS test Swift, and runs
the deterministic core suite on Linux. App and UI changes should also run
`make build` or `make smoke` locally. The complete Simulator suite remains
available through `make verify-full` and the manual `Full Verify` GitHub
workflow, without spending macOS runner time on every push.

Production archives are built and uploaded from the manual, main-only
`Upload TestFlight` GitHub workflow. A developer Mac is not part of the release
path. See [TestFlight distribution](docs/DISTRIBUTION.md) for its one-time
credential setup and delivery boundary.

HealthKit authorization and background delivery require a signed build on a
physical iPhone. Background Watch Connectivity delivery requires a paired
physical iPhone and Apple Watch. Google OAuth and real Drive uploads require
local client configuration and an integration account. Those boundaries are not
proved by the automated Simulator gate; use the
[device testing checklist](docs/DEVICE_TESTING.md).

## Privacy boundary

- HealthKit access is read-only and limited to the types in the product spec.
- The app has no developer backend, analytics, ads, or telemetry.
- Google access uses the narrow `drive.file` scope.
- Health values, OAuth tokens, exported records, and raw HealthKit metadata must
  never appear in logs or diagnostics.
- Local health staging, anchors, and saved day boundaries use file protection
  and are excluded from device backups.

## Documentation

- [Product specification](docs/specs/healthkit-drive-exporter.md)
- [Architecture and current implementation](docs/ARCHITECTURE.md)
- [Google OAuth setup](docs/GOOGLE_OAUTH.md)
- [TestFlight distribution](docs/DISTRIBUTION.md)
- [Physical-device acceptance testing](docs/DEVICE_TESTING.md)
- [Security reporting](SECURITY.md)

## Contributing

Issues and pull requests are welcome. See [Contributing](CONTRIBUTING.md) for
the development setup, validation commands, and privacy requirements.

## License

HealthMule is available under the [MIT License](LICENSE).
