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

## Runner contract

- Core tests and `make verify` need only a Swift 6 toolchain and run on Linux.
- Everything that compiles the app or the Watch app needs a full Xcode with the
  iOS and watchOS SDKs.
- Always call the `scripts/` wrappers instead of bare `swift`, `xcodebuild`, or
  `xcrun`. They locate `/Applications/Xcode*.app` themselves, so `make verify`
  and `make build` work even when `xcode-select` points at CommandLineTools.
- `make test`, `make smoke`, `make harness`, and `make run` get no such fallback. They need
  `xcode-select` pointed at a full Xcode.
- Use `./scripts/xcrun.sh simctl` when `xcode-select` points at CommandLineTools.
  Tools without that wrapper need an operator to select a full Xcode.
- Simulator test commands wait for boot and shut down only devices they booted.
  Leave already-running Simulators alone.
- XcodeGen is pinned and provisioned into `.artifacts/toolchain` by
  `make project`. Do not install it separately; a different version rewrites the
  whole project file.

## Validation

- Fast contract tests: `make test-core`
- Fast local and required CI gate: `make verify`
- Full iOS and Simulator gate: `make verify-full`
- Runtime smoke test: `make smoke`
- Full command matrix: [Contributing](CONTRIBUTING.md#validation)

What the gates prove:

- `make verify` checks the infrastructure contract, parses all app and iOS test
  Swift, and runs the deterministic core tests on Linux or macOS. Make runs
  those three independent lanes concurrently with a bounded job count.
- Parsing is not type checking, so app, Watch, and UI changes also need
  `make build` or `make smoke` locally.
- Required CI always runs `make verify` on Linux. It adds `make build` on macOS
  when app, Watch, project, package, build-script, or compile-workflow inputs
  change; documentation-only and unrelated automation changes skip that lane.
- The iOS unit and Simulator UI suites belong to `make verify-full`, which runs
  locally or through the manual `Full Verify` and `Upload TestFlight` workflows,
  never on a pull request.

## Delivery

- Open pull requests and merge after the required `verify` check passes.
- A push to `main` runs `Verify` only; nothing ships on merge.
- `Upload TestFlight` is a manual dispatch from `main`
  (`gh workflow run testflight.yml --ref main`) that uploads a signed build to
  App Store Connect. External testing and App Store submission stay manual App
  Store Connect steps. Setup and the sync-store decision record:
  [Notion](https://app.notion.com/p/3e5e75710b5281999cc8c6a31e5a9e5c).

## Repo rules

- Keep `HealthMuleCore` Foundation-only and deterministic.
- HealthKit is read-only. Never add HealthKit write types or entitlements.
- Never log health values, OAuth tokens, record bodies, or raw metadata.
- Preserve explicit JSON `null` values and unknown fields in exported records.
- Keep local OAuth configuration in ignored `Config/Secrets.xcconfig`, signing
  in ignored `Config/Signing.xcconfig`, and runtime tokens in Keychain. Never
  commit credentials or client secrets.
- Simulator fixtures are development proof only. HealthKit background delivery
  and real Drive uploads require the physical-device checklist in the docs.

## Repository skills

- Use [Swift concurrency](.agents/skills/swift-concurrency/SKILL.md) for tasks, actor isolation, Sendable, and callback-to-async changes.
- Use [SwiftUI](.agents/skills/swiftui-expert-skill/SKILL.md) for view, state, layout, and accessibility changes.
- Use [Swift testing](.agents/skills/swift-testing-expert/SKILL.md) for test architecture and async test failures; preserve the existing test framework unless migration is requested.
- Use [Xcode build optimization](.agents/skills/xcode-build-orchestrator/SKILL.md) for build timing and optimization work; its five companion skills are installed alongside it. Keep `project.yml` as the project source and use the repository build commands.
