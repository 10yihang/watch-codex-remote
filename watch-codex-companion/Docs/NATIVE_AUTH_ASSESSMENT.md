> Historical report. This local candidate now wires the experimental real flow and supersedes the disabled/read-only claims below. See [LIVE_CONNECTION.md](LIVE_CONNECTION.md) for current scope and unrun Apple/device checks. No prior CI result validates this revision.

# Native iPhone authentication assessment and local candidate

Prepared 2026-11-09. This is a source comparison and a dormant implementation candidate, not a successful account connection.

## Result

NightBlood Remote provides a concrete native iPhone implementation of browser OAuth, Remote step-up, Secure Enclave enrolment, explicit host confirmation and relay session refresh. Its MIT license permits reuse with the copyright and permission notice retained.

It does **not** demonstrate a separately registered OAuth client for this Watch app. The inspected NightBlood build uses the public Codex OAuth application identifier and the `codex_cli_simplified_flow` parameter. Its own documentation explicitly says public availability of that identifier is not an assurance of service support for a third-party integration. This is a distinction between an implementation example and verified authorization/support, not a claim that a public application identifier is a secret.

The existing Watch project deliberately rejects that identifier and has no live login entry point. This candidate preserves that boundary. It prepares the native platform code without silently changing the app's authorization policy or claiming the blocked live route is solved.

## Pinned sources and license

