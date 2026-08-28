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
