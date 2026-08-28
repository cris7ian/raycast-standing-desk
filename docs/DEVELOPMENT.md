# Development

## Prerequisites

- macOS.
- Node.js 22.22.2 or later.
- npm 7 or later.
- Xcode Command Line Tools.
- Xcode with an iOS 17 or later simulator runtime for iPhone development.
- Raycast stable.

## Setup

```sh
npm ci
npm run dev
```

`npm run dev` builds the native helper before Raycast starts development mode.

## Source map

| Path                            | Responsibility                                       |
| ------------------------------- | ---------------------------------------------------- |
| `src/manage-desk.tsx`           | Full Raycast interface and action coordination.      |
| `src/desk-menu.tsx`             | Persistent menu-bar status and common actions.       |
| `src/settings-form.tsx`         | Settings validation and default restoration.         |
| `src/quick-command.ts`          | Shared direct-command behavior.                      |
| `src/native.ts`                 | Native process execution and JSON event parsing.     |
| `src/storage.ts`                | Settings, presets, selected desk, and safety state.  |
| `src/model.ts`                  | Pure configuration and height validation.            |
| `src/diagnostics.ts`            | Bounded and redacted diagnostic logging.             |
| `native/DeskBLE.swift`          | CoreBluetooth state machine and movement safety.     |
| `native/StandingDeskCore.swift` | Shared protocol, validation, and movement policy.    |
| `ios/StandingDesk/`             | SwiftUI views, persistence, and iOS Bluetooth owner. |
| `ios/StandingDeskTests/`        | Disconnected iOS unit tests.                         |
| `scripts/verify-ios.sh`         | iOS simulator build and unit-test verification.      |
| `scripts/build-native.sh`       | Universal helper build and signing.                  |

Native architecture intermediates are written to `.raycast-swift-build`, which the Raycast publisher excludes from Store submissions.

## Verification

Run the complete suite:

```sh
npm run lint
npm run typecheck
npm test
npm run build
git diff --check
```

`npm test` runs Vitest, builds the native helper, and runs native protocol self-tests.

Verify the iPhone app separately:

```sh
scripts/verify-ios.sh
```

The script builds for a generic iPhone simulator with complete Swift concurrency checks. It then runs tests on the first available iPhone simulator.

GitHub Actions runs the same script on `macos-15`. Keep the iPhone source compatible with the runner's stable Xcode toolchain.

### Run on a personal iPhone

1. Open `ios/StandingDesk.xcodeproj` in Xcode.
2. Select your Personal Team for the **Standing Desk** target.
3. Connect and select your iPhone.
4. Run the application.

Xcode can write the selected development team into the project. Review signing changes before committing; another developer must select their own team.

## Safe live testing

Use three verification levels.

### Level 1: Offline

Run linting, type checking, tests, and the Raycast production build. This level cannot contact or move the desk.

### Level 2: Status only

Quit other desk-control applications if connection fails. Discover the local CoreBluetooth identifier first:

```sh
./assets/deskctl discover --name Desk --discovery-timeout 5
```

Copy the reported `identifier` value. Then run:

```sh
desk_identifier="PASTE_COREBLUETOOTH_UUID_HERE"
./assets/deskctl status \
  --identifier "$desk_identifier" \
  --name Desk \
  --base-height 62 \
  --minimum-height 62 \
  --maximum-height 127 \
  --connection-timeout 8
```

This command connects and reads height without sending a movement command. Do not commit its device identifier output.

### Level 3: Physical movement

Run movement only with explicit authorization. Inspect the desk area first and keep the physical control within reach.

## Native changes

After editing Swift, run:

```sh
npm run build:native
./assets/deskctl self-test
lipo -archs assets/deskctl
codesign --verify --verbose assets/deskctl
```

The architecture output must contain `arm64` and `x86_64`. Commit the rebuilt `assets/deskctl` with its source change.

## Raycast compatibility

The local Raycast application and `@raycast/api` must use compatible runtimes. Check the installed version with:

```sh
defaults read /Applications/Raycast.app/Contents/Info CFBundleShortVersionString
```

Do not accept a major API update only because npm reports it as latest. Confirm that `npm run dev` targets the installed stable Raycast bundle.

## Continuous integration

GitHub Actions runs the Raycast and iPhone offline verification suites for pushes and pull requests. CI does not have a desk and must never attempt Bluetooth discovery.

## GitHub release

The `VERSION` file defines the release version. Before creating a release, update `VERSION` and `CHANGELOG.md`. Create an annotated tag named `v` followed by that version. Pushing the tag starts the release workflow.

The workflow verifies the extension, builds a production Raycast bundle, creates source and bundle ZIP files, calculates SHA-256 checksums, and publishes a GitHub Release.

Build release assets locally with:

```sh
scripts/package-release.sh "$(tr -d '[:space:]' < VERSION)" release
```

Run local packaging from a clean worktree. The script rejects dirty worktrees and version mismatches so the source archive and bundle represent the same commit.

The source archive is the supported local installation route. Extract it, run `npm ci && npm run dev`, and keep the source directory available to Raycast. The prebuilt bundle is a release artifact. It does not replace the Raycast local-extension workflow.

## Raycast Store release

Treat every file in the working tree as publishable. Before publishing, inspect `git status --short`. Move unrelated untracked files outside the repository. Do not rely on `.gitignore` to exclude them from the Raycast publisher.

Store screenshots belong in `metadata/`. Raycast accepts up to six screenshots and recommends at least three. Each screenshot must be a `2000 x 1250` PNG.

Target approximately `12%` padding around the Raycast window. The current Store validator accepts `8%–17%` per side. It permits at most `4%` vertical or horizontal asymmetry.

Use one background across the screenshot set. Do not include credentials, CoreBluetooth identifiers, or content from other applications.

Run the complete verification suite, then publish:

```sh
npm run publish
```

Running the command again updates the existing open Store pull request.

## iPhone App Store web pages

The iPhone bundle identifier is `com.salsaparapizza.standingdesk`.

Privacy and support pages use a private S3 bucket behind CloudFront at `standingdesk.salsaparapizza.com`. Publish them with the `personal` AWS profile:

```sh
scripts/publish-app-store-pages.sh
```

The static site source is `app-store-release-prep/web/`. The command uploads the complete directory to the private `standingdesk.salsaparapizza.com` bucket in `eu-west-1`, preserves unrelated bucket objects, and invalidates CloudFront distribution `E3C0WPKC4RFR6O`.

The publisher applies no-cache headers to HTML, `robots.txt`, `sitemap.xml`, and `site.webmanifest`. It verifies the public HTTPS pages, required assets, manifest content type, and final headline after the invalidation completes.
