# Google OAuth and Drive setup

HealthMule uses GoogleSignIn 10.x for native iOS OAuth and calls Google Drive
API v3 directly. It requests only:

```text
https://www.googleapis.com/auth/drive.file
```

The scope lets the app create and manage the files it created or that the user
explicitly opened or shared with it. It does not grant unrestricted access to
Drive. Google classifies `drive.file` as a non-sensitive, per-file scope; see
[Choose Google Drive API
scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth).

## Create the Google configuration

1. Create or select a Google Cloud project.
2. Enable **Google Drive API** for the project.
3. Configure the Google Auth Platform consent screen and declare
   `https://www.googleapis.com/auth/drive.file` under data access.
4. If the app is External and still in Testing, add the Google account that will
   run the app as a test user.
5. Create an OAuth client with application type **iOS**.
6. Set its bundle ID to the app’s current `HEALTHMULE_BUNDLE_IDENTIFIER`.
   The clean-checkout default is `dev.uinaf.healthmule`; signed local builds
   can override it in the ignored `Config/Signing.xcconfig`.
7. Record the iOS client ID and its reversed-client-ID URL scheme.

A backend client ID is unnecessary because HealthMule has no backend. A native
iOS app cannot keep a client secret confidential, so do not add a web client
secret to the project. Google’s [iOS integration
guide](https://developers.google.com/identity/sign-in/ios/start-integrating)
describes the iOS client and reversed URL scheme.

## Configure the checkout

Create the ignored local configuration:

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Set both values:

```text
HEALTHMULE_GOOGLE_CLIENT_ID = 123456789-example.apps.googleusercontent.com
HEALTHMULE_GOOGLE_REDIRECT_SCHEME = com.googleusercontent.apps.123456789-example
```

The URL scheme is the client ID’s dot-separated prefix in reverse-domain form,
as shown by Google Cloud Console. Do not include `https://`, a path, or a trailing
slash. The app accepts the configuration only when this scheme exactly equals
`com.googleusercontent.apps.<client-id-prefix>` for the configured client ID.

`Config/App.xcconfig` includes this file optionally, so a clean checkout still
builds and tests with an intentionally unconfigured Google state. The real
`Config/Secrets.xcconfig` is ignored by Git. Device-signing values are likewise
kept in ignored `Config/Signing.xcconfig`; its bundle identifier must match this
Google iOS client.

Generate the project after changing checked-in project configuration:

```sh
make project
```

[project.yml](../project.yml) owns the GoogleSignIn pin;
[Contributing](../CONTRIBUTING.md#dependencies) covers updates.

## OAuth publishing status

An External Google OAuth app left in **Testing** receives refresh tokens that
expire after seven days when it requests scopes beyond basic profile identity.
`drive.file` therefore makes weekly reauthorization likely during development.
Google documents this in [OAuth refresh-token
expiration](https://developers.google.com/identity/protocols/oauth2#expiration).

For durable unattended sync, move the OAuth app to **In production** and complete
any basic verification the Google console requires. Keeping it in Testing is
acceptable while developing, but the app must treat token expiry as a normal
Reconnect state rather than as data loss.

## Connection and uploads

`GoogleAuthService` requests `drive.file`, restores credentials through
GoogleSignIn's Keychain state, and refreshes tokens for the expected account.
Disconnect revokes access and signs out without deleting Drive exports. Never
persist or log tokens outside GoogleSignIn.

OAuth authorization alone does not mean Drive is ready. **Connected** also
requires a stable account identity and verified managed folders. Account or
folder changes republish the complete local snapshot before reporting success.
[Google Drive identity](ARCHITECTURE.md#google-drive-identity) owns folder
validation, account namespaces, stable file IDs, and reset behavior;
[Drive transport](ARCHITECTURE.md#drive-transport) owns background transfers and
destination draining.

Use the [physical-device checklist](DEVICE_TESTING.md) to validate real uploads,
interruption, and relaunch recovery.

### Error classification

| Failure | Classification |
|---|---|
| First background upload `401` | Retried once after another token refresh, because its bearer token may have expired while the system waited to transfer it |
| Repeated Drive `401`, immediate metadata-request `401`, OAuth token-endpoint grant failure | Reauthorization required; the app returns to Reconnect while keeping staged work |
| Network or server failure while refreshing a token | Transient |
| Stable-account mismatch during token refresh | Transient, never a reauthorization failure |
| `408`, `429`, `5xx` | Transient |
| Drive `403` reasons `backendError`, `rateLimitExceeded`, `userRateLimitExceeded` | Transient |
| Any other HTTP failure | Non-retryable |

The destination feeds these classifications into the durable core retry queue,
which applies transient backoff and preserves blocked reauthorization or
permanent-failure states.

- Restoring valid credentials explicitly resumes persisted reauthorization
  blocks, including after an interrupted sign-in and process relaunch.
- Non-retryable failures stay visible as blocked work and are not advertised as
  eligible for Retry.

## Troubleshooting

### Google is “Not configured”

Confirm that both values in `Config/Secrets.xcconfig` are non-placeholder values,
then run `make project` and rebuild.

### Redirect or sign-in fails

Confirm all three values describe the same iOS client:

- Google Cloud client bundle ID: the resolved
  `HEALTHMULE_BUNDLE_IDENTIFIER`
- `HEALTHMULE_GOOGLE_CLIENT_ID`
- `HEALTHMULE_GOOGLE_REDIRECT_SCHEME`

Also confirm that the Drive API is enabled in the same Google Cloud project.

### Drive access was not granted

The app verifies the returned scope list. Use Reconnect and grant
`drive.file`; do not replace it with a broader Drive scope.

### Reconnect is required after about one week

Check the OAuth app’s publishing status. Seven-day refresh tokens are expected
for External apps in Testing.

### Restore fails while offline

The app keeps a temporary-unavailable state rather than asking for a new grant.
Bring the device online and use Try Again, or foreground the app to let the
bootstrap path retry. Pending local records remain in the durable queue.

### Google is authorized but Drive is unavailable

OAuth completed, but the managed-folder check failed. Use Try Drive Again after
connectivity and the Drive API configuration have been checked. The app remains
unable to sync until it verifies the managed root and `daily` folders; it does
not treat OAuth alone as Connected.

### The folder was moved

Drive file IDs remain stable when names or locations change. The app continues
by cached folder ID, and Reset Local Sync State intentionally preserves the
managed folder and file IDs so a moved export tree is not duplicated.

If the managed root or `daily` folder was deleted, trashed, or replaced, use Try
Drive Again. HealthMule verifies the new coherent tree, clears stale file-ID
cache entries, and republishes all locally staged days plus a fresh manifest.

Reset clears the local staged manifest and records, then rebuilds the currently
selected date range. It never deletes older Drive files; files outside the
rebuilt range can remain in the folder without appearing in the new manifest.

## API references

- [Calling Google APIs from iOS](https://developers.google.com/identity/sign-in/ios/api-access)
- [Disconnecting GoogleSignIn](https://developers.google.com/identity/sign-in/ios/disconnect)
- [Drive multipart uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads)
- [Drive API error handling](https://developers.google.com/workspace/drive/api/guides/handle-errors)
