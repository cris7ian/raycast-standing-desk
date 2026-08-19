# Troubleshooting

## Desk discovery times out

1. Confirm Bluetooth is enabled.
2. Hold the desk Bluetooth button until its light flashes.
3. Move the Mac within 8 meters of the desk.
4. Quit other desk-control applications.
5. Use **Forget Connected Desk** before selecting another desk.

The default scan matches Bluetooth names containing `Desk`. Change the name filter in Raycast preferences when necessary.

## Bluetooth access is denied

Open **System Settings > Privacy & Security > Bluetooth**. Enable access for **Standing Desk Bluetooth Helper**.

If the helper is absent, run **Manage Standing Desk** once to trigger the permission request.

## Height has a constant offset

Change **Base Height** in Raycast extension preferences. The default is `62 cm`.

Measure the desktop surface at the lowest position. Use that measurement when the controller reports zero.

## Desk stops before the target

Check for an obstruction, load imbalance, or controller limit. The extension reports a stall after repeated stationary readings.

Do not increase timeouts or remove stall detection until the physical cause is excluded.

## Stop reports a connection error

The stop request file can still cancel an extension-owned movement. Use the physical control when the desk continues moving or another application owns the Bluetooth connection.

## Native helper is missing

Run:

```sh
npm run build:native
```

Then restart `npm run dev`.

## Raycast development command targets another app

Pin `@raycast/api` to a version compatible with the installed stable Raycast application. A newer major API can target a separate development bundle.

Check the installed app version:

```sh
defaults read /Applications/Raycast.app/Contents/Info CFBundleShortVersionString
```

## Another movement is active

Run **Stop Desk**. Wait for the active helper to release the movement lock, then retry.

If no movement exists, close Raycast and remove only the extension support lock after confirming no `deskctl` process is running.
