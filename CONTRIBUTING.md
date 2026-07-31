# Contributing

Issues and focused pull requests are welcome. HealthMule handles sensitive
health and OAuth data, so changes must preserve its read-only and local-first
privacy boundaries.

## Setup

Install a full Xcode toolchain with the iOS 18 and watchOS 11 SDKs, Swift 6,
and XcodeGen. Then generate the Xcode project:

```sh
brew install xcodegen
make project
```

Google credentials are not required for the default build or automated tests.
If a change needs real Drive integration, follow [Google OAuth
setup](docs/GOOGLE_OAUTH.md) and keep the resulting configuration uncommitted.

## Run locally

Launch the phone app and embedded Watch companion in Simulator:

```sh
make run
```

Set `SIMULATOR_UDID` when you need a specific iPhone Simulator.

## Validation

Run the fast required gate for every change:

```sh
make verify
```

App, UI, HealthKit, Google, and Watch changes should also run the relevant
Xcode proof, normally `make build`, `make smoke`, or `make verify-full`. The
[device testing checklist](docs/DEVICE_TESTING.md) owns physical-device
acceptance.

## Development notes

- Read the [product specification](docs/specs/healthkit-drive-exporter.md) and
  [architecture](docs/ARCHITECTURE.md) before changing sync or privacy
  boundaries.
- Keep HealthKit access read-only.
- Never log or commit health values, OAuth tokens, exported records, raw
  HealthKit metadata, signing files, or local credential configuration.
- Preserve explicit JSON `null` values and unknown fields in exported records.

## Pull request expectations

Keep changes focused, add meaningful tests for behavior changes, and update the
owning documentation when a contract changes. Complete the pull request
template with risks, verification evidence, complexity impact, and a sanitized
review aid when one helps explain the change.
