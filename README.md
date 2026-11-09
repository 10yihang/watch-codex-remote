# watch-codex-remote

Native SwiftUI iPhone and Apple Watch companion prototype, plus an offline protocol probe.

**Current status: demo UI plus an experimental native connection layer. Live authentication and connectivity are not available or verified.**

The new Swift layer implements device signing, Secure Enclave key storage, enrollment/pairing HTTP requests and read-only relay access to existing threads. It stays inactive until an approved app-specific Remote authorization flow exists. See [implementation, blocker and validation status](watch-codex-companion/Docs/REMOTE_IMPLEMENTATION.md). This candidate has not yet passed an Apple build.

## Local native OAuth preparation

A dormant iPhone OAuth implementation adapted from MIT-licensed NightBlood Remote is included for review. Its configuration is disabled and empty, it has no UI or launch call sites, and it does not enroll or pair a device. No Swift build or live authentication has been verified for this candidate. See [the source comparison, exact scope and validation checklist](watch-codex-companion/Docs/NATIVE_AUTH_ASSESSMENT.md).

## Project

- [`watch-codex-companion`](watch-codex-companion/README.md): Xcode project, WatchConnectivity demo, Swift core tests and device checklist.
- [`watch-codex-probe`](watch-codex-probe/README.md): offline protocol encoding/signature tests and preserved upstream source references.

Open `watch-codex-companion/WatchCodex.xcodeproj` with Xcode 16 or newer. The targets require iOS 17+ and watchOS 10+.

## Cloud verification

The `Apple simulator build` workflow uses standard GitHub-hosted Ubuntu and `macos-15` runners. It runs on pushes to `main`/`master`, pull requests and manual dispatch:

1. Run source/project guardrails and 20 offline Node.js protocol tests.
2. Run Swift core and new native Remote XCTest cases.
3. Build the iPhone and Watch simulator apps with signing disabled.
4. Retain the Apple build log for seven days.

The workflow has read-only repository permissions, does not use repository secrets, and does not enroll devices, sign in, pair hosts, sign builds or install on physical devices. A passing build does not verify UI appearance, iPhone lock-screen operation, WatchConnectivity on devices or real Remote compatibility. An earlier demo-only revision passed on 2026-11-05 ([historical run](https://github.com/10yihang/watch-codex-remote/actions/runs/41960076332)); that result does not cover this candidate's new connection layer. Use the workflow run for the exact commit being tested.

To run the equivalent checks on a Mac with Xcode selected:

```sh
python3 watch-codex-companion/Scripts/check_source.py
node --test watch-codex-probe/probe.test.mjs
bash watch-codex-companion/Scripts/verify_apple.sh
```

## Third-party source

The probe includes reference files from rcodex (MIT) and OpenAI Codex (Apache-2.0). Their licenses and pinned source revisions are preserved under `watch-codex-probe/upstream/` and documented in the probe README. The source files are references for offline tests, not an installed or executed Remote client.


The native OAuth preparation preserves NightBlood Remote’s MIT license and notices under `watch-codex-companion/ThirdParty/NightBloodRemote/`. It does not include NightBlood branding, voice, CarPlay or desktop transcript integration.
