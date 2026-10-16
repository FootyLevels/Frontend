# Training circles prototype (FP-69)

The Community tab adds private circles of training partners. It uses the authenticated application API and private prepared clips. The bundled sample/debug entry shows an account-required explanation and never makes a test identity or fake circle.

## First version

- Create a named circle or join with a seven-day invite code. Only the circle owner creates/replaces invite codes. Owner removal of a member invalidates the outstanding invitation; the UI clears the cached code.
- View members, leave a circle, remove members as owner, or delete an owned circle. Confirmation describes what becomes inaccessible; private originals stay in their owners' libraries.
- Explicitly choose one of your prepared private clips, add a skill and an optional feedback question, review who can watch, then share. Video only is the default. If the latest result is a compatible completed body-motion reconstruction, an optional toggle attaches that exact result; unselected recordings and generated results remain private.
- Open an attempt, watch its verified video, change speed, attach the current paused video time to feedback, and tap feedback times to seek. For a shared motion, open the 3D viewer, jump to its segment and orbit the model while the original video drives playback. Authors can share another attempt linked to the previous one.
- Remove your own shared attempts/comments; the circle owner can moderate both. Feed/feedback pages support continuation even when a page is empty because entries became inaccessible.

Shared comparison is deferred. Explicit 3D motion sharing extends the practise → share → feedback → retry loop, without a public feed, scoring, follower counts or direct messages. Selected-pose/keyframe results are not motion-sharing candidates. Generating a newer result does not change existing posts; sharing another result requires a new deliberate share.

## Account and playback boundaries

CommunityClient belongs to one account generation. AuthenticatedAPIClient sends Firebase tokens only to the configured application API, never to storage. Responses are validated for circle identity/membership, clip ownership/path, canonical media profile, duration, size/hash, timestamps, and short signed grants. Mutation retry keys remain stable for unchanged payloads and rotate after edits.

Shared videos reuse PrivatePlaybackAssets with a community-specific grant-lifetime bound; existing private-owner playback keeps its previous default. Files download without bearer tokens or redirects and are checked before local AVPlayer use. The client rechecks the pinned shared post after download, before creating playback. Membership/source access is refreshed every 15 seconds; an independent 45-second deadline stops playback if renewal hangs. Backgrounding, closing, logout or a session/access failure tears down playback and verified local files. Visible private captions/feedback are hidden when access expires.

Shared motion uses a separate circle-post `motion-assets` route, with the same 60-second grants and current membership checks. Reconstruction and sanitized job metadata are bound to the exact author, project, prepared video, input revision, output attempt and immutable artifact map. Native clients validate the profile, source, segment bounds and exact chunk names before downloading. The sequence/topology/chunk hashes and manifest provenance are checked by the existing private motion decoder. Access is checked again after downloads and scene construction before displaying the model. Pending loads and visible scenes close immediately on teardown or revocation; late completions cannot restore the scene.

The prepared full-length video remains the canonical feedback clock. The model subtracts the selected segment's source start time when indexing motion and hides outside that segment. This preserves existing comment timestamps and seeks; the trimmed reconstruction `video.mp4` is never confused with the full prepared video. Existing private motion playback retains its default zero offset.

The server issues at most 60-second bearer reads. Revocation prevents future grants immediately; a recipient can retain bytes they already received. Sharing confirmation states that members may save a copy. Only current members get future grants; new members can see existing active shares.

## Run and verify

Use the shared FootyLevels-Development Xcode scheme for account screens and the Development Firebase configuration. The Backend must run this same community branch with its two feed indexes. The current deployed public API has not been changed by this work; 404 is presented as an unavailable feature or withdrawn circle/item, with no fabricated success.

CommunityClientTests covers API intent/idempotency, account changes and stale responses, strict source/asset scopes and short grants, post-download revocation, invalid timestamps/durations, seeking, logout file cleanup, circle metadata revocation and an in-flight feed after teardown. The UI suite also checks the unsigned Community gate and that the local sample is not shareable. Complete signed-in screen-by-screen and physical-device acceptance remain separate from these component/UI-gate checks.

Motion-specific regressions cover explicit opt-in payloads, default video-only consent, candidate lookup failure, clearing selection, changed mutation keys, source/attempt/file validation, pinned motion refresh, short-lived file reads, access revocation after scene construction, original-video feedback timestamps, segment boundary alignment/missing-pose re-entry and teardown while sequence/chunk downloads are pending.

See Backend/docs/training-circles.md for routes, Firestore schema, prototype limits and deployment requirements, and Backend/docs/training-circles-evidence.json for the independently verified real cloud/service proof. That proof uses seeded synthetic prepared media and no GPU job.

## Verified checkpoint — 16 October 2026

The standalone Development simulator app build passed. The final full simulator suite reports 93 unique tests passed, three existing opt-in live-cloud skips and zero failures. This includes all 16 new CommunityClientTests and the Community account-gate UI check. The result bundle is saved locally at `verification/2026-10-16-community/frontend-tests-final.xcresult` in the parent FootyLevels workspace; `training-circles-evidence.json` records the portable summary. The real service proof passed separately with three temporary Firebase accounts and actual private video bytes, with account/storage/metadata cleanup verified. No branch was pushed or runtime deployed.
