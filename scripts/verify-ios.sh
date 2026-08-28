#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$project_root/ios/StandingDesk.xcodeproj"
scheme="Standing Desk"
swift_checks=(
  SWIFT_STRICT_CONCURRENCY=complete
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
)

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  "${swift_checks[@]}" \
  build

target_build_dir="$(
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -sdk iphonesimulator \
    -destination "generic/platform=iOS Simulator" \
    CODE_SIGNING_ALLOWED=NO \
    -showBuildSettings |
    sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p' |
    sed -n '1p'
)"
built_info_plist="$target_build_dir/Standing Desk.app/Info.plist"
development_region="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' "$built_info_plist")"

if [[ "$development_region" != "en" ]]; then
  echo "Expected CFBundleDevelopmentRegion to be en, got: $development_region" >&2
  exit 1
fi

simulator_id="${1:-}"
if [[ -z "$simulator_id" ]]; then
  simulator_id="$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]+iPhone[^()]*(\(([0-9A-F-]{36})\)).*/\2/p' | sed -n '1p')"
fi

if [[ -z "$simulator_id" ]]; then
  echo "No available iPhone simulator was found." >&2
  exit 1
fi

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  CODE_SIGNING_ALLOWED=NO \
  "${swift_checks[@]}" \
  test
