# Contributing

Changes must keep HealthMule read-only toward HealthKit and keep health data
and OAuth tokens out of logs, commits, and reports.

## Setup

Requires full Xcode with the iOS 26 and watchOS 26 SDKs and Swift 6.

```sh
make project                        # also provisions the pinned XcodeGen
make run                            # phone app plus embedded Watch app in Simulator
SIMULATOR_UDID=<udid> make run      # a specific iPhone Simulator
```

Google credentials are optional for builds and automated tests. Real Drive
work needs [Google OAuth setup](docs/GOOGLE_OAUTH.md).

## Validation

| Command | Covers |
| --- | --- |
| `make verify` | Required gate: Swift parse plus core tests |
| `make test-core` | Export, sync, and companion contracts |
| `make build` | Unsigned iOS build with the embedded Watch app |
| `make test` | App unit tests and Simulator UI tests |
| `make smoke` | App-shell launch |
| `make harness` | Deterministic UI states, screenshots, and an xcresult summary in `.artifacts/agent-harness` (`HEALTHMULE_HARNESS_OUTPUT` overrides) |
| `make verify-full` | `verify` plus the full iOS and Simulator suites |
| `make clean` | Remove managed build products |

HealthKit, Google, background-delivery, and Watch changes may also need the
[physical-device checklist](docs/DEVICE_TESTING.md). Change sync or privacy
behavior only with the [product spec](docs/specs/healthkit-drive-exporter.md)
and [architecture](docs/ARCHITECTURE.md) updated in the same pull request.

Retest a security report on the latest TestFlight build, and strip personal
health data from the report.

## Dependencies

[project.yml](project.yml) pins GoogleSignIn with `exactVersion`. After
changing it, run:

```sh
make project
./scripts/with-xcode-lock.sh ./scripts/xcodebuild.sh -resolvePackageDependencies -project HealthMule.xcodeproj -scheme HealthMule -derivedDataPath .artifacts/DerivedData
./scripts/check-app-dependencies.sh
make verify-full
```

Commit the generated project and the workspace `Package.resolved` together.
