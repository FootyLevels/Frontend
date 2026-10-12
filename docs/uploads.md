# FP-16: private capture/import and resumable uploads

The account flow uses the DGX application API, Firebase login/Firestore records,
and Supabase Free private storage. It is separate from the DEBUG-only legacy
Skill Lab service. The bundled example still opens offline without signing in.

## Player flow

A signed-in player can import from Photos or record up to 60 seconds. Camera or
microphone denial explains how to use Settings or Photos; cancellation creates
no project. PhotosPicker needs access only to the selected item. The editor asks
for a title, optional practice label, start and end. It validates a readable video
track and a 1–60 second selection before networking. Export keeps rotation,
removes audio, prepares a 720p MP4 and checks the 50 MB limit. Invalid/corrupt input,
export failure or an oversized prepared clip never creates a cloud project.

The prepared clip and metadata are saved privately under Application Support,
excluded from backups and protected until first device unlock. Each draft is
scoped by Firebase UID, environment and application API origin. Its opaque UUID
is reused for both project creation and upload-session idempotency. Title/source/
label/checksum/size are pinned; resumed transfers recheck the file's SHA-256.

Only the authenticated API receives a Firebase token. The storage transport pins
the selected environment's HTTPS storage host, private bucket and exact owner/
project/upload object path, rejects redirects and uses only the scoped upload
signature. TUS sends at most 6 MiB per chunk; HEAD reads the server-confirmed offset,
and a 409 causes bounded offset resynchronization. Signatures stay in memory;
the provider's resumable Location is a bearer capability stored only in device
Keychain. Neither is logged or saved in draft JSON.

Pause/background/network loss preserves the draft. Resume after relaunch uses
fresh authenticated capability refresh and server offsets. A lost create response
uses the same project key; a lost finalization response returns the same committed
project. An account generation change cancels/discards late work even if the UID
is subsequently reused. Another account/environment/origin cannot see or resume
these local drafts. The library lists owned cloud projects, supports pagination
and allows another clip to be imported.

Discard persists its intent, recovers an unknown project creation ID if necessary,
and requests a server tombstone before deleting the local draft. A failed removal
remains visible for retry. Server blob/quota release follows its capability
quarantine and the FP-18/54 maintenance rules; deletion acknowledgement does not
claim immediate blob removal.

## Development connection

Debug Development builds use the approved public HTTPS account API by default.
Launch with `--require-login` for the ordinary account route; the included example
still works offline without login in Debug. Firebase bearer tokens go only to the
configured application API, while Supabase signed capabilities use separate
private transports. See [identity configuration](authentication.md).

For a simulator-only private connection, forward Mac loopback 8012 to DGX loopback
**8010** and set `FOOTYLEVELS_API_URL=http://127.0.0.1:8012`. Historical proofs used
8011 before the 12 October cutover. A phone uses the default HTTPS address without
this SSH forward. Demo/Release still needs its own separately configured HTTPS
runtime and does not honor Debug overrides or enable legacy uploads.

## Verification and remaining gates

`PrivateUploadTests` covers confirmed-offset resume, stale offsets, capability
origin/path validation, corrupt and oversized input, private draft isolation,
lost project response/relaunch, same-UID session replacement, video-only export,
trim and portrait orientation. Existing auth and offline-sample tests remain.

`LivePrivateUploadTests` is disabled by default. Enable only Development with
`FOOTYLEVELS_LIVE_UPLOAD_TESTS=1` and `FOOTYLEVELS_AUTH_TEST_API` set to the loopback
forward above in the test target environment. It creates two temporary real
Firebase accounts, uploads to real private Supabase through the actual DGX API,
interrupts after a 6 MiB chunk, recreates the coordinator, resumes/finalizes, checks
a second recording and foreign-account denial, then verifies signed source bytes.
Accounts are deleted in cleanup. `Documents/fp16-ios-evidence.json` records exact
fixture IDs/phases only; remove and audit their Firestore/blob/quota fixtures using
the trusted scoped cleanup procedure afterward. Never commit credentials or
capabilities. A padded MP4 fixture exercises chunking; it is not a production model
input and does not establish a new media-preparation or GPU result.

Finalization returns `preparing` honestly. FP-54 server decoding, private
canonical playback/previews and readiness were verified and deployed on the
private Development API on 11 October, including automatic durable dispatch.
FP-39/19/40 still connect the iOS frame-selection/reconstruction/playback
interface and authenticated public routing. Physical camera/permission/device
testing and interactive Google sign-in
remain separate verification gates. This client checkpoint does not claim the
whole application is verified end to end.

## Verified cloud checkpoint — 11 October 2026

The opt-in simulator probe passed against real Development Firebase, the DGX
application API and Supabase private storage. It interrupted after a confirmed
6 MiB chunk, recreated the coordinator and resumed the same project to revision 2.
A second upload, foreign-account denial, signed download size/SHA-256 and
tombstone checks passed. The trusted cleanup verified removal of two temporary
accounts, two projects, two upload records, two source objects and two profiles;
global reserved bytes returned to zero. No credentials or capabilities are in
the committed aggregate evidence (`uploads-evidence.json`).

The default upload/auth/configuration suite and both UI checks passed, including
opening the included 3D example without login. Progress now distinguishes byte
transfer from server verification, and foreground/list refreshes avoid racing
an active upload or camera permission request. These checks do not exercise a
physical camera, interactive Google login or new authenticated 3D generation.
Both Release configuration tests also passed with a test-only
`ENABLE_TESTABILITY=YES` build override: Demo Firebase is selected, loopback
authenticated origins and legacy service access are disabled, and the bundled
example remains available. The app's Release build settings are unchanged.
