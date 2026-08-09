# Contributing

Issues and focused pull requests are welcome. HealthMule handles sensitive
health and OAuth data, so changes must preserve its read-only and local-first
privacy boundaries.

## Setup

Install a full Xcode toolchain with the iOS 26 and watchOS 26 SDKs and Swift 6.
Then generate the Xcode project, which also provisions the pinned XcodeGen:

```sh
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

Choose additional proof based on the change:

| Command | Purpose |
| --- | --- |
| `make test-core` | Foundation-only export, sync, and companion contracts |
| `make test-infra` | Xcode, workflow, and toolchain contract checks |
| `make build` | Unsigned iOS build with the embedded Watch app |
| `make test` | App unit tests and Simulator UI tests |
| `make smoke` | App-shell launch smoke test |
| `make harness` | Twelve deterministic UI states with screenshots and an xcresult summary |
| `make verify-full` | Complete local iOS and Simulator gate |

Run `make clean` to remove build products managed by these commands. HealthKit,
Google, background-delivery, and Watch changes may also need the
[physical-device checklist](docs/DEVICE_TESTING.md).

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
