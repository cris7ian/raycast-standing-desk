# Standing Desk for Raycast

Control an IKEA IDÅSEN standing desk from Raycast through Bluetooth Low Energy (BLE).

The extension shows the current height, stores Sit and Stand positions, moves to a target height, and stops active movement. Sit defaults to `70 cm`. Stand defaults to `110 cm`.

![Standing Desk extension icon](assets/extension-icon.png)

## Commands

| Command                          | Result                                               |
| -------------------------------- | ---------------------------------------------------- |
| **Manage Standing Desk**         | Opens the complete control view.                     |
| **Move Desk to Sit**             | Moves to the saved Sit position.                     |
| **Move Desk to Stand**           | Moves to the saved Stand position.                   |
| **Raise Desk**                   | Raises the desk by the configured step.              |
| **Lower Desk**                   | Lowers the desk by the configured step.              |
| **Stop Desk**                    | Cancels extension movement and sends a stop command. |
| **Save Current Height as Sit**   | Replaces the saved Sit position.                     |
| **Save Current Height as Stand** | Replaces the saved Stand position.                   |

The management view also supports a custom target height and desk selection reset.

## Requirements

- macOS with Bluetooth enabled.
- [Raycast](https://www.raycast.com/).
- Node.js 22 or later.
- Xcode Command Line Tools.
- An IKEA IDÅSEN or compatible LINAK desk controller.

## Install

1. Clone this repository.
2. Run `npm install`.
3. Run `npm run dev`.
4. Approve Bluetooth access when macOS asks.
5. Hold the desk Bluetooth button until its light flashes.
6. Open **Manage Standing Desk** in Raycast.

`npm run dev` compiles a signed universal helper for Apple silicon and Intel Macs. Raycast keeps the development extension after the process stops.

## First use

The first movement action shows a safety confirmation. Watch the desk during every movement and keep its path clear.

The extension finds the first device whose Bluetooth name contains `Desk`. It then stores the macOS Bluetooth identifier. Use **Forget Connected Desk** to select another desk.

Open Raycast extension preferences to change:

- Bluetooth name filter.
- Base, minimum, and maximum heights.
- Raise and Lower step size.

Saved Sit and Stand heights remain in Raycast local storage.

## Safety

Software cannot detect every collision or cable problem. Keep people, furniture, cables, and loose objects clear.

Movement stops when the desk reaches its target, receives a stop request, stalls, or exceeds 45 seconds. Use the physical desk control or disconnect power if software stopping fails.

Read [Safety](docs/SAFETY.md) before changing movement logic.

## Documentation

- [Architecture](docs/ARCHITECTURE.md) describes components, data flow, persistence, and failure boundaries.
- [Bluetooth protocol](docs/BLUETOOTH.md) documents characteristics, payloads, and height conversion.
- [Development](docs/DEVELOPMENT.md) covers setup, verification, and safe live testing.
- [Troubleshooting](docs/TROUBLESHOOTING.md) covers discovery, permissions, height calibration, and build failures.
- [Safety](docs/SAFETY.md) defines operator and contributor safeguards.

## Quick verification

```sh
npm ci
npm run lint
npm run typecheck
npm test
npm run build
```

These checks do not move the physical desk.

## Project status

The extension has connected to a real IKEA IDÅSEN controller and read its height. Automated verification covers TypeScript behavior, native height encoding, both Mac architectures, linting, type checking, and Raycast compilation.

Physical movement must remain an attended manual test.

## Protocol references

- [linak-desk-web](https://github.com/smailzhu/linak-desk-web)
- [idasen-desk-controller-mac](https://github.com/DWilliames/idasen-desk-controller-mac)

## License

[MIT](LICENSE)
