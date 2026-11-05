# Watch Codex companion

A native iPhone + Apple Watch prototype for scanning an existing Codex thread, adding a short instruction, and targeting the exact active turn when stopping work.

This build is an honest demo, not a connected Remote client. The supported iOS authorization path is unresolved. The app must never infer Remote authentication from phone/watch reachability. No login, device enrollment, persistent keys, controller pairing, desktop credential import, network socket, or actual host mutation is implemented.

The demo can run independently on the watch or exchange demo messages with the iPhone through WatchConnectivity. These are visibly separate modes. No queued mutation, automatic retry, silent fallback, new thread creation, fork, permissions override or fake execution success is allowed.

Audience: a Chinese-speaking developer checking work in short, on-the-go moments. Main information: task title, current state, last concise update, snapshot time, and the real destination of an action. Success is truthful state and a few deliberate taps.

Platforms: iPhone only, iOS 17+; companion watchOS app, watchOS 10+. SwiftUI, Foundation and WatchConnectivity only. No external runtime dependencies.
