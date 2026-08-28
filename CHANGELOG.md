## Unreleased

- Localize the iPhone app in Spanish, French, Italian, and German.
- Add localized Sit and Stand quick actions to the iPhone Home Screen icon.
- Add a native iPhone controller with compact Sit, Stand, Raise, Lower, Stop, save-position, refresh, and settings controls.
- Share protocol, validation, and movement evaluation between the macOS helper and iPhone app.
- Persist iPhone desk selection and the one-time safety acknowledgement across launches and settings changes.
- Serialize iPhone Bluetooth requests, setup acknowledgements, and Stop handoffs.
- Harden iPhone restoration, Bluetooth startup, reconnect handling, settings mutations, and strict-concurrency verification.
- Add the black desk symbol and creator credit to the iPhone main screen.
- Add a white, symbol-only iPhone launch screen that reuses the main toolbar asset.
- Select complete height values on focus and dismiss the numeric keyboard when tapping outside a field.
- Keep the iPhone target compatible with the Xcode 16.4 compiler used by GitHub Actions.
- Repair remembered-desk startup, disconnected-peripheral cleanup, and unavailable-Bluetooth scan handling.
- Serialize settings edits, preserve migration state, and keep rounded targets inside configured limits.

## [1.0.0] - 2026-08-26

- Add Bluetooth controls for IKEA IDÅSEN standing desks.
- Add a self-contained native controller with no external tools or identifiers.
- Add menu-bar controls, saved positions, movement limits, safety checks, and diagnostics.
