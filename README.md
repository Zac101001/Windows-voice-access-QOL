# Voice Access Bar Control

![Platform](https://img.shields.io/badge/platform-Windows%2011-blue)
![Language](https://img.shields.io/badge/language-PowerShell-5391FE)
![License](https://img.shields.io/badge/license-MIT-green)

A tiny Windows tray application that makes **Windows 11 Voice Access** pleasant to use:
at every sign-in it **wakes Voice Access**, forces it into **Command mode**, and then **hides the
bar** so it stops reserving the top ~40 px of the screen. The bar keeps listening in the
background — it is only hidden, never closed.

The interesting part is Command mode: Windows exposes **no** API, registry value, hotkey or menu to
enter it. The only trigger is the spoken phrase *"Commands mode"*. This project solves that with
**digital audio injection through the "Stereo Mix" recording device** and a **live microphone
switch-back** (see [How it works](#how-it-works)).

---

## Features

- **One-click startup sequence at logon** — wake up → Command mode → hide the bar.
- **Tray menu** with every manual action: hide/show the bar, start Voice Access, wake up, run the
  sequence now.
- **Two checkboxes**: *Startup sequence at logon* (ON/OFF, persisted) and *Start automatically with
  Windows* (controls the Windows Voice Access autostart).
- **Reliable, defensive design**:
  - fail-safe cleanup that always restores your microphone and playback device,
  - single-instance guard (no duplicate trays),
  - locale-independent state detection (works on non-English Windows),
  - generic audio-endpoint discovery (no hardcoded device brand),
  - responsive UI during the (long) startup sequence,
  - rotating log file with clear success markers.
- **Proper Windows packaging**: a standalone setup `.exe` (Install / Uninstall) and a separate
  uninstaller, a Start-Menu group, and an entry in **Settings → Apps**.

---

## Requirements

| Item | Value |
|------|-------|
| OS | Windows 11 (Voice Access is a Windows 11 feature) |
| Runtime | Windows PowerShell 5.1 (built in) and .NET Framework 4.x (built in) |
| Privileges | Administrator (hiding the bar and killing Voice Access require elevation) |
| Audio | A **Stereo Mix / "What U Hear"** capture device (present on most Realtek/onboard audio) |

> Command mode injection needs Stereo Mix. If it is unavailable, the sequence still runs
> (wake + hide) and simply skips Command mode, telling you so.

---

## Install

1. Download **`VoiceAccessTraySetup.exe`** (from the latest Release or the built `Installer/dist/`).
2. Double-click it, accept the UAC prompt, then click **Install**.

That's it. The installer copies the app to `C:\Program Files\VoiceAccessTray`, registers the
`VoiceAccessTray` logon task (elevated, no time limit), creates Start-Menu shortcuts, adds an entry
in **Settings → Apps**, and starts the tray immediately.

Silent install:

```powershell
VoiceAccessTraySetup.exe -silent
```

---

## Usage

Right-click the tray icon:

| Menu item | Action |
|-----------|--------|
| Hide Voice Access bar | Frees the top ~40 px (bar keeps listening). |
| Show Voice Access bar | Brings the bar back. |
| Start Voice Access | Launches Voice Access if not running. |
| Wake up (start listening) | Puts Voice Access into listening mode. |
| Run startup sequence now | Runs wake up → Command mode → hide immediately (for testing). |
| **Startup sequence at logon** | Checkbox — enables/disables the automatic sequence (ON by default). |
| **Start automatically with Windows** | Checkbox — controls Windows Voice Access autostart. |
| Uninstall Voice Access Bar Control… | Launches the uninstaller (shown when installed via the setup). |
| Exit | Quits the tray. |

Double-clicking the tray icon hides the bar.

---

## Uninstall

Any of these:

- the **Uninstall** button in the setup window,
- `C:\Program Files\VoiceAccessTray\VoiceAccessTrayUninstall.exe` (`-quiet` for silent),
- **Settings → Apps → Voice Access Bar Control → Uninstall**,
- Start Menu → **Uninstall Voice Access Bar Control**,
- tray menu → **Uninstall Voice Access Bar Control…**.

It removes the task, the installed files, the shortcuts, the Apps entry, the preferences and the
log folder.

---

## How it works

### The problem

- The Voice Access bar registers as an **AppBar** and reserves screen space, so hiding it needs
  `SHAppBarMessage(ABM_REMOVE)` **and** `ShowWindow(SW_HIDE)`.
- "Command mode" (spoken commands instead of dictation) has **no programmatic trigger** — it is
  entered only by saying *"Commands mode"*, and it **resets on every Voice Access restart**.
- The real microphone (a Realtek array with echo cancellation) **cannot reliably hear** TTS played
  through the speakers.

### The solution

1. Restart Voice Access so it can start with the **Stereo Mix** microphone (it latches its mic at
   startup).
2. Enable Stereo Mix (`IPolicyConfig::SetEndpointVisibility`, with retries — it is flaky) and point
   `HKCU\Software\Microsoft\VoiceAccess\VoiceAccessMicrophoneId` at it.
3. Set the default playback device to the speakers Stereo Mix captures, then speak
   *"Commands mode"* via `System.Speech`. Stereo Mix captures it **digitally**, so Voice Access
   hears it perfectly.
4. Once Command mode is active, **switch the microphone back to the real one LIVE** through the
   Voice Access Settings menu (no restart, so Command mode is kept).
5. Restore the playback device, disable Stereo Mix, wait ~5 s, and hide the bar.

A `finally` block guarantees the microphone registry, the playback device and Stereo Mix are
restored even if something fails, and if the live switch-back ever fails the app restarts Voice
Access on the real microphone so it is never left "deaf".

> **Side effect:** the phrase *"Commands mode"* is briefly audible on the speakers at sign-in. That
> sound *is* the mechanism and cannot be removed without changing the trick.

---

## Repository layout

```
.
├─ V2/                                  # current version
│  ├─ VoiceAccessTray.ps1               # the application
│  └─ VoiceAccessTray-DOCUMENTATION.md  # full technical handoff
├─ V1/                                  # earlier version + design notes & experiments
│  ├─ VoiceAccessTray.ps1
│  ├─ Hide-VoiceAccessBar.ps1           # small manual hide/show helper
│  ├─ commands-mode-implementation.md
│  ├─ command-mode-experiments.md       # every method tried to reach Command mode
│  └─ documentatie.txt
├─ Installer/
│  ├─ build.ps1                         # builds the .exe files
│  ├─ src/Setup.cs                      # installer source (GUI + install logic)
│  ├─ src/Uninstall.cs                  # uninstaller source
│  ├─ payload/                          # generated: copy of the app script
│  └─ dist/                             # generated: VoiceAccessTraySetup.exe, VoiceAccessTrayUninstall.exe
├─ README.md
├─ LICENSE
└─ .gitignore
```

The entry points you are most likely to touch are `V2/VoiceAccessTray.ps1` and
`Installer/build.ps1`.

---

## Run from source (without installing)

Elevated PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "V2\VoiceAccessTray.ps1" -AutoHide
```

Check the log:

```powershell
Get-Content "$env:LOCALAPPDATA\VoiceAccessTray\tray.log"
```

A healthy run looks like:

```
AutoSetup: stereo=2c2c37af-…
AutoSetup: mic set to …2c2c37af…
AutoSetup: awake=True
AutoSetup: modeOk=True
AutoSetup: switch back to 'Microphone Array (Realtek(R) Audio)'
AutoSetup: switched=True
AutoSetup: hiding bar
AutoSetup: done
AutoSetup: restored microphone registry
AutoSetup: restored default playback
AutoSetup: disabled Stereo Mix
```

Key success markers: `stereo=` non-empty, `modeOk=True`, `switched=True`.

---

## Build the installer

```powershell
powershell -ExecutionPolicy Bypass -File Installer\build.ps1
```

Uses the C# compiler that ships with Windows
(`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`). Output goes to `Installer\dist\`:
`VoiceAccessTraySetup.exe` (embeds the app script and the uninstaller) and
`VoiceAccessTrayUninstall.exe`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Bar not hidden | Run the tray **as Administrator** (the task already does). |
| `modeOk=False` | Stereo Mix missing/disabled, or the machine has no Realtek-style capture. The log tells you. |
| `switched=False` | The microphone menu could not be driven; the app restarts Voice Access on the real mic and shows a balloon. |
| Voice Access not found by the tray | Make sure Voice Access is installed/enabled in Windows. |
| Duplicate trays | Not possible anymore — a single-instance guard exits extra copies. |

---

## License

[MIT](LICENSE) — free and open source (OSI-approved). You may use, modify and distribute this
software, including commercially, as long as the copyright and permission notice are kept.

## Disclaimer

This software relies on **undocumented Windows COM interfaces** (`IPolicyConfig`) and on UI
Automation of the Voice Access bar. It changes audio device visibility and the default playback
device **temporarily** during the startup sequence. Use at your own risk; test on your machine
first. Not affiliated with Microsoft.
