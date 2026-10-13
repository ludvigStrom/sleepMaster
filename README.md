# SleepMaster

macOS menu-bar extra that toggles `pmset -a disablesleep`.

Click the moon icon → **Do not go to sleep**. macOS asks for your password. The setting survives quit and reboot.

After a `/Applications` install it starts at login.

```bash
# Debug
open SleepMaster.xcodeproj

# Signed, notarized .pkg
cp Scripts/release.env.example Scripts/release.env   # set TEAM_ID + NOTARY_PROFILE
bash Scripts/release_pkg_notarize.sh 1.0.0
```
