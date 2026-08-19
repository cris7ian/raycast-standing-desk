# Architecture

## Overview

The extension separates Raycast user interface code from physical Bluetooth control. A signed Swift helper owns all CoreBluetooth operations.

```mermaid
flowchart LR
    User[Raycast user] --> Commands[Raycast commands]
    Commands --> UI[TypeScript UI and actions]
    UI --> Runner[Native process runner]
    Runner --> Helper[Swift deskctl helper]
    Helper --> CoreBluetooth[Apple CoreBluetooth]
    CoreBluetooth --> Desk[IKEA IDASEN desk]
    UI <--> Storage[Raycast LocalStorage]
    UI --> StopFile[Stop request file]
    Helper --> StopFile
    Helper --> Lock[Movement lock file]
```

## Components

### Raycast manifest

`package.json` defines the command entry points and pins the Raycast API to the installed stable runtime.

### Management view

`src/manage-desk.tsx` renders desk status, presets, adjustment actions, custom height input, and recovery actions. It streams native progress into the visible height and toast messages.

### Menu-bar view

`src/desk-menu.tsx` renders an icon-only macOS menu-bar item. Its menu shows the last reported height without opening Bluetooth during startup. It hands movement and save actions to dedicated Raycast commands so work continues after the menu closes. Manual refresh remains available for a current reading.

### Direct commands

The Sit, Stand, Raise, Lower, Stop, Save Sit, and Save Stand entry points call shared functions in `src/quick-command.ts`.

### Domain and persistence

`src/model.ts` defines safe defaults and validates configuration and target heights. `src/storage.ts` stores settings, presets, the selected desk identifier, the last reported height, and the safety acknowledgement through Raycast `LocalStorage`.

### Native process bridge

`src/native.ts` validates settings, starts `assets/deskctl`, parses newline-delimited JSON events, and updates the stored desk identifier.

The bridge uses two support files:

- `stop-request` stores the latest movement request identifier. A newer request cancels an older helper.
- `movement.lock` prevents concurrent movement helpers.

### Bluetooth helper

`native/DeskBLE.swift` discovers the desk, connects, resolves required characteristics, reads height, and sends movement commands. It emits `status`, `progress`, `complete`, and `error` events as JSON lines.

`scripts/build-native.sh` compiles `arm64` and `x86_64` executables. It combines them with `lipo`, embeds `native/Info.plist`, and applies an ad-hoc signature.

## Movement sequence

1. TypeScript validates the requested target.
2. The bridge publishes a unique movement request identifier.
3. An active helper detects the new identifier and stops.
4. The new helper waits up to five seconds for the movement lock.
5. A superseded helper exits without connecting to the desk.
6. CoreBluetooth discovers and connects to the desk.
7. The helper reads the current height.
8. The helper wakes and stops the controller before movement.
9. The helper writes the target every 400 milliseconds.
10. Height notifications and explicit reads update progress.
11. The helper stops after two readings within `0.25 cm`.

Movement also stops after cancellation, a stall, a Bluetooth error, or 45 seconds.

## Failure boundaries

- Raycast owns user feedback. The extension owns settings and saved positions.
- The bridge owns process lifecycle and inter-process cancellation.
- The helper owns protocol validation and emergency stop writes.
- The physical controller remains the final stop mechanism.

No layer assumes that a software stop always succeeds.
