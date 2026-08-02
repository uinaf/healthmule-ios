# HealthMule agent guide

## Start here

- [Product and export contract](docs/specs/healthkit-drive-exporter.md)
- [Architecture and privacy boundaries](docs/ARCHITECTURE.md)
- [Google OAuth setup](docs/GOOGLE_OAUTH.md)
- [Physical-device acceptance](docs/DEVICE_TESTING.md)
- [TestFlight delivery](docs/DISTRIBUTION.md)
- [Sync-store scaling decision](docs/decisions/sync-store-persistence.md)
- Generate the Xcode project: `make project`
- Build and launch in Simulator: `make run`

## Runner contract

- Core tests and `make verify` need only a Swift 6 toolchain and run on Linux.
- Everything that compiles the app or the Watch app needs a full Xcode with the
  iOS and watchOS SDKs.
- Always call the `scripts/` wrappers instead of bare `swift`, `xcodebuild`, or
  `xcrun`. They locate `/Applications/Xcode*.app` themselves, so `make verify`
  and `make build` work even when `xcode-select` points at CommandLineTools.
  `make test`, `make smoke`, and `make run` cannot be compensated for that way —
  see below.
- `xcrun simctl` and any tool that resolves Xcode through `xcode-select` — the
  Claude Code iOS Simulator MCP included — fail until an operator runs
  `sudo xcode-select -s /Applications/Xcode.app`. Use `./scripts/xcrun.sh`
  meanwhile.
- Boot the target Simulator before `make test`, `make smoke`, or
  `make verify-full`. Against a cold device the test runner loses a launch race
  and every UI test fails with `SBMainWorkspace ... Busy`, which reads like a
  product failure but is not one.
- XcodeGen is pinned and provisioned into `.artifacts/toolchain` by
  `make project`. Do not install it separately; a different version rewrites the
  whole project file.

## Validation

- Fast contract tests: `make test-core`
- Fast local and required CI gate: `make verify`
- Full iOS and Simulator gate: `make verify-full`
- Runtime smoke test: `make smoke`

`make verify` checks the infrastructure contract, parses all app and iOS test
Swift, and runs the deterministic core tests on Linux or macOS. Parsing is not
type checking, so app, Watch, and UI changes also need `make build` or
`make smoke` locally. Required CI runs `make verify` on Linux plus `make build`
on macOS, so a compile break is caught on the pull request. The iOS unit and
Simulator UI suites belong to `make verify-full`, which only ever runs locally
or through the manual `Full Verify` workflow.

## Repo rules

- Keep `HealthMuleCore` Foundation-only and deterministic.
- HealthKit is read-only. Never add HealthKit write types or entitlements.
- Never log health values, OAuth tokens, record bodies, or raw metadata.
- Preserve explicit JSON `null` values and unknown fields in exported records.
- Keep credentials in `Config/Secrets.xcconfig` and Keychain; neither is
  committed.
- Simulator fixtures are development proof only. HealthKit background delivery
  and real Drive uploads require the physical-device checklist in the docs.
