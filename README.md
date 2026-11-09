# watch-codex-remote

Native SwiftUI iPhone + Apple Watch companion with an **experimental real Remote connection path** and a separate demo.

**This local candidate is not yet compiled or tested on an Apple device. No successful real account connection is claimed.** The old `f7de911` build/CI result does not validate these changes.

The real tab now calls native browser OAuth → separate Remote step-up → Secure Enclave enrollment → explicit Mac pairing/selection → relay → existing-thread read/send/stop. It does not import desktop credentials or require an extra host bridge. Credentials stay on iPhone; Watch sends bounded, destination-bound commands through WatchConnectivity.

This is an unofficial private-interface integration. The public Codex OAuth application identifier is taken from the pinned MIT NightBlood reference, not an app-specific registered identifier. It is not a secret and its availability does not establish third-party service support. Runtime rejection and upstream protocol changes remain possible.

## Open and validate

Open `watch-codex-companion/WatchCodex.xcodeproj` in Xcode 16 or newer. iOS 17+ and watchOS 10+ are required. Preserve your local development team, bundle IDs and Watch companion ID when applying source changes. Do not replace signing settings with template defaults.

```sh
python3 watch-codex-companion/Scripts/check_source.py
node --test watch-codex-probe/probe.test.mjs
bash watch-codex-companion/Scripts/verify_apple.sh
```

Passed locally: 26 source/project checks (including 12 OAuth structural checks) and 20 offline Node protocol tests. There are 70 Swift XCTest methods in the candidate; **none were executed for this revision**, and neither simulator target was built. Full Xcode and Swift are absent from the local Linux environment.

See [real connection implementation and device acceptance](watch-codex-companion/Docs/LIVE_CONNECTION.md).

## Boundaries

- Nothing logs in, enrolls a device or reconnects automatically at launch.
- Login and device enrollment require separate in-app confirmations. Keys/tokens are device-only Keychain items; device signing uses Secure Enclave and user presence.
- Every pairing, host selection, send and stop is explicit. No new thread/fork, permission/model/cwd override, hidden host bridge, background command queue or automatic mutation replay.
- Unknown mutations are journaled before dispatch and locked across restart until the affected host/thread is read and the user acknowledges the result.
- iPhone must remain open and unlocked. Backgrounding closes the relay. No background/lock-screen reliability claim is made.
- Real flow is the default tab/page. Demo data and commands use a different wire envelope and cannot enter the real controller.

## Sources

The original offline probe preserves rcodex MIT and OpenAI Codex Apache-2.0 references under `watch-codex-probe/upstream/`. Native authentication follows [NightBlood Remote at 4824aceb1cd04ac521f7f0342771c20edad60dac](https://github.com/jonathanroomer/NightBloodRemote/tree/4824aceb1cd04ac521f7f0342771c20edad60dac), with its notices preserved under `watch-codex-companion/ThirdParty/NightBloodRemote/`. No voice, CarPlay, branding or desktop transcript bridge is included.
