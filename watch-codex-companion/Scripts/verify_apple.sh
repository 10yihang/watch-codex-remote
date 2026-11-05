#!/bin/bash
# Run locally on a Mac with Xcode selected. Builds only: no login, signing, install or pairing.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null || ! command -v swift >/dev/null; then
  echo 'BLOCKED: Full Xcode and Swift are required. No Apple build has run.' >&2
  exit 2
fi
xcodebuild -version
swift --version
swift test
xcodebuild -list -project WatchCodex.xcodeproj
xcodebuild -project WatchCodex.xcodeproj -scheme WatchCodexPhone -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/apple \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WatchCodex.xcodeproj -scheme WatchCodexWatch -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath .build/apple \
  CODE_SIGNING_ALLOWED=NO build
printf '\nCore tests and both simulator builds completed. No simulator UI or device test has run.\n'
