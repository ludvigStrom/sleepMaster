# Sleepmaster roadmap

Oct 14, 2026 · @Ludvig

## How to use this roadmap

Ten phases take Sleepmaster from one sudo toggle to the full app; every checkbox is one small change with its own test. Finish and test each box before the next. Every phase ends in a build you could ship. Phases 5–8 can be reordered freely.

**Key decision: two layers of keep-awake.** IOKit power assertions (`IOPMAssertionCreateWithName`) block idle sleep with no password and are released automatically if the app quits or crashes. They cannot stop sleep when the lid closes. Only `pmset disablesleep` can, and it needs root. Lid-closed mode is the core feature, so Phase 1 brings it back right away: first with the old password prompt, then through a helper you approve once in System Settings.

Assumed stack: Swift + SwiftUI, macOS 14 or later (`MenuBarExtra`, `SMAppService`, and `@Observable`).

## Phase 0 — No more password

Goal: the existing toggle works exactly as today, without ever asking for a password.

- [x] **0.1 Put the toggle behind a `SleepController` protocol.** Methods `start()`, `stop()`, `isActive`; the current pmset code becomes `PmsetSleepController`. Test: the toggle behaves exactly as before.
- [x] **0.2 Add `AssertionSleepController`.** It creates a `kIOPMAssertionTypePreventUserIdleSystemSleep` assertion named "Sleepmaster" and releases it on stop. Test: `pmset -g assertions` lists Sleepmaster when on and not when off, with no password prompt.
- [x] **0.3 Make the assertion controller the default.** Test: set Energy sleep to 1 minute, toggle on, leave the Mac idle 5 minutes; it stays awake. Toggle off; it sleeps.
- [x] **0.4 Verify release on quit and crash.** Test: toggle on, then `kill -9` the app; the assertion disappears from `pmset -g assertions`.
- [x] **0.5 Clean up after the old version.** On launch, check `pmset -g` for `SleepDisabled 1`. If found, offer a one-time reset, which asks for the password one last time. Test: set it manually with sudo, launch, accept, and confirm it reads 0.

Known gap after Phase 0: closing the lid sleeps the Mac again, because assertions only block idle sleep. Phase 1 restores it.

## Phase 1 — Lid-closed mode

Goal: closing the lid no longer sleeps the Mac, as before Phase 0. First restore it with the password (1.1–1.2), then remove the password for good (1.3–1.6), then add a battery safety net (1.7).

- [x] **1.1 Add a `lidClosed` setting that layers pmset on top of the assertion.** When it is on, `start()` also runs `pmset -a disablesleep 1` through the old password path, and `stop()` runs `disablesleep 0`. It defaults to on, so the app works as it did before Phase 0. Test: toggle on and close the lid; a `ping` from another machine keeps answering for 2 minutes. With lidClosed off, the Mac sleeps when the lid closes.
- [x] **1.2 Reset on quit.** In `applicationWillTerminate`, run `disablesleep 0` if the app set it. Test: toggle on, then Quit; `pmset -g` shows SleepDisabled 0. A crash still leaves it set; 0.5 catches that on the next launch, and 1.6 fixes it properly.
- [x] **1.3 Add a privileged helper daemon, registered with `SMAppService.daemon`.** Its launchd plist goes in `Contents/Library/LaunchDaemons`, and the app must be signed with your Team ID. It exposes one XPC call, `setSleepDisabled(Bool)`. Test: register it and approve it in System Settings › General › Login Items; the call flips SleepDisabled with no password prompt.
- [x] **1.4 Make the helper accept only Sleepmaster.** Check the caller's code signature (Team ID + bundle ID) before acting. Test: a test client signed differently is rejected.
- [x] **1.5 Switch `lidClosed` to the helper, keeping the password path as a fallback.** When the helper's status is `.requiresApproval`, show "Approve in System Settings" and open the pane with `SMAppService.openSystemSettingsLoginItems()`. Test: with the helper approved, toggle on and off 10 times with no password prompt.
- [x] **1.6 Make the helper own the reset.** It sets `disablesleep 0` when the XPC connection drops (app quit or crash) and at boot. Test: toggle on, `kill -9` the app, and `pmset -g` shows SleepDisabled 0 within 5 seconds.
- [x] **1.7 Add a low-battery cut-off.** On battery below 10%, turn lid-closed mode off and log it. This stops a closed Mac from draining flat or overheating in a bag. Test: set the threshold just below the current level and unplug; SleepDisabled goes to 0 at the next 1% drop.

