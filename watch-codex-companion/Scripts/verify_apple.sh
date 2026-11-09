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
validation_id=net.example.watchcodex.validation
mkdir -p .build/apple
xcodebuild -list -project WatchCodex.xcodeproj
xcodebuild -project WatchCodex.xcodeproj -scheme WatchCodexPhone -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/apple \
  CODE_SIGNING_ALLOWED=NO WATCH_CODEX_PHONE_BUNDLE_ID="$validation_id" build
xcodebuild -project WatchCodex.xcodeproj -scheme WatchCodexWatch -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath .build/apple \
  CODE_SIGNING_ALLOWED=NO WATCH_CODEX_PHONE_BUNDLE_ID="$validation_id" build
# Command-line overrides do not rewrite source project/signing settings.
xcodebuild -project WatchCodex.xcodeproj -scheme WatchCodexPhone -configuration Release \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings -json \
  CODE_SIGNING_ALLOWED=NO WATCH_CODEX_PHONE_BUNDLE_ID="$validation_id" > .build/apple/phone-release-settings.json
xcodebuild -project WatchCodex.xcodeproj -scheme WatchCodexWatch -configuration Release \
  -destination 'generic/platform=watchOS Simulator' -showBuildSettings -json \
  CODE_SIGNING_ALLOWED=NO WATCH_CODEX_PHONE_BUNDLE_ID="$validation_id" > .build/apple/watch-release-settings.json
python3 Scripts/validate_bundle_products.py --products .build/apple/Build/Products \
  --expected-phone "$validation_id" \
  --phone-release-settings .build/apple/phone-release-settings.json \
  --watch-release-settings .build/apple/watch-release-settings.json
printf '\nCore tests and both simulator builds completed. No simulator UI or device test has run.\n'
