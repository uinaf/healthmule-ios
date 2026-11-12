# Contributing

Changes must keep HealthMule read-only toward HealthKit and keep health data
and OAuth tokens out of logs, commits, and reports.

## Setup

Requires full Xcode with the iOS and watchOS SDKs for the deployment targets
in [`project.yml`](project.yml).

```sh
make project                        # also provisions the pinned XcodeGen
make run                            # phone app plus embedded Watch app in Simulator
SIMULATOR_UDID=<udid> make run      # a specific iPhone Simulator
```

Google credentials are optional for builds and automated tests. Real Drive
work needs [Google OAuth setup](docs/GOOGLE_OAUTH.md).

## Validation

```sh
make verify        # required gate
make verify-full   # adds the Xcode test suites
```

Focused targets live in the [`Makefile`](Makefile).

HealthKit, Google, background-delivery, and Watch changes may also need the
[physical-device checklist](docs/DEVICE_TESTING.md).

Retest a security report on the latest TestFlight build, and strip personal
health data from the report.

## Dependencies

[project.yml](project.yml) pins GoogleSignIn with `exactVersion`. Commit the
generated project and the workspace `Package.resolved` with any pin change;
`make verify` fails when they differ.