## Phase 2 — Menu bar shell

Goal: the popover from the design, holding just the big on/off button.

- [x] **2.1 Create one `AppState` object.** An `@Observable` class holds `isActive`; every view and the controller read from it. Test: a unit test flips `isActive` and checks that the controller is called.
- [x] **2.2 Add a `MenuBarExtra` with `.window` style.** Show the header, the round power button, the lid-closed toggle and the status text. Test: clicking the icon opens the popover, and the button toggles on and off.
- [x] **2.3 Add the menu bar icon states.** Show a moon when off and an amber eye when on. Test: the icon changes within 1 second of toggling.
- [x] **2.4 Add a footer with Settings… (placeholder) and Quit ⌘Q.** Test: Quit releases the assertion (re-run test 0.4 using Quit).
- [x] **2.5 Hide the Dock icon.** Set `LSUIElement` so the app lives only in the menu bar. Test: no Dock icon and no app switcher entry.

## Phase 3 — Indefinitely and Timer modes

Goal: the two modes from the design, with a countdown that can be trusted.

- [x] **3.1 Add `mode` (indefinitely / timer) to `AppState` and a segmented control.** Indefinitely behaves exactly like today's toggle. Test: switching modes while on keeps the Mac awake throughout.
- [x] **3.2 Build the timer engine on an end `Date`, not a decrementing counter.** It then survives display sleep and app hangs. When the end time passes, release the assertion and switch to off. Test: a 1-minute timer turns off on time, including when the display slept in between.
- [x] **3.3 Add duration chips: 15 min, 30 min, 1, 2, 4 and 8 hours.** Picking a chip while off also turns Sleepmaster on. Test: each chip sets the right end time, shown as "Allows sleep at HH:MM".
- [x] **3.4 Show a live countdown in the popover and menu bar.** Popover shows h:mm:ss; menu bar shows h:mm next to the icon. Test: both stay in sync and the menu bar updates at least every minute.
- [x] **3.5 Add +30 min and +1 hour buttons while a timer runs.** Test: the end time moves by exactly that amount.
- [x] **3.6 Add "Until a specific time…" with a time picker.** A time earlier than now means tomorrow. Test: choose 23:00 at 22:58; it turns off at 23:00.
- [x] **3.7 Persist the mode and last duration in `UserDefaults`.** Test: relaunch the app and the same mode and chip are selected (it starts off).

## Phase 4 — Only while plugged in

Goal: the common setting that applies to both modes.

- [x] **4.1 Add a `PowerMonitor`.** Read the power source with `IOPSCopyPowerSourcesInfo` and listen for changes with `IOPSNotificationCreateRunLoopSource`. It publishes `isOnAC` and `batteryPercent`. Test: log output changes within 2 seconds of unplugging and replugging.
- [x] **4.2 Add the "Only while plugged in" toggle to the popover.** Its subtitle shows the live power state. Test: the subtitle flips when you unplug.
- [x] **4.3 Add the paused state.** When on, the setting is enabled and the Mac is on battery, release the assertion but keep `isActive`. Re-take the assertion on AC. Test: on → unplug → no assertion in `pmset -g assertions` → replug → assertion back.
- [x] **4.4 Keep the timer running through a pause.** Test: start 30 min, unplug 10 min, replug; about 20 min remain.
- [x] **4.5 Add the paused UI.** Show "Paused on battery" in the popover and a grey eye with "Paused" in the menu bar. Test: matches the States board in the design.
- [x] **4.6 Add a battery floor (default 20%).** Below it, sleep is allowed even when the plugged-in setting is off. Test: lower the floor to 1 above the current level and confirm sleep is allowed.

