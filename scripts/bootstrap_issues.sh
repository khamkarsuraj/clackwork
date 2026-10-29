#!/usr/bin/env bash
#
# Creates the GitHub labels, milestones, issues and project board for Thlick v1.0,
# based on docs/PRD.md. Safe to run more than once: existing labels are updated,
# and milestones, issues, comments and the project are only created when missing.
#
# Usage:
#   scripts/bootstrap_issues.sh            # apply
#   scripts/bootstrap_issues.sh --dry-run  # print what would happen, change nothing
#
# Requires the gh CLI, logged in with the `repo` and `project` scopes.

set -euo pipefail

REPO="${REPO:-khamkarsuraj/thlick}"
OWNER="${REPO%%/*}"
PROJECT_TITLE="Thlick v1.0"
IMPLEMENTED_MARKER="<!-- bootstrap:implemented -->"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

created=0
skipped=0
issue_urls=()

log() { printf '%s\n' "$*"; }

if ! gh auth status >/dev/null 2>&1; then
  log "gh is not logged in. Run: gh auth login --scopes project"
  exit 1
fi

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

label() { # name color description
  if (( DRY_RUN )); then
    log "[dry-run] label: $1"
  else
    gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null
    log "label: $1"
  fi
}

log "== Labels"
label "type:bug"      "d73a4a" "Something is broken"
label "type:feature"  "1d76db" "New user-facing behavior"
label "type:task"     "5319e7" "Work that is not a feature or a bug"
label "type:chore"    "c5def5" "Tooling, config and maintenance"
label "type:docs"     "0075ca" "Documentation"
label "type:test"     "bfd4f2" "Tests and test infrastructure"

label "priority:P0"   "b60205" "Required for launch"
label "priority:P1"   "d93f0b" "Should ship in v1.0 if time allows"
label "priority:P2"   "fbca04" "Later"

label "area:audio"       "0e8a16" "Sound engine and samples"
label "area:listener"    "0e8a16" "System-wide key listener"
label "area:menubar"     "0e8a16" "Menu bar icon and popover"
label "area:main-window" "0e8a16" "Main window"
label "area:onboarding"  "0e8a16" "First-launch onboarding"
label "area:settings"    "0e8a16" "Settings"
label "area:shortcuts"   "0e8a16" "Global shortcuts and HUD"
label "area:ci"          "0e8a16" "CI, builds and releases"
label "area:privacy"     "0e8a16" "Keystroke privacy and permissions"
label "area:a11y"        "0e8a16" "Accessibility"

label "good first issue" "7057ff" "Good for newcomers"
label "blocked"          "000000" "Waiting on something else"
label "needs-design"     "f9d0c4" "Needs a design decision or screen"
label "needs-decision"   "f9d0c4" "Needs a decision from the owner"

# ---------------------------------------------------------------------------
# Milestones (PRD schedule)
# ---------------------------------------------------------------------------

M1="M1 Sound engine prototype"
M2="M2 Profiles + popover"
M3="M3 Main window, settings, shortcuts, HUD"
M4="M4 Onboarding + polish + a11y"
M5="M5 Beta + launch (v1.0.0)"

existing_milestones="$(gh api "repos/$REPO/milestones?state=all&per_page=100" --jq '.[].title')"

milestone() { # title description
  if grep -Fxq "$1" <<<"$existing_milestones"; then
    log "milestone exists: $1"
  elif (( DRY_RUN )); then
    log "[dry-run] milestone: $1"
  else
    gh api -X POST "repos/$REPO/milestones" -f title="$1" -f description="$2" >/dev/null
    log "milestone: $1"
  fi
}

log "== Milestones"
milestone "$M1" "Weeks 1-2: sound engine prototype with one profile, latency measured."
milestone "$M2" "Weeks 3-4: record and edit all 5 profiles, menu bar popover."
milestone "$M3" "Weeks 5-6: main window, settings, global shortcuts, HUD."
milestone "$M4" "Week 7: onboarding, light and dark polish, accessibility pass."
milestone "$M5" "Week 8: beta, bug fixes, launch."

# ---------------------------------------------------------------------------
# Issues
# ---------------------------------------------------------------------------

existing_issues="$(gh issue list --repo "$REPO" --state all --limit 1000 \
  --json number,title,url --jq '.[] | "\(.number)\t\(.url)\t\(.title)"')"