- Watch baseline: [`10yihang/watch-codex-remote`, `4a32ea3b870f479d4a284df3d247e077f267846b`](https://github.com/10yihang/watch-codex-remote/tree/4a32ea3b870f479d4a284df3d247e077f267846b).
- NightBlood reference: [`jonathanroomer/NightBloodRemote`, `4824aceb1cd04ac521f7f0342771c20edad60dac`](https://github.com/jonathanroomer/NightBloodRemote/tree/4824aceb1cd04ac521f7f0342771c20edad60dac).
- [MIT license](https://github.com/jonathanroomer/NightBloodRemote/blob/4824aceb1cd04ac521f7f0342771c20edad60dac/LICENSE): copyright 2026 NightBlood Remote contributors; retain the notice in copies or substantial portions. The complete license and [notices](https://github.com/jonathanroomer/NightBloodRemote/blob/4824aceb1cd04ac521f7f0342771c20edad60dac/NOTICE.md) are preserved in `ThirdParty/NightBloodRemote/`.
- NightBlood's [README](https://github.com/jonathanroomer/NightBloodRemote/blob/4824aceb1cd04ac521f7f0342771c20edad60dac/README.md) reports physical iPhone/CarPlay success on its tested setup. That is the upstream author's report, not independent testing of this Watch app. It explicitly leaves other signing teams, free Personal Team signing and future desktop compatibility unverified.

MIT permission covers source reuse. It does not grant Apple entitlements, remote-account access, ownership of trademarks or service support.

## Native route in the reference

1. `project.yml` supplies the public Codex client ID. `CodexPlanOAuth.swift` opens `https://auth.openai.com/oauth/authorize` with random state and S256 PKCE. The ordinary scope is `openid profile email offline_access api.connectors.read api.connectors.invoke`.
2. `CodexOAuthCallbackServer.swift` binds only `127.0.0.1`, tries ports 1455 then 1457, and expects `http://localhost:<port>/auth/callback`. It validates the Host header, single state/code values and request shape. `CodexOAuthSafariPresenter.swift` keeps login in the foreground app through `SFSafariViewController` and supports cancellation.
3. Native code exchanges the authorization code with `https://auth.openai.com/oauth/token`. `CodexPlanTokenStore.swift` stores the returned token set in device-only Keychain. It does not read the desktop's token files.
4. `CodexRemoteEnrolment.swift` calls `/backend-api/codex/remote/control/client/enroll/start`, validates the account/challenge, creates an iPhone Secure Enclave identity, and saves lifecycle metadata before finishing.
5. `CodexRemoteEnrolmentTransport.swift` requests a separate `codex.remote_control.enroll` step-up token with `reauth=remote_control`, `max_age=0` and account/workspace binding. `CodexRemoteEnrolmentTypes.swift` checks the account, recent authentication and exact step-up scope. A normal login token or pairing code is not a substitute for this grant.
6. It signs the enrolment challenge and posts enrol-finish. A lost response preserves the key and marks the outcome unknown rather than retrying or deleting recovery material.
7. The user claims a pairing code once, selects the host from a fresh client-scoped listing and explicitly confirms the exact host. Refresh then obtains the short-lived controller token before the WebSocket proof/handshake.

Source pointers:

- [OAuth and callback contract](https://github.com/jonathanroomer/NightBloodRemote/blob/4824aceb1cd04ac521f7f0342771c20edad60dac/ios/NightBloodRemote/NightBloodRemote/CodexPlanOAuth.swift#L9-L31)
- [Configured public application identifier](https://github.com/jonathanroomer/NightBloodRemote/blob/4824aceb1cd04ac521f7f0342771c20edad60dac/ios/NightBloodRemote/project.yml#L98)
- [Step-up parameters](https://github.com/jonathanroomer/NightBloodRemote/blob/4824aceb1cd04ac521f7f0342771c20edad60dac/ios/NightBloodRemote/NightBloodRemote/CodexRemoteEnrolmentTransport.swift#L443-L468)
- [Unknown-finish preservation](https://github.com/jonathanroomer/NightBloodRemote/blob/4824aceb1cd04ac521f7f0342771c20edad60dac/ios/NightBloodRemote/NightBloodRemote/CodexRemoteEnrolment.swift#L184-L245)
- [Explicit host confirmation](https://github.com/jonathanroomer/NightBloodRemote/blob/4824aceb1cd04ac521f7f0342771c20edad60dac/ios/NightBloodRemote/NightBloodRemote/CodexRemoteControllerREST.swift#L420-L463)

The iPhone loopback callback is not a Mac host bridge. NightBlood's separate voice, CarPlay, DeviceCheck and desktop-transcript helper code is outside this Watch integration and was not ported or executed.

## Concrete integration differences

| Area | Current Watch baseline | Work still needed |
| --- | --- | --- |
| Native sign-in | No OAuth implementation or credentials | This candidate adds dormant platform modules. Resolve the accepted client/scope/redirect contract before enabling. Review token issuer/audience/account binding against that contract. |
| Step-up | `finishEnrollment` accepts a raw `stepUpToken` string | Implement separate browser step-up and validate account, expiry/authentication freshness and exact scope. Never treat an ordinary token as step-up. |
| Identity | Secure Enclave key; label `os_protected_nonextractable`; no biometric gate | NightBlood uses `hardware_secure_enclave` plus foreground biometry. Test the exact accepted iPhone identity; never change the protection label after its hash is challenge-bound. The reference's source also labels acceptance a live-device verification gate. |
| Enrolment response | Requires `RemoteControlSession` from enrol-finish | NightBlood decodes account/client/scopes at enrol-finish and gets a controller session through refresh after host confirmation. Compare a sanitized authorized response before changing this contract. The differing decoders alone do not prove a service defect. |
| Account identity | Strict comparison with one account-user ID | NightBlood also handles `user_id` from the ordinary token for enrol-start. Establish the correct mapping; do not broadly relax identity checks. |
| Persistence/recovery | Device key provider exists, but no complete enrolment/pairing journal | Persist lifecycle state before mutation dispatch. Preserve an uncertain result across restart; reconcile before any repeat. |
| Pairing | `pair` sends a request; `hosts` lists environments | Consume a code once, verify with a fresh listing, bind explicit host confirmation to account + controller + environment. An HTTP success alone must not set Connected. |
| Controller token | Read-only relay and session signing implemented | Validate refresh/expiry, keep the short-lived token in memory, close on lock/background/account change, and never replay an uncertain operation. |
| Watch data | Demo engine and WatchConnectivity only | Add an explicitly distinct live source only after real phone read-only validation. Keep credentials, controller tokens and keys on iPhone. Handle offline phone, lock, stale snapshots and duplicate taps. |
| Real commands | No native resume/start/interrupt | Add only after a real selected existing thread is read and matched. Never create/fork a replacement thread or change permissions to make a test pass. |

These are source-backed differences and proposed validation points. No production response was observed during this task.

## Files in the candidate

Added to the **iPhone target only**, adapted from the four MIT upstream files:

- `iPhone/CodexPlanOAuth.swift`: PKCE/state, foreground Safari login, explicit token refresh, cancellation and bounded HTTPS token exchange.
- `iPhone/CodexOAuthCallbackServer.swift`: one-use loopback HTTP callback, strict state/Host checks, bounded input and listener cleanup.
- `iPhone/CodexOAuthSafariPresenter.swift`: native Safari presentation and dismissal.
- `iPhone/CodexPlanTokenStore.swift`: atomic token-set Keychain storage with redacted descriptions, no iCloud synchronization, no background-access downgrade.

Other changes:

- `Scripts/generate_project.py`, generated `.pbxproj` and `iPhone/Info.plist`: include the four sources on iPhone only; `CodexOAuthEnabled=false`, client ID empty, scope empty.
- `Scripts/check_native_auth.py`: 12 structural checks for disabled configuration, no caller, no borrowed desktop identity, phone-only membership, callback/transport boundaries, storage and license retention.
- `Scripts/check_source.py`: includes the new guardrails and the expected additional iPhone build sources. The old blanket ban on the literal `refresh_token` is narrowed to the new native auth implementation; no token import or live caller was introduced.
- `ThirdParty/NightBloodRemote/LICENSE` and `NOTICE.md`: preserved verbatim.
- This document and a short root README note.

Deliberate changes from the source: no compiled public Codex client ID, no CLI-flow parameter, no default scopes, no CarPlay/background Keychain mode, a 1 MiB streaming response cap, bounded stored token fields, a separate Watch app Keychain namespace, and non-blocking Safari presentation guarded against an existing modal. Encoded Keychain bytes are bounded both before writing and after reading. These changes mean this is not a claim to reproduce the upstream author's working setup.

The UI and demo engine are unchanged. Merely launching the app cannot start OAuth, open its callback listener, write tokens or enroll a device. The implementation still needs a reviewed integration/controller layer and runtime tests. Configuration flags are not proof of consent or service support.

## Cloud verification after publication

With owner approval, native OAuth code commit `fa96253133a17fc27d32cb9949c2d64e6fdd8646` was published and [run 42632249643](https://github.com/10yihang/watch-codex-remote/actions/runs/42632249643) completed successfully on 2026-11-09:

- 24 source/project tests, including the native-auth guardrail wrapper; 20 Node protocol tests.
- 49 Swift core tests: 18 core, 9 API, 11 relay and 11 signing tests, all with zero failures.
- Xcode 16.4 (16F6), Swift 6.1.2 compiler; iPhone and Watch unsigned simulator builds succeeded.
- Actual demo simulator screenshot capture and both artifact uploads succeeded. Screenshot capture is not interactive OAuth or physical-device validation.

The build reported a Notification sendability warning in the new OAuth foreground watcher. A follow-up maps notifications to `Void` before actor-isolated iteration; this does not enable login or change its cancellation purpose. Check the exact follow-up commit's CI result as well. The project remains in Swift 5 language mode; this is not a claim of a full Swift 6 migration.

## Initial local verification

Passed locally:

- 24 source/project structural tests, including the new auth check wrapper.
- 12 native-auth structural tests.
- 20 existing offline Node protocol tests.
- Deterministic project regeneration is covered by the source tests.

Blocked before execution:

- `Scripts/verify_apple.sh` exits 2 because this Linux executor has neither Swift nor Xcode. No Swift compilation, XCTest or Apple build ran for this candidate.

Not run:

- Safari callback runtime or cancellation, real token exchange, Keychain operations, biometric/Secure Enclave operations, device enrolment, pairing, relay, live host/thread reads, physical WatchConnectivity, install/signing or account operations.
- Initial local preparation performed no push, pull request, release or workflow dispatch. Publication and cloud CI happened later with owner approval, as recorded above.

A second static review identified a potentially hanging UIKit presentation wait and an encoded-Keychain-size edge case; both were corrected before packaging. Those corrections still require iOS runtime testing.

Source-string checks alone cannot establish runtime security, compilation or interoperability. The subsequent cloud build establishes compilation for its exact commit, not live interoperability. The Swift package tests still cover the existing shared core, not these UIKit/Network/Security auth files. An iPhone test target with injected transport/callback/Keychain fakes is needed before enabling this code.

## Physical-device validation sequence

1. **Build first, with no account actions.** Run source checks, Node tests and `Scripts/verify_apple.sh` on a Mac with full Xcode. Fix compile/test failures against this exact candidate. Preserve the user's real bundle IDs and signing settings when regenerating.
2. **Test auth offline through fakes.** Exercise port collision, incorrect/duplicate state, incorrect Host/path/method, oversized headers/token response, cancel/back/swipe dismissal, app background, timeout, duplicate start, stale operation completion, Keychain protection mismatch and refresh cancellation. Do not use real credentials as fixtures.
3. **Confirm the route and prerequisites.** Establish the permitted client/scopes/redirect and service access for this app/account. Check the current official desktop version, same account/workspace, workspace Remote permission and the selected Mac's Remote enablement separately. Do not change permissions or bypass a rejection.
4. **Prepare a physical iPhone and paired Watch.** Use the intended Apple team and unique matching bundle IDs. Developer Mode/trust/signing are separate from Remote authorization. Simulator success does not validate hardware keys or the phone/Watch link.
5. **Authorize sign-in explicitly.** Explain that it will contact OpenAI and store a refresh-capable token set in this iPhone's device-only Keychain. The user completes authentication; do not paste passwords/tokens into chat or source. Stop after sign-in and verify the intended account without exposing identifiers in public logs.
6. **Authorize controller enrolment separately.** Explain the persistent iPhone identity and Remote-controller access. Only then create one hardware key, complete step-up and send one enrolment finish. Save lifecycle state first; after an uncertain outcome, reconcile rather than repeating. A 403 is not permission to change endpoint/client/workspace or weaken attestation.
7. **Pair and confirm the exact Mac.** Claim one code, refresh client-scoped environments, compare the intended Mac and explicitly confirm it. Preserve account/controller/environment binding and any unknown result across restart.
8. **Read-only acceptance.** Refresh a controller session, complete the challenge/proof handshake, run initialize → initialized → thread/list → metadata-only thread/read for an existing selected thread. Compare the real ID/content on the host. Test cancel, foreground return, expired token and disconnect without auto-replay.
9. **Watch acceptance, then commands.** Only after phone read-only success add the live Watch source. Check foreground/background/locked phone, unavailable phone, duplicated taps, stale snapshot and interrupted connection. Obtain the exact test command and target; test one bounded existing-thread command before enabling general mutations. Keep the host's existing approval/permission settings.

Stop and report the exact stage on failure. A compiled app is not signed/installed; sign-in is not enrolment; pairing is not a relay handshake; relay is not correct-thread execution; an iPhone result is not a physical Watch result.
