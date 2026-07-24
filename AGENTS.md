# Health Relay agent guide

## Start here

- Product contract: `docs/specs/healthkit-drive-exporter.md`
- Architecture and privacy boundaries: `docs/ARCHITECTURE.md`
- Google OAuth setup: `docs/GOOGLE_OAUTH.md`
- Generate the Xcode project: `make project`
- Build and launch in Simulator: `make run`

## Validation

- Fast contract tests: `make test-core`
- Full local gate: `make verify`
- Runtime smoke test: `make smoke`

`make verify` owns project generation, Swift package tests, an iOS build, and
the simulator test suite. Keep CI pointed at this command.

## Repo rules

- Keep `HealthRelayCore` Foundation-only and deterministic.
- HealthKit is read-only. Never add HealthKit write types or entitlements.
- Never log health values, OAuth tokens, record bodies, or raw metadata.
- Preserve explicit JSON `null` values and unknown fields in exported records.
- Keep credentials in `Config/Secrets.xcconfig` and Keychain; neither is
  committed.
- Simulator fixtures are development proof only. HealthKit background delivery
  and real Drive uploads require the physical-device checklist in the docs.
