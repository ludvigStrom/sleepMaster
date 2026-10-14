# SleepMaster

macOS menu-bar extra that keeps the Mac awake.

Click the moon icon → **Do not go to sleep**. Idle sleep is blocked with an IOKit power assertion (no password). **Stay awake with the lid closed** also sets `pmset disablesleep`. That path asks for a password until you approve the Sleepmaster helper in System Settings › General › Login Items. After approval, toggling no longer asks.

Sleep is allowed again when you turn the toggle off, when you quit, or when the helper notices the app crashed. On battery below 10% the lid-closed setting is turned off so a closed Mac does not drain flat.

If an older version left `SleepDisabled` on, the app offers a one-time reset.

After a `/Applications` install it starts at login.

```bash
# Debug
open SleepMaster.xcodeproj

# Signed, notarized .pkg
cp Scripts/release.env.example Scripts/release.env   # set TEAM_ID + NOTARY_PROFILE
bash Scripts/release_pkg_notarize.sh 1.0.0
```