# issue TITLE LABELS MILESTONE [IMPLEMENTED_NOTE] <<'EOF' body EOF
# IMPLEMENTED_NOTE, when set, is posted once as a comment saying the current code
# appears to meet the acceptance criteria. Issues are never closed by this script.
issue() {
  local title="$1" labels="$2" milestone="$3" implemented="${4:-}"
  local body url number
  body="$(cat)"

  url="$(awk -F'\t' -v t="$title" '$3 == t { print $2; exit }' <<<"$existing_issues")"
  if [[ -n "$url" ]]; then
    log "issue exists: $title"
    skipped=$((skipped + 1))
  elif (( DRY_RUN )); then
    log "[dry-run] issue: $title  [$labels] ($milestone)"
    created=$((created + 1))
    return
  else
    url="$(gh issue create --repo "$REPO" --title "$title" --body "$body" \
      --label "$labels" --milestone "$milestone")"
    existing_issues+=$'\n'"0"$'\t'"$url"$'\t'"$title"
    log "issue: $title -> $url"
    created=$((created + 1))
    sleep 1 # stay clear of GitHub's secondary rate limit on content creation
  fi
  issue_urls+=("$url")

  if [[ -n "$implemented" && $DRY_RUN -eq 0 ]]; then
    number="${url##*/}"
    if ! gh issue view "$number" --repo "$REPO" --json comments --jq '.comments[].body' \
        | grep -qF "$IMPLEMENTED_MARKER"; then
      gh issue comment "$number" --repo "$REPO" --body "$IMPLEMENTED_MARKER
The current code on \`main\` appears to meet these acceptance criteria. $implemented

Leaving this open for the owner to verify and close." >/dev/null
      log "  commented: implemented"
    fi
  fi
}

log "== Issues: functional requirements"

issue "Listen to key events system-wide" "type:feature,area:listener,priority:P0" "$M1" \
  "Implemented by the listen-only event tap in \`Listener/KeyListener.swift\`. Needs a manual check with Input Monitoring granted." <<'EOF'
**PRD:** FR-1 · **Priority:** P0

Receive key down and key up events from every app, system-wide.

### Acceptance criteria
- [ ] Key down and key up events from every app reach the app through a listen-only event tap.
- [ ] Only Input Monitoring is required, not Accessibility.
- [ ] Only the key category leaves the listener. Characters are never read, stored or logged.
- [ ] The listener stops completely when sound is disabled.
- [ ] Listening starts automatically once permission is granted, without a relaunch.

**Design:** `docs/design/Onboarding2.dc.html` (kept locally, not in the repo)
EOF

issue "Play the matching sample for each key type" "type:feature,area:audio,priority:P0" "$M1" \
  "Implemented in \`Audio/SoundEngine.swift\` with key types from \`Listener/KeyListener.swift\`." <<'EOF'
**PRD:** FR-2 · **Priority:** P0

Play the sample that matches the key type: standard, space, return, backspace or modifier.

### Acceptance criteria
- [ ] Space, Return (including keypad Enter), Backspace (including forward delete) and modifier keys each play their own sample.
- [ ] All other keys play the standard sample.
- [ ] Every profile has samples for all five key types.
EOF

issue "Vary each press with a random sample and ±3% pitch and volume" "type:feature,area:audio,priority:P0" "$M1" \
  "Implemented in \`Audio/SoundEngine.swift\`: random variation per press, varispeed rate and player volume within ±3%." <<'EOF'
**PRD:** FR-3 · **Priority:** P0

Pick a random sample variation and apply slight pitch and volume variance per press, so repeated presses don't sound identical.

### Acceptance criteria
- [ ] Each press picks one of at least 3 variations at random.
- [ ] Pitch varies by at most ±3% per press.
- [ ] Volume varies by at most ±3% per press.
EOF

issue "Support overlapping sounds during fast typing (150 WPM)" "type:feature,area:audio,priority:P0" "$M1" \
  "Implemented with a pool of 12 player voices. The debug stress test plays 400 keys 12 ms apart with no audio overload." <<'EOF'
**PRD:** FR-4 · **Priority:** P0

Sounds overlap during fast typing without clipping or dropped sounds.

### Acceptance criteria
- [ ] Typing at 150 WPM or faster plays every key without dropped sounds.
- [ ] Overlapping sounds don't clip.
- [ ] No audio overload messages under sustained fast typing.
EOF

issue "Ignore key repeat when a key is held" "type:feature,area:listener,priority:P0" "$M1" \
  "Implemented: auto-repeat key events are skipped in \`Listener/KeyListener.swift\`." <<'EOF'
**PRD:** FR-5 · **Priority:** P0

Holding a key plays one sound, not a stream of repeats.

### Acceptance criteria
- [ ] Holding any key plays exactly one sound.
- [ ] The key sounds again only after it is released and pressed again.
EOF

issue "Stay silent in secure input fields" "type:feature,area:listener,area:privacy,priority:P0" "$M1" \
  "Implemented: events are dropped while secure event input is enabled." <<'EOF'
**PRD:** FR-6 · **Priority:** P0

No sound plays while typing in password fields or other secure input, where macOS blocks key events.

### Acceptance criteria
- [ ] Typing in a password field plays no sound.
- [ ] Sound resumes as soon as focus leaves the secure field.
EOF

issue "Stereo positioning for keys" "type:feature,area:audio,priority:P1" "$M3" <<'EOF'
**PRD:** FR-7 · **Priority:** P1

Keys on the left sound slightly left, keys on the right slightly right.

### Acceptance criteria
- [ ] With the setting on, left-side keys pan left and right-side keys pan right.
- [ ] With the setting off, every key plays centered.
- [ ] The setting in Settings > Sound controls it. The toggle exists but has no effect yet.
EOF

issue "Profile list that switches sound instantly" "type:feature,area:main-window,priority:P0" "$M2" \
  "Implemented: the five profile cards in the Keyboards section switch the active profile immediately." <<'EOF'
**PRD:** FR-8 · **Priority:** P0

Show the list of 5 profiles. Selecting one switches the sound instantly.

### Acceptance criteria
- [ ] All 5 profiles from the PRD table are listed.
- [ ] Selecting a profile changes the sound of the next key press.
- [ ] The selected profile is clearly marked.

**Design:** `docs/design/Window.dc.html`, `docs/design/WindowDark.dc.html` (kept locally, not in the repo)
EOF

issue "Play a short preview when a profile is selected" "type:feature,area:audio,area:main-window,priority:P0" "$M2" \
  "Implemented: selecting a card plays a key, and the Preview button plays a short typing burst." <<'EOF'
**PRD:** FR-9 · **Priority:** P0

Play a short preview of the profile when it is selected.

### Acceptance criteria
- [ ] Selecting a profile plays a short sample of it.
- [ ] A Preview button plays a short typing sequence.

**Design:** `docs/design/Window.dc.html` (kept locally, not in the repo)
EOF

issue "Master volume slider independent of system volume" "type:feature,area:audio,priority:P0" "$M2" \
  "Implemented: the volume slider sets the engine's mixer volume, 0 to 100%." <<'EOF'
**PRD:** FR-10 · **Priority:** P0

A master volume slider from 0 to 100%, independent of the system volume.

### Acceptance criteria
- [ ] The slider ranges from 0% to 100%.
- [ ] Changing it doesn't change the macOS system volume.
- [ ] The new volume applies to the next key press.
EOF

issue "Remember profile, volume and on/off state across restarts" "type:feature,area:settings,priority:P0" "$M2" \
  "Implemented: selected profile, volume and on/off state are saved to UserDefaults." <<'EOF'
**PRD:** FR-11 · **Priority:** P0

The selected profile, volume and on/off state survive quitting and relaunching.

### Acceptance criteria
- [ ] After a relaunch the same profile is selected.
- [ ] After a relaunch the volume is the same.
- [ ] After a relaunch sound is on or off as it was.
EOF

issue "Enable and disable key listening" "type:feature,area:listener,area:main-window,priority:P0" "$M2" \
  "Implemented: the toolbar switch and the sound-off empty state turn listening fully on and off." <<'EOF'
**PRD:** FR-12 · **Priority:** P0

Enable/Disable turns key listening fully on or off.

### Acceptance criteria
- [ ] Disabling stops the event tap, not just the sound.
- [ ] Enabling starts it again without a relaunch.
- [ ] When disabled, the main window shows one clear "Turn on sound" action instead of greyed-out controls.

**Design:** `docs/design/WindowDisabled.dc.html` (kept locally, not in the repo)
EOF

issue "Mute with 15 min, 1 hour and until-unmuted options" "type:feature,area:menubar,priority:P0" "$M2" <<'EOF'
**PRD:** FR-13 · **Priority:** P0

Mute keeps the app running but silent, with "Mute for 15 min", "Mute for 1 hour" and "Until I unmute".

### Acceptance criteria
- [ ] The popover's mute button has a menu with the three options.
- [ ] Timed mutes unmute automatically when the time is up.
- [ ] While muted, keys make no sound but listening continues.

The mute state and timed mute already exist in `State/AppState.swift`. The popover UI does not.

**Design:** `docs/design/PopoverMuted.dc.html` (kept locally, not in the repo)
EOF

issue "Menu bar icon shows active, muted and disabled states" "type:feature,area:menubar,priority:P0" "$M2" <<'EOF'
**PRD:** FR-14 · **Priority:** P0

The menu bar icon changes to reflect the state: active, muted, or disabled.

### Acceptance criteria
- [ ] Three visually distinct icon states.
- [ ] The icon updates immediately when the state changes from anywhere: popover, window or shortcut.
- [ ] Icons work in light and dark menu bars.

**Design:** `docs/design/Main.dc.html`, `docs/design/PopoverDark.dc.html` (kept locally, not in the repo)
EOF

issue "Auto-mute while the microphone is in use" "type:feature,area:audio,priority:P1" "$M3" <<'EOF'
**PRD:** FR-15 · **Priority:** P1

As a setting, mute automatically while the microphone is in use, such as during calls.

### Acceptance criteria
- [ ] With the setting on, sound stops while any app uses the microphone.
- [ ] Sound returns when the microphone is released.
- [ ] The setting in Settings > Sound controls it. The toggle exists but has no effect yet.
EOF

issue "Per-app exclusion list" "type:feature,area:settings,priority:P1" "$M3" <<'EOF'
**PRD:** FR-16 · **Priority:** P1

Users can list apps where sound never plays, such as Zoom or Terminal.

### Acceptance criteria
- [ ] Settings has an Exclusions section to add and remove apps.
- [ ] No sound plays while an excluded app is frontmost.
- [ ] The list persists across restarts.
EOF

issue "Menu bar popover with the core controls" "type:feature,area:menubar,priority:P0" "$M2" <<'EOF'
**PRD:** FR-17 · **Priority:** P0

The menu bar icon opens a compact popover, about 280 px wide.

### Acceptance criteria
- [ ] Header row with the app name and the on/off switch.
- [ ] Keyboard picker listing the 5 profiles, with a checkmark on the active one.
- [ ] Volume slider with speaker icons at each end.
- [ ] Mute button with the timed-mute menu (FR-13).
- [ ] Footer with "Open Thlick", Settings and Quit.

**Design:** `docs/design/Main.dc.html`, `docs/design/PopoverDark.dc.html` (kept locally, not in the repo)
EOF

issue "Popover changes apply immediately" "type:feature,area:menubar,priority:P0" "$M2" <<'EOF'
**PRD:** FR-18 · **Priority:** P0

Every change made in the popover applies immediately. There is no Save button.

### Acceptance criteria
- [ ] Toggle, mute, volume and profile changes take effect on the next key press.
- [ ] The main window reflects popover changes immediately, and the reverse.
EOF

issue "Option to hide the Dock icon and run from the menu bar only" "type:feature,area:settings,area:menubar,priority:P0" "$M2" <<'EOF'
**PRD:** FR-19 · **Priority:** P0

Users can hide the Dock icon and run Thlick as a menu bar-only app.

### Acceptance criteria
- [ ] The "Show icon in Dock" setting hides and shows the Dock icon immediately.
- [ ] With the Dock icon hidden, the app stays reachable from the menu bar.
- [ ] The default is off (menu bar only) once the menu bar item exists.

The setting exists, but it defaults to on because there is no menu bar item yet.

**Design:** `docs/design/SettingsGeneral.dc.html` (kept locally, not in the repo)
EOF

issue "Launch at login, on by default after onboarding" "type:feature,area:settings,area:onboarding,priority:P0" "$M3" <<'EOF'
**PRD:** FR-20 · **Priority:** P0

Thlick starts at login, turned on by default when onboarding finishes.

### Acceptance criteria
- [ ] The "Open at login" setting registers and unregisters the login item.
- [ ] Finishing onboarding turns it on.
- [ ] The setting reflects the real system state, including changes made in System Settings.

The setting already uses `SMAppService`. Onboarding doesn't exist yet.
EOF

issue "Onboarding explains Input Monitoring and links to System Settings" "type:feature,area:onboarding,area:privacy,priority:P0" "$M4" <<'EOF'
**PRD:** FR-21 · **Priority:** P0

First launch explains why Input Monitoring is needed and links straight to System Settings.

### Acceptance criteria
- [ ] Step 1 says in one sentence what the app does.
- [ ] Step 2 explains why Input Monitoring is needed and promises "we never record what you type".
- [ ] An "Open System Settings" button opens the Input Monitoring pane.
- [ ] Onboarding can be skipped after step 2.

**Design:** `docs/design/Onboarding1.dc.html`, `docs/design/Onboarding2.dc.html` (kept locally, not in the repo)
EOF

issue "Detect permission grant and continue onboarding automatically" "type:feature,area:onboarding,priority:P0" "$M4" <<'EOF'
**PRD:** FR-22 · **Priority:** P0

When the user grants Input Monitoring, onboarding moves on by itself, without a restart.

### Acceptance criteria
- [ ] Granting permission advances the permission step within a few seconds.
- [ ] No relaunch is needed.

Permission detection and automatic listener start already exist in `State/AppState.swift`. The onboarding step doesn't.

**Design:** `docs/design/Onboarding2.dc.html` (kept locally, not in the repo)
EOF

issue "Onboarding: pick a profile and try typing" "type:feature,area:onboarding,priority:P0" "$M4" <<'EOF'
**PRD:** FR-23 · **Priority:** P0

Before finishing, the user picks a profile and tries it in a test field.

### Acceptance criteria
- [ ] Step 3 lists the 5 profiles.
- [ ] A test field plays the selected profile while typing.
- [ ] The chosen profile is saved.

**Design:** `docs/design/Onboarding3.dc.html` (kept locally, not in the repo)
EOF

issue "Onboarding: teach the main shortcuts and the menu bar icon" "type:feature,area:onboarding,priority:P0" "$M4" <<'EOF'
**PRD:** FR-24 · **Priority:** P0

The final onboarding step shows where the menu bar icon is and teaches the 3 main shortcuts.

### Acceptance criteria
- [ ] Step 4 highlights the menu bar icon.
- [ ] It shows the current shortcuts for sound on/off, mute and next keyboard.
- [ ] Finishing closes onboarding and doesn't show it again.

**Design:** `docs/design/Onboarding4.dc.html` (kept locally, not in the repo)
EOF

log "== Issues: global shortcuts"

issue "Shortcut: enable or disable sound (⌃⌥K)" "type:feature,area:shortcuts,priority:P0" "$M3" \
  "Implemented with Carbon hot keys in \`Shortcuts/HotKeyCenter.swift\`. The HUD is tracked separately." <<'EOF'
**PRD:** Global shortcuts table · **Priority:** P0

### Acceptance criteria
- [ ] ⌃⌥K toggles sound on and off from any app.
- [ ] The shortcut can be changed in Settings > Shortcuts.
- [ ] The change is visible in the app. The HUD overlay is a separate issue.
EOF

issue "Shortcut: mute or unmute (⌃⌥M)" "type:feature,area:shortcuts,priority:P0" "$M3" \
  "Implemented with Carbon hot keys in \`Shortcuts/HotKeyCenter.swift\`. The HUD is tracked separately." <<'EOF'
**PRD:** Global shortcuts table · **Priority:** P0

### Acceptance criteria
- [ ] ⌃⌥M toggles mute from any app.
- [ ] The shortcut can be changed in Settings > Shortcuts.
- [ ] The change is visible in the app. The HUD overlay is a separate issue.
EOF

issue "Shortcut: next keyboard profile (⌃⌥→)" "type:feature,area:shortcuts,priority:P0" "$M3" \
  "Implemented with Carbon hot keys in \`Shortcuts/HotKeyCenter.swift\`. The HUD is tracked separately." <<'EOF'
**PRD:** Global shortcuts table · **Priority:** P0

### Acceptance criteria
- [ ] ⌃⌥→ switches to the next profile from any app, wrapping around after the last.
- [ ] A key sound plays in the new profile as feedback.
- [ ] The shortcut can be changed in Settings > Shortcuts.
EOF

issue "Shortcut: previous keyboard profile (⌃⌥←)" "type:feature,area:shortcuts,priority:P1" "$M3" \
  "Implemented with Carbon hot keys in \`Shortcuts/HotKeyCenter.swift\`." <<'EOF'
**PRD:** Global shortcuts table · **Priority:** P1

### Acceptance criteria
- [ ] ⌃⌥← switches to the previous profile from any app, wrapping around before the first.
- [ ] A key sound plays in the new profile as feedback.
- [ ] The shortcut can be changed in Settings > Shortcuts.
EOF

issue "Shortcut: volume up and down (⌃⌥↑ / ⌃⌥↓)" "type:feature,area:shortcuts,priority:P1" "$M3" \
  "Implemented with Carbon hot keys in \`Shortcuts/HotKeyCenter.swift\`: 5% steps, clamped to 0-100%." <<'EOF'
**PRD:** Global shortcuts table · **Priority:** P1

### Acceptance criteria
- [ ] ⌃⌥↑ and ⌃⌥↓ change the master volume in steps from any app.
- [ ] Volume stays within 0-100%.
- [ ] A key sound plays at the new level as feedback.
- [ ] Both shortcuts can be changed in Settings > Shortcuts.
EOF

issue "Shortcut cheat sheet (⌘/)" "type:feature,area:shortcuts,priority:P1" "$M3" <<'EOF'
**PRD:** Global shortcuts table, design principle 5 · **Priority:** P1

### Acceptance criteria
- [ ] Pressing ⌘/ inside the app shows all shortcuts with their current key combos.
- [ ] The sheet reflects customized shortcuts.
- [ ] It closes with Escape or ⌘/.
EOF

log "== Issues: non-functional requirements"

issue "NFR: key press to sound under 20 ms" "type:task,area:audio,priority:P0" "$M1" <<'EOF'
**PRD:** Non-functional requirements, Latency · **Priority:** P0

### Acceptance criteria
- [ ] Measured key press to sound latency is under 20 ms, targeting 10 ms.
- [ ] Measured on both Apple silicon and Intel Macs.
- [ ] The measurement method is documented so it can be repeated.
EOF

issue "NFR: CPU under 1% idle and 5% while typing" "type:task,area:audio,area:listener,priority:P0" "$M1" <<'EOF'
**PRD:** Non-functional requirements, CPU · **Priority:** P0

### Acceptance criteria
- [ ] Average CPU is under 1% while idle.
- [ ] Average CPU is under 5% during sustained fast typing.
EOF

issue "NFR: memory under 80 MB with all profiles loaded" "type:task,area:audio,priority:P0" "$M1" <<'EOF'
**PRD:** Non-functional requirements, Memory · **Priority:** P0

### Acceptance criteria
- [ ] Memory stays under 80 MB with all 5 profiles loaded, measured with recorded samples, not the placeholders.
EOF

issue "NFR: download under 40 MB" "type:task,area:ci,priority:P0" "$M5" <<'EOF'
**PRD:** Non-functional requirements, App size · **Priority:** P0

### Acceptance criteria
- [ ] The release download is under 40 MB, including all recorded samples.
EOF

issue "NFR: ready to play sound within 1 second of launch" "type:task,area:audio,priority:P0" "$M3" <<'EOF'
**PRD:** Non-functional requirements, Startup · **Priority:** P0

### Acceptance criteria
- [ ] The first key press plays within 1 second of launch, with all profiles loaded.
EOF

issue "NFR: never store, log or send keystroke content" "type:task,area:privacy,priority:P0" "$M4" <<'EOF'
**PRD:** Non-functional requirements, Privacy · **Priority:** P0

### Acceptance criteria
- [ ] Keystroke content is never stored, logged or transmitted.
- [ ] Only the key category is used to pick a sound.
- [ ] No analytics on key events.
- [ ] A test guards the listener's output type against carrying characters.

**Open decision:** the listener also passes the key's position on the drawn keyboard for the press animation. Decide whether that is allowed and update the PRD to match.
EOF

issue "NFR: request only Input Monitoring" "type:task,area:privacy,priority:P0" "$M4" <<'EOF'
**PRD:** Non-functional requirements, Permissions · **Priority:** P0

### Acceptance criteria
- [ ] The app requests only Input Monitoring.
- [ ] Every feature works without Accessibility permission.
EOF

issue "NFR: support macOS 13 and later on Apple silicon and Intel" "type:task,area:ci,priority:P0" "$M5" <<'EOF'
**PRD:** Non-functional requirements, Compatibility · **Priority:** P0

### Acceptance criteria
- [ ] The app runs on macOS 13 Ventura and every later version.
- [ ] Universal build for Apple silicon and Intel.
- [ ] Newer-only APIs are guarded with availability checks.
EOF

issue "NFR: VoiceOver, keyboard navigation and Reduce Motion" "type:task,area:a11y,priority:P0" "$M4" <<'EOF'
**PRD:** Non-functional requirements, Accessibility · **Priority:** P0

### Acceptance criteria
- [ ] Every control has a VoiceOver label.
- [ ] All windows can be used with the keyboard alone.
- [ ] Animations respect Reduce Motion.

Note: sidebar arrow-key navigation is currently disabled so typing doesn't switch sections. Revisit for keyboard navigation.
EOF

issue "NFR: recover after sleep, audio device and permission changes" "type:task,area:audio,area:listener,priority:P0" "$M3" <<'EOF'
**PRD:** Non-functional requirements, Reliability · **Priority:** P0

### Acceptance criteria
- [ ] Sound keeps working after sleep and wake.
- [ ] Sound keeps working after the output device changes, such as plugging in headphones.
- [ ] Granting or revoking Input Monitoring is picked up without a relaunch.
EOF

log "== Issues: open questions"

issue "Decide pricing" "type:task,needs-decision" "$M5" <<'EOF'
**PRD:** Open questions

Free, one-time purchase, or free with paid sound packs?

### Acceptance criteria
- [ ] Pricing model decided and recorded in the PRD.
EOF

issue "Decide distribution: Mac App Store, direct download, or both" "type:task,needs-decision" "$M5" <<'EOF'
**PRD:** Open questions

Affects sandboxing, App Store review of Input Monitoring use, and whether Sparkle is needed.

### Acceptance criteria
- [ ] Distribution channel decided and recorded in the PRD.
EOF

issue "Decide whether key-up sounds are on by default" "type:task,needs-decision" "$M5" <<'EOF'
**PRD:** Open questions

The key-up setting was removed from Settings during development. Decide whether key-up sounds exist at all, and if so, the default.

### Acceptance criteria
- [ ] Decision recorded in the PRD.
EOF

log "== Issues: follow-ups"

issue "Release workflow: sign, notarize and publish DMG with Sparkle" "type:chore,area:ci,priority:P1" "$M5" <<'EOF'
A release workflow needs Apple Developer certificates the owner must provide.

### Acceptance criteria
- [ ] A tagged release builds, signs and notarizes the app.
- [ ] A DMG is published as a GitHub release.
- [ ] A Sparkle appcast is updated, if direct download is chosen.
EOF

issue "Performance test harness for latency NFR" "type:test,area:audio,priority:P1" "$M4" <<'EOF'
Latency, CPU and memory are checked by hand for now.

### Acceptance criteria
- [ ] A repeatable way to measure key press to sound latency.
- [ ] Results can be compared between builds.
EOF

issue "Redraw architecture diagram (dropped from PRD export)" "type:docs,priority:P2" "$M4" <<'EOF'
The PRD's "Technical architecture" section lost its embedded diagram in export.

### Acceptance criteria
- [ ] The diagram shows the key path: listener, key type, sound engine, output.
- [ ] It is added back to the PRD.
EOF

issue "Trademark check on profile names" "type:task,priority:P0" "$M5" <<'EOF'
Brand names describe the sound style only. Final display names need a trademark check before launch.

### Acceptance criteria
- [ ] All 5 profile names checked.
- [ ] Names changed where needed.
EOF

issue "Record sound samples for all 5 profiles" "type:task,area:audio,priority:P0" "$M2" <<'EOF'
The app currently plays sounds synthesized in code as placeholders.

### Acceptance criteria
- [ ] Each profile has recorded samples for standard down and up, space down and up, return, backspace and modifiers.
- [ ] At least 3 variations of each.
- [ ] All samples are recorded in-house or licensed.
- [ ] The engine loads the recordings instead of the synthesizer.
EOF

issue "Shortcut HUD overlay" "type:feature,area:shortcuts,priority:P0" "$M3" <<'EOF'
**PRD:** Design principles 1 and 5

A shortcut shows a small HUD near the bottom of the screen for 1.2 seconds, like the system volume overlay.

### Acceptance criteria
- [ ] Every shortcut shows a HUD with the new state, such as "Muted" or the new profile name.
- [ ] It disappears after 1.2 seconds.
- [ ] It works in light and dark mode and respects Reduce Motion.

**Design:** `docs/design/HUD.dc.html` (kept locally, not in the repo)
EOF

# ---------------------------------------------------------------------------
# Project board
# ---------------------------------------------------------------------------

log "== Project board"

if (( DRY_RUN )); then
  log "[dry-run] project: $PROJECT_TITLE with Backlog, Ready, In progress, In review, Done"
  log "Done (dry run). Would create $created issues, $skipped already exist."
  exit 0
fi

project_number="$(gh project list --owner "$OWNER" --format json \
  --jq ".projects[] | select(.title == \"$PROJECT_TITLE\") | .number" | head -1)"
if [[ -z "$project_number" ]]; then
  project_number="$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json --jq '.number')"
  log "project: created #$project_number"
else
  log "project exists: #$project_number"
fi
gh project link "$project_number" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 || true

project_id="$(gh project view "$project_number" --owner "$OWNER" --format json --jq '.id')"
status_field_id="$(gh project field-list "$project_number" --owner "$OWNER" --format json \
  --jq '.fields[] | select(.name == "Status") | .id')"
current_options="$(gh project field-list "$project_number" --owner "$OWNER" --format json \
  --jq '.fields[] | select(.name == "Status") | [.options[].name] | join(",")')"

wanted_options="Backlog,Ready,In progress,In review,Done"
if [[ "$current_options" != "$wanted_options" ]]; then
  gh api graphql --input - >/dev/null <<EOF
{
  "query": "mutation(\$id: ID!, \$opts: [ProjectV2SingleSelectFieldOptionInput!]) { updateProjectV2Field(input: {fieldId: \$id, singleSelectOptions: \$opts}) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }",
  "variables": {
    "id": "$status_field_id",
    "opts": [
      {"name": "Backlog",     "color": "GRAY",   "description": "Not started"},
      {"name": "Ready",       "color": "BLUE",   "description": "Ready to pick up"},
      {"name": "In progress", "color": "YELLOW", "description": "Being worked on"},
      {"name": "In review",   "color": "PURPLE", "description": "PR open"},
      {"name": "Done",        "color": "GREEN",  "description": "Merged and verified"}
    ]
  }
}
EOF
  log "project: Status columns set to $wanted_options"
fi

backlog_id="$(gh project field-list "$project_number" --owner "$OWNER" --format json \
  --jq '.fields[] | select(.name == "Status") | .options[] | select(.name == "Backlog") | .id')"

for url in "${issue_urls[@]}"; do
  gh project item-add "$project_number" --owner "$OWNER" --url "$url" >/dev/null
done
log "project: ${#issue_urls[@]} issues added"

# New items have no status; put them in Backlog. Items already moved are left alone.
# The item list lags right after item-add, so give it a moment to catch up.
sleep 5
no_status_items="$(gh project item-list "$project_number" --owner "$OWNER" --limit 1000 --format json \
  --jq '.items[] | select((.status // "") == "") | .id')"
moved=0
while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  gh project item-edit --id "$item" --project-id "$project_id" \
    --field-id "$status_field_id" --single-select-option-id "$backlog_id" >/dev/null
  moved=$((moved + 1))
done <<<"$no_status_items"
log "project: $moved items placed in Backlog"

log "Done. Created $created issues, $skipped already existed."
log "Project: https://github.com/users/$OWNER/projects/$project_number"
