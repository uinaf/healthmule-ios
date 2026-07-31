# HealthMule agent guide

## Start here

- Product contract: `docs/specs/healthkit-drive-exporter.md`
- Architecture and privacy boundaries: `docs/ARCHITECTURE.md`
- Google OAuth setup: `docs/GOOGLE_OAUTH.md`
- Physical-device acceptance: `docs/DEVICE_TESTING.md`
- TestFlight delivery: `docs/DISTRIBUTION.md`
- Generate the Xcode project: `make project`
- Build and launch in Simulator: `make run`

## Validation

- Fast contract tests: `make test-core`
- Fast local and required CI gate: `make verify`
- Full iOS and Simulator gate: `make verify-full`
- Runtime smoke test: `make smoke`

`make verify` checks the infrastructure contract, parses all app and iOS test
Swift, and runs the deterministic core tests on Linux or macOS. App and UI
changes also need `make build` or `make smoke`. `make verify-full` owns the
complete iOS unit and Simulator UI suite.

## Repo rules

- Keep `HealthMuleCore` Foundation-only and deterministic.
- HealthKit is read-only. Never add HealthKit write types or entitlements.
- Never log health values, OAuth tokens, record bodies, or raw metadata.
- Preserve explicit JSON `null` values and unknown fields in exported records.
- Keep credentials in `Config/Secrets.xcconfig` and Keychain; neither is
  committed.
- Simulator fixtures are development proof only. HealthKit background delivery
  and real Drive uploads require the physical-device checklist in the docs.
