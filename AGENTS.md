# HealthMule agent guide

HealthMule exports a read-only allowlist of Apple Health metrics as daily JSON
files in the user's own Google Drive. There is no developer backend.

## Start here

- `make project` generates the Xcode project with the pinned XcodeGen.
- `make run` builds and launches in Simulator.
- `make verify` is the required gate before any push.

| Question | Doc |
| --- | --- |
| What the app must do; the JSON contract | [Product spec](docs/specs/healthkit-drive-exporter.md) |
| Sync, Drive, and privacy invariants | [Architecture](docs/ARCHITECTURE.md) |
| Connecting a real Drive account | [Google OAuth setup](docs/GOOGLE_OAUTH.md) |
| What only a signed device can prove | [Physical-device checklist](docs/DEVICE_TESTING.md) |

## Toolchain

- `make verify` needs only Swift 6 and runs on Linux. iPhone and Watch builds
  need full Xcode with the iOS and watchOS SDKs.
- Call the `scripts/` wrappers, not bare `swift`, `xcodebuild`, or `xcrun`.
  They find `/Applications/Xcode*.app` when `xcode-select` points at
  CommandLineTools.
- `make test`, `make smoke`, `make harness`, and `make run` need `xcode-select`
  on a full Xcode.
- Use only `make project`: another XcodeGen version rewrites the whole project
  file.

## Validation

`make verify` only parses app and iOS test sources; it does not type-check
them. App, Watch, and UI changes also need `make build` or `make smoke`.
`make verify-full` adds the iOS unit and Simulator UI suites. Other targets:
[Contributing](CONTRIBUTING.md).

## Delivery

- Open a pull request; merge after the required `verify` check passes.
- Merging ships nothing. Upload to TestFlight with
  `gh workflow run testflight.yml --ref main`. External testing and App Store
  submission are manual. Release setup:
  [Notion](https://app.notion.com/p/3e5e75710b5281999cc8c6a31e5a9e5c).

## Repo rules

- `HealthMuleCore` stays Foundation-only and deterministic.
- HealthKit access is read-only: no write types or entitlements.
- Logs carry no health values, OAuth tokens, record bodies, or raw metadata.
- Exported records keep explicit JSON `null` values and unknown fields.
- OAuth config lives in ignored `Config/Secrets.xcconfig`, signing in ignored
  `Config/Signing.xcconfig`, runtime tokens in Keychain.
- Simulator fixtures prove development behavior only. Background delivery and
  real Drive uploads need the physical-device checklist.

## Repository skills

- [Swift concurrency](.agents/skills/swift-concurrency/SKILL.md): tasks, actor isolation, Sendable, callback-to-async.
- [SwiftUI](.agents/skills/swiftui-expert-skill/SKILL.md): views, state, layout, accessibility.
- [Swift testing](.agents/skills/swift-testing-expert/SKILL.md): test architecture and async test failures; keep the existing test framework.
- [Xcode build optimization](.agents/skills/xcode-build-orchestrator/SKILL.md): build timing; keep `project.yml` as the project source.
