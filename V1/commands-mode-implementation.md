# Voice Access - startup sequence with Command mode

Implemented 2026-10-17 in `C:\Users\ZAC\Documents\VoiceAccessTray.ps1`.

## Tray toggle (ON/OFF)
Tray icon -> right-click -> **"Startup sequence at logon (wake up, Command mode, hide)"**
(checkbox, ON by default). State is stored in `HKCU\Software\VoiceAccessTray` -> `AutoSetup` (1/0).

Another menu item, **"Run startup sequence now (wake up, Command mode, hide)"**, runs it immediately.

## What the sequence does (in order)
1. Restart Voice Access so it can start with the **Stereo Mix** microphone.
2. Enable **Stereo Mix** (`IPolicyConfig::SetEndpointVisibility`, with retries - it can fail transiently).
3. Point Voice Access microphone at Stereo Mix (`HKCU\Software\Microsoft\VoiceAccess\VoiceAccessMicrophoneId`).
4. Start Voice Access (visible) and **wake it up** (listening).
5. **Command mode**: temporarily set the default playback device to the Realtek speakers, speak
   "Commands mode" via TTS (System.Speech) so Stereo Mix feeds it to Voice Access, and wait until
   the bar shows `Command mode`. (Repeated up to 4 times.)
6. **Switch the microphone back to the real one, LIVE** via the Voice Access settings menu
   (`Settings > Select default microphone`) - no restart, so **Command mode is kept** and
   Voice Access hears the real microphone again.
7. Restore the default playback device and disable Stereo Mix.
8. Wait **5 seconds**.
9. **Hide the bar** (AppBar `ABM_REMOVE` + `ShowWindow(0)`), so the top 40 px are freed.

## Why it works this way
- Windows exposes no setting/button/menu/registry value for "Commands mode" - the only trigger is
  the spoken phrase "Commands mode".
- The real microphone (Realtek array) cannot reliably hear TTS through the speakers (echo
  cancellation), so a **digital** path is used: Stereo Mix captures what plays on the Realtek output.
- Switching the microphone back live (via the UI menu) keeps Command mode and restores normal
  microphone use - this is the key that makes the feature practical.

## Files
- `C:\Users\ZAC\Documents\VoiceAccessTray.ps1` - tray app (English UI).
- `C:\Users\ZAC\Documents\Hide-VoiceAccessBar.ps1` - hide/show helper (manual use).
- Log: `%LOCALAPPDATA%\VoiceAccessTray\tray.log` (sequence steps and errors).
- Scheduled task `VoiceAccessTray` runs the tray with `-AutoHide` at sign-in (RunLevel Highest).
- Backups: `C:\Users\ZAC\Documents\VoiceAccessBackup\`.

## Notes / limitations
- Changing the microphone requires the Stereo Mix trick; if Stereo Mix is unavailable the sequence
  still runs but skips Command mode and notifies you.
- The TTS phrase is briefly audible on the speakers at startup (it is what makes the mode change).
- Command mode does not survive a Voice Access restart, which is why the sequence re-applies it at
  every logon.
