# FP-40: private motion playback

The owned-project screen reuses the existing RealityKit motion player, camera,
mesh codec and AVPlayer clock. The bundled example still opens locally without
login; it remains separate from private generated results.

## Current flow

After private upload, the screen polls preparation and job status while visible
and active. Prepared playback is obtained from `/api/projects/{id}/media-assets`;
all reference hashes, sizes, origins and owner/project paths are checked before
video is saved locally. The player chooses an exact 30 fps segment of 1–10 seconds
and submits it to `/api/projects/{id}/reconstructions/motion`. Cancellation and
reopening use the durable job/project IDs. Media preparation is described separately
and is not offered the reconstruction-cancel action.

The client fetches the immutable result and its winning job, checks the owner,
source/revision, profile, attempt, segment and ready/partial counts, then obtains
an allowlisted asset map from `/api/reconstructions/{id}/assets`. Only the API gets
Firebase credentials. Private storage gets its own signed read URL, with no API
key or Firebase token; redirect forwarding is rejected. Links stay in memory,
refresh before expiry, and an expired provider response permits one fresh retry.

Files are downloaded into a bounded buffer and verified by SHA-256 and exact size.
A session-owned 8 MiB byte cache avoids repeat small downloads; verified local
video files use private temporary directories excluded from backup. Another account
generation cannot read even a cached file. Closing the view removes its files and
buffers. Logout invalidates playback and removes its video item; late responses
cannot publish local cache/files into a changed session.

## Playback contract

The private adapter accepts schema 1, packing version 1, `body-motion-30fps-v1`,
`motionBuffers` and `uint16-le-xyz-gzip`, with right-handed Y-up coordinates and
estimated metres. It checks pinned engine/contract, canonical/source times,
complete distinct chunk coverage, topology bytes/hash/indices, finite bounded
coordinates and explicit frame validity. Gzip decoding has an exact bounded
output buffer and validates CRC/trailer, complete input consumption and no trailing
member. Unknown versions, wrong buffers, gaps and damaged files fail explicitly.

The verified trimmed video drives 3D time, play/pause/scrubbing and speed. Local
segment time is retained for synchronization; the displayed source time adds the
exact original prepared-video offset. Missing poses stay hidden, with no blending
across a missing frame or shot cut. Unloaded/corrupt chunks have separate loading
or error messages. Camera presets, follow and wireframe controls are retained.
The displayed floor grid is bounded to 50 m for predictable preview resources;
this is a visual reference, not ground calibration.

This first owned flow displays body motion. Private selected-keyframe GLB UI remains
additional integration work; an unsupported result does not silently load through
the shared legacy client. No scoring, AQA or execution-correctness classifier is added.
Ball tracking and measured scale/ground calibration are not claimed by this profile.

## Verified checkpoint

The Debug simulator suite passed 36 checks, with two live-cloud tests explicitly
skipped. This includes account/upload/configuration regressions, the bundled sample
reaching a ready 3D player, signed-out UI and launch variants. The final private
playback suite passed all 11 tests after additional scope/lifetime checks. Its
synthetic triangle sequence reaches the actual reused RealityKit player, hides a
missing pose at the expected source time, and clears scene/video on sign-out.
The tests also exercise corrupt/oversized files, gzip CRC/tails/bounds, topology,
unknown formats, exact motion submission, private grant scopes, expiry refresh
and account-generation isolation. Synthetic geometry is component evidence.

The opted-in real service/player probe also passed on the iPhone 17 Pro simulator
(iOS 26.4). A real temporary Development Firebase SDK email account created an
owned project, uploaded a two-second video-only bundled clip to private Supabase,
and waited for the deployed media worker to prepare 60 frames. It submitted frames
15–45 through the authenticated API; the actual DGX GPU worker generated all 30
poses on attempt 1, with 18,439 vertices and 36,874 faces. The app verified the
ten-file result's provenance, sizes/hashes, topology and compressed buffers, and
the reused RealityKit motion player reached ready. Seeking local frame 15 landed
at original source time 1.0 seconds. Camera, wireframe, speed, stale-session denial
and local-file removal passed. The live XCTest result is one pass, no failures or
skips. The account and exact 18 source/prepared/result files, metadata, quota and
one private model cache entry were removed; absence and quiescence were verified.
See [credential-free verification evidence](private-playback-evidence.json).

This is real simulator service/player integration, including GPU generation, not
a complete interactive app or physical-device acceptance test. Actual output had
30/30 valid poses; missing-frame behavior remains covered separately by component
tests. Workers poll conservatively to protect free-tier Firestore usage, so queue
pickup can take several minutes. The API still runs on DGX loopback 8011, while
public ngrok port 8010 remains legacy compatibility. Named physical-iPhone
playback, interactive Google sign-in, authenticated public routing and private
selected-keyframe UI remain open. FP-40 stays In Progress.

`LivePrivatePlaybackTests` is skipped by default. After starting the private SSH
forward from Mac port 8012 to DGX port 8011, set `FOOTYLEVELS_LIVE_PLAYBACK_TESTS=1`
and `FOOTYLEVELS_AUTH_TEST_API=http://127.0.0.1:8012` in a copy of the Development
`.xctestrun` inside `Build/Products`. Run only this class, with serial testing and
a 1,500-second test allowance. No secrets belong in the run configuration. Once
the SDK test finishes, its Documents/fp40-ios-evidence.json holds non-secret exact
cleanup IDs. Run Backend's `scripts/cleanup_ios_playback_fixtures.py` with that file
using the configured Mac ADC; it checks the temporary account's exact invocation
email, project title/owner/environment, waits for writers, deletes only that
fixture's assets/records/cache and releases only its reserved quota. Preserve
evidence and retry cleanup if writers remain active; never broadly clear storage.
