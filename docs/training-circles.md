# Training circles prototype (FP-69)

The Community tab adds private circles of training partners. It uses the authenticated application API and private prepared clips. The bundled sample/debug entry shows an account-required explanation and never makes a test identity or fake circle.

## First version

- Create a named circle or join with a seven-day invite code. Only the circle owner creates/replaces invite codes. Owner removal of a member invalidates the outstanding invitation; the UI clears the cached code.
- View members, leave a circle, remove members as owner, or delete an owned circle. Confirmation describes what becomes inaccessible; private originals stay in their owners' libraries.
- Explicitly choose one of your prepared private clips, add a skill and an optional feedback question, review who can watch, then share. Other recordings and generated 3D results remain private.
- Open an attempt, watch its verified video, change speed, attach the current paused video time to feedback, and tap feedback times to seek. Authors can share another attempt linked to the previous one.
- Remove your own shared attempts/comments; the circle owner can moderate both. Feed/feedback pages support continuation even when a page is empty because entries became inaccessible.

Shared 3D comparison is deferred. The first community loop is practise → share → feedback → retry, without a public feed, scoring, follower counts or direct messages.

## Account and playback boundaries

CommunityClient belongs to one account generation. AuthenticatedAPIClient sends Firebase tokens only to the configured application API, never to storage. Responses are validated for circle identity/membership, clip ownership/path, canonical media profile, duration, size/hash, timestamps, and short signed grants. Mutation retry keys remain stable for unchanged payloads and rotate after edits.

Shared videos reuse PrivatePlaybackAssets with a community-specific grant-lifetime bound; existing private-owner playback keeps its previous default. Files download without bearer tokens or redirects and are checked before local AVPlayer use. The client rechecks the pinned shared post after download, before creating playback. Membership/source access is refreshed every 15 seconds; an independent 45-second deadline stops playback if renewal hangs. Backgrounding, closing, logout or a session/access failure tears down playback and verified local files. Visible private captions/feedback are hidden when access expires.

The server issues at most 60-second bearer reads. Revocation prevents future grants immediately; a recipient can retain bytes they already received. Sharing confirmation states that members may save a copy. Only current members get future grants; new members can see existing active shares.

## Run and verify

Use the shared FootyLevels-Development Xcode scheme for account screens and the Development Firebase configuration. The Backend must run this same community branch with its two feed indexes. The current deployed public API has not been changed by this work; 404 is presented as an unavailable feature or withdrawn circle/item, with no fabricated success.

CommunityClientTests covers API intent/idempotency, account changes and stale responses, strict source/asset scopes and short grants, post-download revocation, invalid timestamps/durations, seeking, logout file cleanup, circle metadata revocation and an in-flight feed after teardown. The UI suite also checks the unsigned Community gate and that the local sample is not shareable. Complete signed-in screen-by-screen and physical-device acceptance remain separate from these component/UI-gate checks.

See Backend/docs/training-circles.md for routes, Firestore schema, prototype limits and deployment requirements, and Backend/docs/training-circles-evidence.json for the independently verified real cloud/service proof. That proof uses seeded synthetic prepared media and no GPU job.
