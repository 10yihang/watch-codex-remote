# watch-codex-remote

Native SwiftUI iPhone and Apple Watch companion prototype, plus an offline protocol probe.

**Current status: demo-only. Real Codex Remote authentication, pairing and existing-session access are not implemented or verified.**

## Project

- [`watch-codex-companion`](watch-codex-companion/README.md): Xcode project, WatchConnectivity demo, Swift core tests and device checklist.
- [`watch-codex-probe`](watch-codex-probe/README.md): offline protocol encoding/signature tests and preserved upstream source references.

Open `watch-codex-companion/WatchCodex.xcodeproj` with Xcode 16 or newer. The targets require iOS 17+ and watchOS 10+.

## Cloud verification

The `Apple simulator build` workflow uses standard GitHub-hosted Ubuntu and `macos-15` runners. It runs on pushes to `main`/`master`, pull requests and manual dispatch:

1. Run 16 source/project checks and 20 offline Node.js protocol tests.
2. Run 18 Swift core XCTest cases.
3. Build the iPhone and Watch simulator apps with signing disabled.
4. Retain the Apple build log for seven days.

The workflow has read-only repository permissions, does not use repository secrets, and does not enroll devices, sign in, pair hosts, sign builds or install on physical devices. A passing build does not verify UI appearance, iPhone lock-screen operation, WatchConnectivity on devices or real Remote compatibility. Historical test reports describe the original pre-CI state; check the workflow run for current Apple-build results.

To run the equivalent checks on a Mac with Xcode selected:

```sh
python3 watch-codex-companion/Scripts/check_source.py
node --test watch-codex-probe/probe.test.mjs
bash watch-codex-companion/Scripts/verify_apple.sh
```

## Third-party source

The probe includes reference files from rcodex (MIT) and OpenAI Codex (Apache-2.0). Their licenses and pinned source revisions are preserved under `watch-codex-probe/upstream/` and documented in the probe README. The source files are references for offline tests, not an installed or executed Remote client.
