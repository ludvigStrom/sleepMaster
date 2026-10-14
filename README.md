# Sleepmaster

macOS 14+ menu-bar app that keeps the Mac awake. Lives in the menu bar only (no Dock icon). Current release is **1.0.2**.

Click the moon → turn it on. Outline moon when off, amber eye when on, grey eye + “Paused” on battery pause.

## How it stays awake

Two layers:

1. **IOKit assertion** (always). Blocks idle sleep with no password. Released on off, Quit, or crash (`kill -9`).
2. **Lid closed** (optional, on by default). Also runs `pmset disablesleep` so closing the lid does not sleep. Needs the Sleepmaster helper (root). Until you approve it in System Settings › General › Login Items, that path may ask for a password once. After approval, toggles are silent.

Sleep is allowed again when you turn it off, when a timer ends, when you quit, or when the helper sees the app die. On battery below **10%**, lid-closed is forced off so a closed Mac does not drain in a bag.

If an older build left `SleepDisabled` on, launch offers a one-time reset.

## Using it

Global toggle from any app: **⌥⌘S**. Settings: **⌘,** from the popover. Quit: **⌘Q**.

### Modes

- **Indefinitely** — stays awake until you turn it off.
- **Timer** — chips for 15 min, 30 min, 1 / 2 / 4 / 8 hours, or **Until a specific time…** (a time earlier than now means tomorrow). End is stored as a `Date`, so it still fires after display sleep. While a timer runs: **+30 min** / **+1 hour**.

The popover shows `h:mm:ss`. The menu bar can show `h:mm` next to the icon (Settings).

### Applies to both modes

- **Only while plugged in** — on battery the assertion is released but the session stays on (“Paused on battery”). Replug restores it; a running timer keeps counting.
- **Allow the display to sleep** — system stays awake, screen can go dark. Default keeps the display on. Changing it while on swaps the assertion with no gap.

**Stay awake with the lid closed** is Settings-only. Needs power and an external display.

### Automation

A **manual off always wins** until the same trigger fires again (app relaunches or goes busy again, you plug in again, the schedule window starts again).

- **Watched apps** — Add app… then pick a mode per app:
  - **While running** — on while that app is launched (default).
  - **While busy** — on only while that app’s process tree (helpers, node, and so on) is over the CPU threshold. Cross for ~2 s → busy; stay under for ~10 s → idle. Default threshold **25% of one core** (5–80% in Settings). Status: `Awake while Cursor is busy` vs `Awake while Cursor runs`.
- **Turn on automatically when plugged in** — AC starts Indefinitely; unplug turns it off.
- **Schedule** — days + from/to (overnight windows wrap midnight).

### Notifications

Permission is requested the first time a timer starts, not at launch.

- Warning before the timer ends (default 5 min, 1–15). Actions: **+30 min**, **Keep awake** (Indefinitely), **Let it sleep**.
- Optional banner when paused on battery (one shot, no repeats on power blips).

### Settings

| Section | What |
| --- | --- |
| General | Appearance (Light / Dark / Follow OS), launch at login, show time in menu bar, shortcut |
| When turned on | Default mode and timer, remember last choice |
| Power & battery | Plug-only, auto-on when plugged in, battery floor (5–50%, default 20%), lid closed |
| Automation | Watched apps + busy CPU stepper, schedule |
| Notifications | Warning lead, pause banner |

First launch shows a one-screen onboarding (modes + launch at login). After a `/Applications` install, launch at login is on.

Battery floor: even with plug-only off, sleep is allowed when battery is below the floor.

## Requirements

- macOS 14 or later
- Apple Developer ID to ship a signed, notarized `.pkg` (debug builds work unsigned)

## Develop

```bash
open SleepMaster.xcodeproj
```

Targets: **SleepMaster** (app), **SleepMasterHelper** (privileged daemon, XPC `setSleepDisabled`), **SleepMasterTests** (logic tests; they compile app sources, they are not hosted in the app).

```bash
xcodebuild test -scheme SleepMaster -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/SleepMasterDerived
```

Stack: Swift + SwiftUI, `@Observable` `AppState`, `MenuBarExtra` `.window`, `SMAppService` (login item + helper daemon). Sparkle 2 for updates when `SU_FEED_URL` is set. Debug builds leave the feed empty.

## Release

```bash
cp Scripts/release.env.example Scripts/release.env   # TEAM_ID + NOTARY_PROFILE
# Optional Sparkle: SU_FEED_URL and SU_PUBLIC_ED_KEY (public key only)
bash Scripts/release_pkg_notarize.sh 1.0.2
```

The script builds a universal unsigned app, signs inside-out (Sparkle XPCs → framework → helper → app) with Developer ID + hardened runtime, writes a Sparkle zip, builds a signed `.pkg`, notarizes, and staples.

Output:

- `Build/dist/SleepMaster-1.0.2.pkg` — installer
- `Build/dist/SleepMaster-1.0.2.zip` — Sparkle payload

On a **second Mac**:

```bash
spctl -a -v /Applications/SleepMaster.app
```

Expect `accepted`.

Sparkle local test: generate EdDSA keys with Sparkle’s `generate_keys`, put the **public** key in `SU_PUBLIC_ED_KEY`, point `SU_FEED_URL` at a local `appcast.xml`, host the newer zip + appcast, launch the older build.

Full Gatekeeper / VoiceOver / light-mode notes and the signed-build regression checklist: [build runbook.md](build%20runbook.md). Phase history: [Sleepmaster roadmap.md](Sleepmaster%20roadmap.md).
