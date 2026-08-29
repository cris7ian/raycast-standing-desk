#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$project_root/ios/StandingDesk.xcodeproj"
scheme="Standing Desk"
derived_data="$project_root/.build/derived_data"
swift_checks=(
  SWIFT_STRICT_CONCURRENCY=complete
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
)

simulator_id="${1:-}"
if [[ -z "$simulator_id" ]]; then
  # Prefer an already-booted iPhone simulator to avoid cold-boot latency
  simulator_id="$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]+iPhone[^()]*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | head -n 1)"
fi
if [[ -z "$simulator_id" ]]; then
  # Fallback to the latest available iPhone simulator
  simulator_id="$(xcrun simctl list devices available | sed -nE 's/^[[:space:]]+iPhone[^()]*\(([0-9A-F-]{36})\).*/\1/p' | tail -n 1)"
fi

if [[ -z "$simulator_id" ]]; then
  echo "No available iPhone simulator was found." >&2
  exit 1
fi

destination="platform=iOS Simulator,id=$simulator_id"

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  "${swift_checks[@]}" \
  build-for-testing

built_info_plist="$derived_data/Build/Products/Debug-iphonesimulator/Standing Desk.app/Info.plist"
development_region="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' "$built_info_plist")"

if [[ "$development_region" != "en" ]]; then
  echo "Expected CFBundleDevelopmentRegion to be en, got: $development_region" >&2
  exit 1
fi

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  "${swift_checks[@]}" \
  test-without-building
