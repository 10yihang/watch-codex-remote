> Historical report. This local candidate now wires the experimental real flow and supersedes the disabled/read-only claims below. See [LIVE_CONNECTION.md](LIVE_CONNECTION.md) for current scope and the verified cloud build for `eac3ae0`. Real-device behavior remains unverified.

# Native Remote connection work

## 2026-11-09 cloud validation update

Native connection and dormant OAuth code at `fa96253133a17fc27d32cb9949c2d64e6fdd8646` passed [run 42632249643](https://github.com/10yihang/watch-codex-remote/actions/runs/42632249643): 24 project/source checks, 20 Node protocol tests, 49 Swift core tests, both unsigned simulator builds and demo screenshot capture. Xcode 16.4 / Swift 6.1.2 were used. OAuth is still disabled; no real login, Keychain operation, device enrolment, pairing, live host command or physical-device test was performed. The core tests do not exercise the OAuth runtime. A follow-up resolves a Notification sendability warning; check the exact current commit's CI as well.

The original preparation report below is historical. Its earlier “not run” Apple-build statements were superseded by the cloud evidence above, not by the local source checks.


Prepared 2026-11-05 from main `70b91065aede43e0de70f9d645d536f6dbe2cf70`.

## What changed

- `RemoteSigning.swift`: native canonical enrollment/refresh/WebSocket payloads, account/client/session/token binding, SHA-256 and P-256 DER proofs. Exact rcodex golden vectors have Swift tests.
- `RemoteDeviceKey.swift`: explicit Secure Enclave key creation, protected device-only Keychain wrapping, identity validation, signing and removal. No software fallback, launch-time creation, desktop credentials or token storage.
- `RemoteAPI.swift`: real bounded HTTPS requests for enrollment/refresh, pairing, host listing and revocation. Fixed service origin, no redirects/cookies/cache, finite timeouts and no automatic retries. Mutation transport failures and malformed successful responses are unknown outcomes, never permission to repeat enrollment.
- `RemoteRelay.swift`: native URLSession WebSocket challenge/proof handshake, relay v3 framing, initialize/initialized, existing thread list and metadata read. Correlates requests, ignores old streams/duplicate sequences, rejects routing mismatches/gaps, bounds incoming frames and closes on timeout.
- The iPhone connection page describes the actual missing authorization prerequisite and offers a memory-only signature/encoding self-check. It does not open a socket or persist a key.

The connection modules are included in the iPhone target and the Swift package. They are not wired to demonstration commands. WatchConnectivity and the demo engine remain separate; the Watch cannot accidentally execute a real command by switching its demo source.

## What is still blocked

There is no verified, provider-approved independent iOS OAuth client/redirect and Remote relay grant for this app. The shipped UI therefore cannot log in, enroll or connect. It has no token-paste field, desktop client ID, credential import, remote feature toggle or fabricated login callback.

The public [Sign in with ChatGPT OSS flow](https://developers.openai.com/siwc/token-sharing-open-source) does support third-party client registration. Its [documented scopes and resource](https://developers.openai.com/siwc/token-sharing-open-source/sign-in) cover eligible Responses API use, not Codex Remote enrollment or ChatGPT conversations. It must not be treated as a Remote credential source without explicit provider support.

[rcodex](https://github.com/Typiqally/rcodex/tree/8d839ae673e0c8d895e334adbf786ead0325c24d) uses a desktop CLI ChatGPT session and observed, undocumented controller enrollment. A pairing code alone does not supply the ChatGPT bearer token, controller session token or device proof required by its relay. The native code preserves this protocol boundary rather than manufacturing missing authority.

No user credential was read, no production request was made, no persistent key was created, no account was enrolled or paired, and no host was changed while implementing this candidate.

## Current deliberately limited scope

- Relay operations are read-only: `initialize`, `thread/list` and `thread/read`. There is no native resume/start/interrupt yet and no thread creation/fork. Add mutations only after the approved read-only handshake is validated against a selected host and real existing thread.
- Returned App Server JSON remains raw, bounded and correlated. There is no live thread UI adapter or Watch forwarding yet, so a synthetic response cannot become a live-looking conversation.
- One in-flight RPC. No automatic reconnect or replay. ACK is not an App Server response.
- 150 KiB WebSocket frame cap, 1 MiB HTTP response cap; relay chunks are rejected explicitly rather than partially assembled. Metadata-only reads reduce but do not eliminate this limitation.
- No background relay, continuous watchOS networking, notification delivery, signing/distribution, token refresh storage or approved native OAuth implementation.
- iOS key protection is real platform code but its service-side acceptance is unverified. The simulator may test ephemeral protocol signatures; Secure Enclave creation intentionally fails if the hardware is unavailable.

## Verification of this candidate

- Passed: 23 Python source/project guardrails, including dormant key creation and absence of desktop credential paths.
- Passed: the existing 20 Node offline protocol tests.
- Added: native signature, session-binding, relay routing, header/pair-code/path, decoding and account-binding XCTest cases, included in `swift test`.
- Not run: **any Swift tests or Apple builds for this candidate**. The current Linux workspace has neither Swift nor Xcode; `Scripts/verify_apple.sh` exits 2 with an explicit blocker. Prior commits' successful Actions runs do not validate these changes.
- Not run: native self-check UI, network integration, Secure Enclave hardware, account enrollment, actual host reads, physical Watch tests or device installation.

## Next validation gate

1. Publish only after the owner approves the source changes and standard GitHub macOS CI. Run the existing workflow on the exact resulting commit; fix compile/test failures before calling the code buildable.
2. Obtain the app-specific, provider-approved Remote OAuth client/redirect, audience/scopes, step-up contract and iOS key-identity acceptance. Do not substitute a desktop token or unrelated Responses API grant.
3. Implement that specific OAuth contract and bind it to the account IDs expected by the protocol. On the device, separately request clear approval before persistent controller enrollment; keep an uncertain enrollment recoverable rather than automatically deleting its key or retrying.
4. With approval, enroll one device, obtain one host pairing code, select that host explicitly, and confirm that revocation works. Check the advertised App Server version against the validated protocol schema.
5. Run `initialize → initialized → thread/list → thread/read` against the user's known thread. Compare IDs/content on the host. Only a successful read of actual data establishes real connectivity.
6. Add explicit existing-thread resume/turn/interrupt and a separate live Watch source, then validate one user-selected test command, duplicate taps, timeout, lock/suspend, restart and reconnection. Never create a substitute thread after failure.

## Source and license attribution

Canonical payloads and the relay/API shapes are adapted from Typiqally/rcodex at `8d839ae673e0c8d895e334adbf786ead0325c24d`, copyright holders and MIT terms preserved in [`../../watch-codex-probe/upstream/LICENSE`](../../watch-codex-probe/upstream/LICENSE). App Server request schemas follow the pinned OpenAI Codex reference and Apache-2.0/NOTICE files in the same upstream directory. These are unofficial client implementations, not a claim of OpenAI or Apple approval.
