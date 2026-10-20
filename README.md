# Clackwork

A native macOS menu bar utility that plays mechanical keyboard sounds as you type in any app.

## Status

Early v1.0 development.

| Area                                                                      | State                                      |
| ------------------------------------------------------------------------- | ------------------------------------------ |
| Main window: profiles, preview, volume, Try it field, light and dark mode | Done                                       |
| Sound engine with 4 profiles: Cherry MX Blue, Brown, Black and Red        | Done, using development recordings; in-house recordings pending (#49) |
| System-wide key listener                                                  | Done                                       |
| Global shortcuts, customizable in Settings                                | Done                                       |
| Settings: launch at login, Dock icon, Input Monitoring status             | Done                                       |
| Menu bar popover and icon states                                          | Not started                                |
| Onboarding, HUD overlay                                                   | Not started                                |
| In-house or confirmed-license recordings                                  | Not started                                |
| Auto-mute during calls, per-app exclusions                                | Settings stored, behavior not built        |

## Build and run

- Xcode 26 or later. Deployment target is macOS 13 Ventura.
- Open `clackwork.xcodeproj`, select the `clackwork` scheme, and press Cmd+R.

## Tests

Press Cmd+U in Xcode, or run:

```
xcodebuild test -project clackwork.xcodeproj -scheme clackwork -destination 'platform=macOS'
```

Unit tests live in `clackworkTests/` and use Swift Testing. Each suite names the PRD requirement or issue it covers. They need no sound packs, audio device or Input Monitoring permission. The keyboard animation test briefly opens a small borderless window.

CI runs the same tests on every pull request and on every push to `main` (`.github/workflows/ci.yml`). Mark `build-and-test` as a required check in the branch settings so a pull request can't merge until it passes. CPU, memory and latency targets are still measured by hand; see the sections below.

## Permissions

Hearing keys in other apps requires **Input Monitoring**. Click "Allow Input Monitoring…" in the app, then enable Clackwork in System Settings. Listening starts on its own within a few seconds, with no relaunch.

Without the permission, sound still plays from the Preview button and the Try it field.

Debug builds from Xcode can lose the grant after a rebuild. If keys go silent, toggle Clackwork off and on in Input Monitoring.

## Privacy

The key listener is listen-only. It passes on only the key category, such as standard, space or modifier, and the key's position on the drawn keyboard for animation. Characters are never read, stored or sent anywhere. Password fields are skipped.

## Default shortcuts

| Action                    | Shortcut  |
| ------------------------- | --------- |
| Sound on or off           | ⌃⌥O       |
| Mute or unmute            | ⌃⌥M       |
| Next or previous keyboard | ⌃⌥→ / ⌃⌥← |
| Volume up or down         | ⌃⌥↑ / ⌃⌥↓ |
| Show keyboard shortcuts   | ⌃⌥S       |

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
clackwork.app/Contents/MacOS/clackwork --test-soundpacks 1
```

To compare IO buffer sizes, add `-ioBufferFrames 128` or any other size.

Bluetooth headphones add 100 ms or more of their own latency, which the app can't reduce. Measure with built-in speakers or wired output.

## Measuring CPU

CPU must stay under 1% on average while idle and under 5% during sustained fast typing (PRD NFR, issue #33). Measure a Release build; Debug builds are unoptimized and not representative.

Add the launch argument `-measureCPU YES`, either in Xcode (Product > Scheme > Edit Scheme > Run, with Build Configuration set to Release) or from Terminal:

```
open clackwork.app --args -measureCPU YES
```

Every 15 seconds the probe logs the app's average CPU, as a percentage of one core (the same scale as Activity Monitor). It splits the time into three parts. Typing is seconds with at least one key press, and the log also shows the typing rate. Settling is the first 5 seconds after the last key, while sounds and animations finish. Idle is everything after that. It skips the first 10 seconds after launch, and it counts key presses only, never which key was pressed. To watch the log outside Xcode:

```
log stream --predicate 'subsystem == "com.surajkhamkar.clackwork" && category == "cpu"'
```

For the typing number, type fast and steadily for at least 15 seconds in another app. Check idle both with the main window open and with it closed.

## Measuring startup

The first key press must play within 1 second of launch, with every profile loaded (PRD NFR, issue #36). Measure a Release build; a Debug build loads the packs unoptimized and takes several times longer.

Add the launch argument `-measureStartup YES`, or run the binary from Terminal:

```
clackwork.app/Contents/MacOS/clackwork -measureStartup YES
```

Each milestone prints the time since the kernel started the process, so dyld and framework loading count too: `sounds ready` (every pack decoded and pitch-rendered, engine running), `listener on` (the key tap is up, or why it isn't) and `menu bar icon up` (drawn on the first pass of the run loop). On an Apple silicon MacBook a Release build reports sounds ready at 400–600 ms and the listener on about 50 ms later, so the first key can play with every pack loaded well inside the budget. The milestones also go to the unified log:

```
log stream --predicate 'subsystem == "com.surajkhamkar.clackwork" && category == "startup"'
```

## Project layout

```
clackwork/
├── App/          App entry, object container, debug tooling
├── Diagnostics/  Latency and CPU probes
├── Audio/        Sound engine and recorded pack loader
├── Listener/     System-wide key event tap
├── Models/       Profiles, key types, keyboard layout, shortcuts
├── Shortcuts/    Global hot key registration
├── Sounds/       Recorded sound packs bundled with the app, and their license notices
├── State/        App state and shortcut store
└── Views/        Main window, Keyboards, Settings, Shortcuts
clackworkTests/   Unit tests
```

## Sound packs

Recorded packs live in `clackwork/Sounds/` as `<profile-id>.caf` and `<profile-id>.json`, one per profile: `mx-blue`, `mx-brown`, `mx-black` and `mx-red`. A profile without a pack is silent.

Sound packs are not committed; each developer keeps them locally. A pack is a folder with one audio file and a `config.json` that maps key scan codes to `[start ms, duration ms]` slices of it. To add one, run:

```
scripts/import_soundpack.sh <pack-folder> <profile-id>
```

Keep each pack's license notice in `clackwork/Sounds/ThirdPartyNotices.txt` so it ships with the sounds.

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
