# Standing Desk for Raycast

Control an IKEA IDÅSEN desk from Raycast. The extension connects directly to the desk through Bluetooth Low Energy (BLE).

## Features

- View the current desk height.
- Move to a saved Sit or Stand position.
- Save the current height as Sit or Stand.
- Raise or lower the desk by a configurable step.
- Move to a custom height.
- Stop active movement.
- Run Sit, Stand, Raise, Lower, Stop, and Save commands directly from Raycast.

Sit defaults to `70 cm`. Stand defaults to `110 cm`.

## Install

1. Install Xcode Command Line Tools and Node.js.
2. Run `npm install` in this directory.
3. Run `npm run dev`.
4. Approve Bluetooth access when macOS asks.
5. Hold the desk Bluetooth button until its light flashes.
6. Open **Manage Standing Desk** in Raycast.

The native helper is built for Apple silicon and Intel Macs. Raycast starts it when a command needs Bluetooth access.

## Safety

Watch the desk while it moves. Keep people, cables, furniture, and objects clear. Use **Stop Desk** or the physical desk control if movement becomes unsafe.

Movement stops when the desk reaches its target, stalls, receives a stop request, or exceeds 45 seconds.

## Troubleshooting

- Quit other desk-control applications before connecting. Many desk controllers permit only one active client.
- Put the desk in pairing mode if discovery times out.
- Open System Settings > Privacy & Security > Bluetooth if access was denied.
- Change **Base Height** if the displayed height has a constant offset.
- Use **Forget Connected Desk** when you want to select a different nearby desk.

The extension remembers the first matching desk by its macOS Bluetooth identifier.

## Technical notes

The helper uses the LINAK Bluetooth characteristics present in the IDÅSEN controller. Heights use hundredths of a centimeter above the configured base height.

Protocol references:

- [linak-desk-web](https://github.com/smailzhu/linak-desk-web)
- [idasen-desk-controller-mac](https://github.com/DWilliames/idasen-desk-controller-mac)
