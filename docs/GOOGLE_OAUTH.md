# Google OAuth and Drive setup

HealthMule requests only `https://www.googleapis.com/auth/drive.file`. Never
widen it.

## Create the Google client

1. Create or select a Google Cloud project and enable **Google Drive API**.
2. Configure the Google Auth Platform consent screen; declare `drive.file`
   under data access.
3. While an External app is in Testing, add the Google account that will run
   the app as a test user.
4. Create an OAuth client of type **iOS**. Set its bundle ID to
   `HEALTHMULE_BUNDLE_IDENTIFIER`: `dev.uinaf.healthmule` by default, or the
   value in ignored `Config/Signing.xcconfig`.
5. Record the client ID and its reversed-client-ID URL scheme.

Add no web client or client secret: a native app cannot keep one secret.

## Configure the checkout

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

```text
HEALTHMULE_GOOGLE_CLIENT_ID = 123456789-example.apps.googleusercontent.com
HEALTHMULE_GOOGLE_REDIRECT_SCHEME = com.googleusercontent.apps.123456789-example
```

The scheme must equal `com.googleusercontent.apps.<client-id-prefix>` exactly:
no `https://`, path, or trailing slash. Then run `make project` and rebuild.

## Publishing status

An External app in **Testing** gets refresh tokens that expire after seven
days ([Google](https://developers.google.com/identity/protocols/oauth2#expiration)),
so expect weekly Reconnect. Move the app to **In production** for unattended
sync.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Google is "Not configured" | Set both values in `Config/Secrets.xcconfig` to real ones, run `make project`, rebuild. |
| Redirect or sign-in fails | Make the client's bundle ID, `HEALTHMULE_GOOGLE_CLIENT_ID`, and `HEALTHMULE_GOOGLE_REDIRECT_SCHEME` describe the same iOS client, in a project with the Drive API enabled. |
| Drive access was not granted | Reconnect and grant `drive.file`. |
| Reconnect needed about weekly | The OAuth app is still in Testing. |
| Restore fails while offline | Go online, then Try Again or foreground the app. Queued records stay. |
| Authorized but Drive is unavailable | The folder check failed. Check connectivity and the Drive API, then Try Drive Again. If it still fails, share Advanced → Prepare Diagnostics. |
| Managed root or `daily` folder deleted or trashed | Try Drive Again. The app republishes every staged day and a fresh manifest to the new tree. |

Moving the folder within My Drive needs no action. Reset Local Sync State
keeps folder and file IDs, rebuilds the selected range, and never deletes Drive
files; older files can remain outside the new manifest.
