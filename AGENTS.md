# HealthMule agent guide

HealthMule exports a read-only allowlist of Apple Health metrics as stable
daily JSON files in the user's own Google Drive. There is no developer backend.

## Start here

- Generate the Xcode project: `make project`
- Build and launch in Simulator: `make run`
- Required gate before any push: `make verify`

| Question | Doc |
| --- | --- |
| What the app must do and what the JSON contract is | [Product and export contract](docs/specs/healthkit-drive-exporter.md) |
| Module map, sync invariants, privacy boundaries | [Architecture](docs/ARCHITECTURE.md) |
| Connecting a real Drive account | [Google OAuth setup](docs/GOOGLE_OAUTH.md) |
| What only a signed physical device can prove | [Physical-device acceptance](docs/DEVICE_TESTING.md) |

## Toolchain

- `make verify` and core tests need only a Swift 6 toolchain and run on Linux.
  Compiling the iPhone or Watch app needs a full Xcode with the iOS and watchOS
  SDKs.
- Call the `scripts/` wrappers rather than bare `swift`, `xcodebuild`, or
  `xcrun`. They find `/Applications/Xcode*.app` themselves, so `make verify`,
  `make build`, and `./scripts/xcrun.sh simctl` work while `xcode-select`
  points at CommandLineTools.
- `make test`, `make smoke`, `make harness`, and `make run` use the toolchain
  `xcode-select` points at, which must be a full Xcode.
- Simulator tasks shut down only the devices they booted.
- `make project` provisions the pinned XcodeGen into `.artifacts/toolchain`.
  Another XcodeGen version rewrites the whole project file.

## Validation

`make verify` runs a Swift parse of the app and iOS tests and the core tests.
Parsing is not type checking, so app, Watch, and UI changes also need
`make build` or `make smoke`. `make verify-full` adds the iOS unit and Simulator
UI suites. The full matrix is in [Contributing](CONTRIBUTING.md#validation).

CI runs `make verify` on Linux for every pull request and push to `main`, plus
`make build` on macOS when compile inputs change; the path filter lives in
[verify.yml](.github/workflows/verify.yml). `make verify-full` runs locally or
through the manual `Full Verify` and `Upload TestFlight` workflows.

## Delivery

- Open pull requests and merge after the required `verify` check passes.
- Merging to `main` ships nothing. `Upload TestFlight` is a manual dispatch from
  `main` (`gh workflow run testflight.yml --ref main`) that uploads a signed
  build to App Store Connect; external testing and App Store submission are
  manual App Store Connect steps. Setup and the sync-store decision record:
  [Notion](https://app.notion.com/p/3e5e75710b5281999cc8c6a31e5a9e5c).

## Repo rules

- `HealthMuleCore` stays Foundation-only and deterministic.
- HealthKit access is read-only, with no write types or entitlements.
- Logs carry no health values, OAuth tokens, record bodies, or raw metadata.
- Exported records keep explicit JSON `null` values and unknown fields.
- OAuth configuration lives in ignored `Config/Secrets.xcconfig`, signing in
  ignored `Config/Signing.xcconfig`, and runtime tokens in Keychain.
- Simulator fixtures are development proof only. HealthKit background delivery
  and real Drive uploads need the physical-device checklist.

## Repository skills

- [Swift concurrency](.agents/skills/swift-concurrency/SKILL.md): tasks, actor isolation, Sendable, callback-to-async changes.
- [SwiftUI](.agents/skills/swiftui-expert-skill/SKILL.md): views, state, layout, accessibility.
- [Swift testing](.agents/skills/swift-testing-expert/SKILL.md): test architecture and async test failures, within the existing test framework.
- [Xcode build optimization](.agents/skills/xcode-build-orchestrator/SKILL.md): build timing and optimization, with its five companion skills. `project.yml` stays the project source.
