# Application identity — FP-14

Debug uses the Development Firebase project; Release uses Demo. Each configuration
has its own Google client and callback scheme. Public Firebase client settings are
bundled; server credentials are never part of the app. The old semester project's
configuration is preserved outside the app resources under `Configuration/Legacy`.
Analytics collection is disabled during this migration.

The existing email and Google login screens use Firebase's persisted session.
DEBUG still opens the included example without login, as requested for local
work. Launch with `--require-login` to test the ordinary login route. Release
always uses that route. The bypass provides no identity to the account API.

## Account API configuration

The authenticated transport is separate from the older Skill Lab connection.
Development Debug builds configure `FootyLevelsAPIBaseURL` to
`https://ranting-pesticide-thespian.ngrok-free.dev`. Since 12 October this endpoint
serves the authenticated application API on DGX loopback 8010. It accepts Firebase
Development identities; the private GPU runtime on 8013 is not an app API.

Debug Demo selection suppresses the Development default. Release selects Demo and
has no API default until a separate Demo HTTPS runtime is configured. For local
simulator tests, an explicit `FOOTYLEVELS_API_URL` still overrides the Debug origin.
Never put credentials in these settings or in the editable legacy server address.

Use HTTPS for a device or Release. Only the configured application origin gets
Firebase bearer tokens. Redirects are refused, asset URLs use a separate
transport, cookies and response caching are disabled, and a 401 gets one token
refresh. A second 401 signs out the matching session. Late responses from a
previous login cannot update the current account, including a new session for
the same UID. Network/503 errors preserve login and offer retry.

Profile bootstrap runs after login when this API address is configured. Logout
clears account state and cached responses; switching accounts recreates the
project navigation and playback views. The included example still opens without login in Debug as requested. Uploaded
private projects, media preparation and 3D generation now use Firebase ownership
and the authenticated API. The legacy server settings only support private team
compatibility testing; the public endpoint no longer serves its shared listing.
Release blocks legacy network reads, mutations and remote asset resolution while
keeping bundled file resolution. This prevents a signed-in Release app from
silently exposing the old shared project list.

## Verification on 10 October 2026

A signed iPhone 17 Pro simulator build used the real Development Firebase SDK
against the local authenticated API and real Firestore. Two temporary email
accounts passed repeated profile bootstrap, own-project reads, foreign-project
read/delete rejection, sign-out and account switching. The bundled example loaded
after logout. Both test accounts and exact project/profile records were removed
and their absence verified. Passwords/tokens stayed in memory.

The first unsigned simulator attempt failed while saving the Firebase session to
the keychain. Simulator builds must leave `CODE_SIGNING_ALLOWED=YES`; no paid Apple
account is needed for simulator signing. Its one exact orphan signup was removed.

`AuthenticatedAPIClientTests` cover refresh, logout, account switching during token
fetch/response, same-UID session changes, unsafe destinations and service failure.
`LiveFirebaseSessionTests` is skipped by default. Its explicit Development-only
opt-in requires these XCTest target environment variables:

```
FOOTYLEVELS_LIVE_AUTH_TESTS=1
FOOTYLEVELS_AUTH_TEST_API=http://127.0.0.1:8011
```

Set them in a copy of the generated `.xctestrun` **inside Build/Products**, then use
`test-without-building -only-testing:FootyLevels-FrontendTests/LiveFirebaseSessionTests`.
The probe creates and deletes temporary Auth users, and records non-secret exact
metadata IDs in the simulator app's Documents/fp14-ios-evidence.json. Remove only
those Firestore project/profile IDs after verifying their owner and test run title.
On a keychain failure, a signup may exist before its UID reaches the SDK; its exact
email is `fp14-ios-<runID>-a@example.invalid` (or `-b`). Never delete other accounts.

Interactive Google consent and a physical iPhone smoke test remain release checks.
They were not substituted with automated password entry or claimed as verified.

The final Debug regression passed 11 account/configuration unit checks, two UI
flows and the existing Swift Testing check. The separately opted-in live SDK probe
passed; it is skipped during ordinary regression runs. The Release simulator build
and two configuration checks passed: Firebase initializes against Demo, loopback
HTTP is refused by the account transport, and legacy remote service/asset access
is blocked while the bundled sample's video still resolves locally.

Email signup now shows recoverable errors, blocks incomplete/mismatched input and
prevents repeated requests. Signup/login screens no longer print account details.
