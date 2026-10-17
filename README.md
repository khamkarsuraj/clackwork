# Clackwork

A native macOS menu bar utility that plays mechanical keyboard sounds as you type in any app.

## Status

Early v1.0 development.

| Area                                                                      | State                                      |
| ------------------------------------------------------------------------- | ------------------------------------------ |
| Main window: profiles, preview, volume, Try it field, light and dark mode | Done                                       |
| Sound engine with 5 profiles                                              | Done, using synthesized placeholder sounds |
| System-wide key listener                                                  | Done                                       |
| Global shortcuts, customizable in Settings                                | Done                                       |
| Settings: launch at login, Dock icon, Input Monitoring status             | Done                                       |
| Menu bar popover and icon states                                          | Not started                                |
| Onboarding, HUD overlay                                                   | Not started                                |
| Recorded sound samples                                                    | Not started                                |
| Stereo positioning, auto-mute during calls, per-app exclusions            | Settings stored, behavior not built        |

## Build and run

- Xcode 26 or later. Deployment target is macOS 13 Ventura.
- Open `clackwork.xcodeproj`, select the `clackwork` scheme, and press Cmd+R.

## Permissions

Hearing keys in other apps requires **Input Monitoring**. Click "Allow Input Monitoring…" in the app, then enable Clackwork in System Settings. Listening starts on its own within a few seconds, with no relaunch.

Without the permission, sound still plays from the Preview button and the Try it field.

Debug builds from Xcode can lose the grant after a rebuild. If keys go silent, toggle Clackwork off and on in Input Monitoring.

## Privacy

The key listener is listen-only. It passes on only the key category, such as standard, space or modifier, and the key's position on the drawn keyboard for animation. Characters are never read, stored or sent anywhere. Password fields are skipped.

## Default shortcuts

| Action                    | Shortcut  |
| ------------------------- | --------- |
| Sound on or off           | ⌃⌥K       |
| Mute or unmute            | ⌃⌥M       |
| Next or previous keyboard | ⌃⌥→ / ⌃⌥← |
| Volume up or down         | ⌃⌥↑ / ⌃⌥↓ |

## Measuring latency

Key press to sound latency must stay under 20 ms (PRD NFR, issue #32). It has four parts:

| Part | What it covers | How it's measured |
| --- | --- | --- |
| Delivery | Hardware key event to the event tap | Live, with the latency probe |
| Hand-off | Event tap to the sound being scheduled | Live, with the latency probe |
| Render wait | Scheduled to the next audio cycle, at most one IO buffer | From the device's buffer size |
| Output | Audio cycle to the speaker | From the device's reported latency |

**Live measurement.** In Xcode, open Product > Scheme > Edit Scheme > Run > Arguments and add `-measureLatency YES`. Run the app, grant Input Monitoring, and type at least 100 keys in any app. Every 100 key presses the Xcode console prints p50, p95 and max for each part and for the total. The probe records timestamps only, never which key was pressed.

**Audio path only.** No key presses needed:

```
clackwork.app/Contents/MacOS/clackwork --latency-report 1
```

To compare IO buffer sizes, add `-ioBufferFrames 128` or any other size.

Bluetooth headphones add 100 ms or more of their own latency, which the app can't reduce. Measure with built-in speakers or wired output.

## Project layout

```
clackwork/
├── App/          App entry, object container, debug tooling
├── Diagnostics/  Latency probe
├── Audio/        Sound engine and placeholder sound synthesizer
├── Listener/     System-wide key event tap
├── Models/       Profiles, key types, keyboard layout, shortcuts
├── Shortcuts/    Global hot key registration
├── State/        App state and shortcut store
└── Views/        Main window, Keyboards, Settings, Shortcuts
```

## Debug tools

Debug builds accept launch flags that need no screen recording permission. Run the binary inside the built app:

```
clackwork.app/Contents/MacOS/clackwork --snapshot <out.png> [--dark] [--section settings]
clackwork.app/Contents/MacOS/clackwork --export-sounds <dir>
clackwork.app/Contents/MacOS/clackwork --stress-sounds 300
clackwork.app/Contents/MacOS/clackwork --test-shortcuts 1
clackwork.app/Contents/MacOS/clackwork --test-keymap 1
clackwork.app/Contents/MacOS/clackwork --latency-report 1
```
