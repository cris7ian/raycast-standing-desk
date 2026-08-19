# Development

## Prerequisites

- macOS.
- Node.js 22 or later.
- npm 7 or later.
- Xcode Command Line Tools.
- Raycast stable.

## Setup

```sh
npm ci
npm run dev
```

`npm run dev` builds the native helper before Raycast starts development mode.

## Source map

| Path                      | Responsibility                                      |
| ------------------------- | --------------------------------------------------- |
| `src/manage-desk.tsx`     | Full Raycast interface and action coordination.     |
| `src/desk-menu.tsx`       | Persistent menu-bar status and common actions.      |
| `src/quick-command.ts`    | Shared direct-command behavior.                     |
| `src/native.ts`           | Native process execution and JSON event parsing.    |
| `src/storage.ts`          | Presets, selected desk, and safety acknowledgement. |
| `src/model.ts`            | Pure configuration and height validation.           |
| `native/DeskBLE.swift`    | CoreBluetooth state machine and movement safety.    |
| `scripts/build-native.sh` | Universal helper build and signing.                 |

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

## Safe live testing

Use three verification levels.

### Level 1: Offline

Run linting, type checking, tests, and the Raycast production build. This level cannot contact or move the desk.

### Level 2: Status only

Quit other desk-control applications if connection fails. Then run:

```sh
./assets/deskctl status \
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

GitHub Actions runs the offline verification suite on macOS for pushes and pull requests. CI does not have a desk and must never attempt Bluetooth discovery.
