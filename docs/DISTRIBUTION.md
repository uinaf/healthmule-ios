# TestFlight distribution

Health Mule is archived, signed, and uploaded only by the manual `Upload TestFlight`
GitHub Actions workflow. A developer Mac is not part of the release path.

The workflow accepts dispatches from `main` only, runs the complete iOS and
Simulator test suite, asks Xcode to create or refresh managed signing assets with
an App Store Connect API key, archives the iPhone app and embedded Watch app,
and uploads the result to App Store Connect. A successful job means Apple
accepted the upload; App Store Connect may still be processing the build.

## One-time setup

Create an App Store Connect team API key under **Users and Access > Integrations >
App Store Connect API**. Give it enough access to upload builds and manage
Certificates, Identifiers & Profiles. Download the `.p8` file immediately;
Apple only offers the download once.

Configure the `testflight` GitHub Environment with this secret:

- `APP_STORE_CONNECT_API_PRIVATE_KEY`: the complete contents of the downloaded
  `.p8` file

Configure these environment variables:

- `APPLE_TEAM_ID`: `54QY62678F`
- `APP_STORE_CONNECT_KEY_ID`: the API key's 10-character key ID
- `APP_STORE_CONNECT_ISSUER_ID`: the issuer UUID shown by App Store Connect
- `GOOGLE_CLIENT_ID`: the iOS OAuth client ID used by Health Mule
- `GOOGLE_REDIRECT_SCHEME`: the reversed-client-ID URL scheme

The Google values are embedded in the signed app and are identifiers, not
client secrets. The Apple private key is the only GitHub secret required. The
workflow writes all generated configuration under the ephemeral runner and
removes it in an `always()` cleanup step.

## Upload a build

Dispatch the workflow from the GitHub Actions page with branch `main`, or run:

```sh
gh workflow run testflight.yml --ref main
gh run watch
```

After the workflow succeeds, open
[App Store Connect](https://appstoreconnect.apple.com/apps), wait for processing,
then assign the build to an internal TestFlight group. External testing and App
Store submission remain explicit App Store Connect steps.

## Security and operational boundary

- The upload job has read-only repository permissions and uses the dedicated
  `testflight` Environment.
- The private key is injected only after the full verification gate passes.
- No certificate or provisioning profile is copied from a developer Mac; Xcode
  automatic signing manages them with the API key.
- Workflow reruns receive a distinct numeric build number.
- Private-repository macOS runner usage counts against the GitHub plan's hosted
  runner allowance.
