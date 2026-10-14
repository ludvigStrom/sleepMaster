# Sleepmaster build runbook

## Release

```bash
cp Scripts/release.env.example Scripts/release.env   # set TEAM_ID + NOTARY_PROFILE
# Optional Sparkle: SU_FEED_URL and SU_PUBLIC_ED_KEY (public key only)
bash Scripts/release_pkg_notarize.sh 1.0.0
```

The script builds unsigned, signs the nested helper then the app (Developer ID + hardened runtime), zips the `.app` for Sparkle, builds a signed `.pkg`, notarizes, and staples.

After installing the pkg on a **second Mac**:

```bash
spctl -a -v /Applications/SleepMaster.app
```

Expect `accepted`.

### Sparkle local update test

1. Generate EdDSA keys with Sparkle’s `generate_keys`. Put the **public** key in `SU_PUBLIC_ED_KEY`. Keep the private key off git.
2. Build 1.0.0 and 1.0.1 with `SU_FEED_URL` pointing at a local `appcast.xml`.
3. Host the newer zip + appcast (`python3 -m http.server` or `file://`).
4. Launch the 1.0.0 build; it should find 1.0.1 and install.

Debug builds leave `SU_FEED_URL` empty so they do not check for updates.

### VoiceOver (9.1)

With VoiceOver on: open the menu extra, toggle Keep Mac awake, switch Mode, pick a chip, flip both Applies-to-both-modes switches, open Settings, and walk every row. Status title is announced on change. Everything is reachable from the keyboard (Tab / Space / ⌥⌘S / ⌘, / ⌘Q).

### Light mode and Reduce Transparency (9.2)

Open the popover and Settings in light and dark. Enable System Settings › Accessibility › Display › Reduce transparency. Cards stay opaque; amber and type stay readable.

---

## Regression checklist

Re-run on a **signed Release** build and tick each line.

### Phase 0
- [ ] Toggle behaves as before (`SleepController`)
- [ ] `pmset -g assertions` lists Sleepmaster when on, not when off; no password
- [ ] Energy sleep 1 minute; toggle on, idle 5 minutes, stays awake; toggle off, sleeps
- [ ] Toggle on, `kill -9`; assertion disappears
- [ ] Manual `SleepDisabled 1`; launch, accept reset; reads 0

### Phase 1
- [ ] Lid closed on: ping answers 2 minutes; lid closed off: sleeps
- [ ] Quit: `pmset -g` shows SleepDisabled 0
- [ ] Helper approved in Login Items; XPC flips SleepDisabled with no password
- [ ] Differently signed client is rejected
- [ ] Helper approved: toggle 10 times, no password
- [ ] Toggle on, `kill -9`: SleepDisabled 0 within 5 seconds
- [ ] Battery below 10% on battery: SleepDisabled goes to 0

### Phase 2
- [ ] Unit: flip `isActive` calls the controller
- [ ] Icon opens popover; power button toggles
- [ ] Icon: outline moon off, amber eye on, within 1 second
- [ ] Quit releases the assertion
- [ ] No Dock icon, no app switcher entry

### Phase 3
- [ ] Switch modes while on; stays awake
- [ ] 1-minute timer turns off on time, including after display sleep
- [ ] Each chip sets the right end time (`Allows sleep at HH:MM`)
- [ ] Popover h:mm:ss and menu bar h:mm stay in sync
- [ ] +30 min / +1 hour move the end time
- [ ] Until 23:00 at 22:58 turns off at 23:00
- [ ] Relaunch keeps mode and chip; starts off

### Phase 4
- [ ] Log / subtitle flips within 2 seconds of unplug/replug
- [ ] Plug subtitle flips when you unplug
- [ ] On → unplug → no assertion → replug → assertion back
- [ ] 30 min, unplug 10 min, replug: ~20 min remain
- [ ] Paused on battery + grey eye + “Paused”
- [ ] Floor 1 above current level: sleep allowed

### Phase 5
- [ ] Display sleep 1 minute: screen dark, download continues
- [ ] Flip display-sleep while on: never zero Sleepmaster assertions

### Phase 6
- [ ] Settings opens in front; second click does not duplicate
- [ ] Launch at login: log out/in; app running, starts off
- [ ] Show time off: timer is eye only
- [ ] Remember off: relaunch uses defaults
- [ ] ⌥⌘S toggles while another app is focused
- [ ] Settings and popover share plug / floor / display / lid-closed (lid-closed is Settings-only)

### Phase 7
- [ ] Permission prompt only on first timer
- [ ] 6-minute timer: banner at ~1 minute (`Your Mac can sleep in N minutes.`)
- [ ] +30 min / Keep awake / Let it sleep work without opening the popover
- [ ] Unplug while on: one pause banner, no blip repeats

### Phase 8
- [ ] Manual off while auto reasons true stays off until a reason fires again
- [ ] Auto-on when plugged in: AC on indefinitely / amber; unplug off
- [ ] Watch TextEdit: launch on, quit off
- [ ] Schedule starting in 2 minutes turns on and later off

### Phase 9
- [ ] Full flow with VoiceOver only
- [ ] Popover and Settings readable in light, dark, and Reduce Transparency
- [ ] Onboarding once on a clean account
- [ ] `spctl -a -v SleepMaster.app` accepted on a second Mac
- [ ] Older Sparkle build finds and installs the newer one