## Phase 5 — Let the display sleep

Goal: keep the system awake while the screen is allowed to turn off.

- [x] **5.1 Pick the assertion type by setting.** Use `PreventUserIdleDisplaySleep` (screen stays on) by default and `PreventUserIdleSystemSleep` when the display may sleep. Test: with display sleep at 1 minute, the screen goes dark but a running download continues.
- [x] **5.2 Swap the assertion live when the toggle changes while on.** Take the new assertion before releasing the old one, so there is no gap. Test: flip it while on; `pmset -g assertions` never shows zero Sleepmaster assertions.

## Phase 6 — Settings window

Goal: the Settings board from the design, General and "When turned on" sections first.

- [x] **6.1 Add a SwiftUI `Settings` scene opened from the popover.** Test: Settings… opens the window in front, and a second click doesn't open a duplicate.
- [x] **6.2 Add Launch at login with `SMAppService.mainApp`.** Test: enable, log out and in; the app is running and starts off.
- [x] **6.3 Add Show time in menu bar.** Test: switched off, the timer shows only the eye icon.
- [x] **6.4 Add default mode, default timer and Remember last choice.** Test: with Remember off, turning on uses the defaults after a relaunch.
- [x] **6.5 Add a global toggle shortcut (default ⌥⌘S).** Use the KeyboardShortcuts package or `RegisterEventHotKey`. Test: the shortcut toggles while another app is focused.
- [x] **6.6 Mirror the popover toggles in Settings.** "Only while plugged in", the battery floor, display sleep and lid-closed mode live in both places, bound to the same state. Test: changing one updates the other immediately.

## Phase 7 — Notifications

Goal: no surprise sleep in the middle of a download or render.

- [x] **7.1 Request notification permission the first time a timer starts, not at launch.** Test: the permission prompt appears only then.
- [x] **7.2 Send a timer warning before the end (default 5 min, configurable).** Test: with a 6-minute timer, the banner arrives at about 1 minute in.
- [x] **7.3 Add actions to the warning.** Use `UNNotificationCategory` with +30 min, Keep awake (switches to Indefinitely) and Let it sleep. Test: each button does its job without opening the popover.
- [x] **7.4 Notify when paused on battery (toggle in Settings).** Test: unplug while on; one banner, and no repeat on every power blip.

## Phase 8 — Automation

Goal: Sleepmaster turns itself on when needed. Automatic activations are tracked separately, so a manual off always wins until the trigger fires again.

- [x] **8.1 Add an `activationReason` field (manual, app, power, schedule).** Show it in the status line, e.g. "Awake while Xcode runs". Test: unit test that a manual off clears automatic activations.
- [x] **8.2 Add Turn on automatically when plugged in.** This starts Indefinitely mode on AC and stops it on battery. Test: plug in and the icon turns amber; unplug and it turns off.
- [x] **8.3 Add an app list with an Add app… picker.** Store bundle IDs and watch `NSWorkspace` launch and terminate notifications. Test: add TextEdit; opening it turns Sleepmaster on, quitting it turns it off.
- [x] **8.4 Add a schedule (days + from/to time).** Re-evaluate on a timer and on wake. Test: set a window starting 2 minutes from now; it turns on and later off on time.

## Phase 9 — Polish and release

- [x] **9.1 Accessibility pass.** Every control has a VoiceOver label, the status is announced on change, and everything works by keyboard. Test: full flow with VoiceOver only.
- [x] **9.2 Light mode and Reduce Transparency.** Test: the popover reads well in both appearances.
- [x] **9.3 First-run onboarding.** One screen explains the modes and offers launch at login. Test: shows once on a clean user account.
- [x] **9.4 Sign with Developer ID, notarize and staple.** Test: `spctl -a -v Sleepmaster.app` reports accepted on a second Mac.
- [x] **9.5 Auto-updates with Sparkle.** Test: an older build finds and installs the newer one.
- [ ] **9.6 Regression checklist.** Re-run every Test line above on the release build and tick it off.
