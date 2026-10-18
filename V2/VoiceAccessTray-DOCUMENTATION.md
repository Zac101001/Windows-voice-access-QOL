# Voice Access Bar Control — Complete Project Handoff

> **Read this first.** This document is self-contained. It assumes you (a human or an AI
> agent) know **nothing** about this project. After reading it you should be able to
> understand, run, modify, debug and reinstall the whole thing.

Last updated: 2026-10-17 (project build), doc written 2026-10-18.
Author context: built interactively by an AI agent + the machine owner (`ZAC`).

---

## 1. What this project is (30-second summary)

A **Windows tray application written in PowerShell** (`VoiceAccessTray.ps1`) that manages the
built-in Windows 11 **Voice Access** feature.

Its headline feature is a **logon startup sequence** that, automatically after you sign in:

1. **wakes up** Voice Access (puts it in listening mode),
2. forces Voice Access into **"Command mode"**,
3. waits **5 seconds**,
4. **hides the Voice Access bar** so it stops reserving the top ~40 px of the screen.

The bar keeps listening in the background — it is only hidden, not closed.

The tray also has a normal menu (hide/show bar, start Voice Access, wake up, autostart, exit)
and a **checkbox ON/OFF** to enable/disable the logon sequence.

The hard/interesting part is **step 2 (Command mode)**: Windows provides *no* API, setting,
button, menu or registry value to enter it. The only trigger is the **spoken phrase
"Commands mode"**. This project solves that with **digital audio injection through the
"Stereo Mix" recording device**. See [section 6](#6-the-command-mode-problem--the-solution-the-core-of-this-project).

---

## 2. Machine / environment this was built and tested on

| Item | Value |
|------|-------|
| OS | Microsoft Windows 11 **Home**, build `10.0.26200` (24H2-era) |
| User | `desktop-voisu4v\zac` (also written `ZAC`) |
| PowerShell | Windows PowerShell 5.1 (`C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`) |
| Voice Access exe | `C:\Windows\System32\VoiceAccess.exe` |
| Real microphone | "Microphone Array (Realtek(R) Audio)" |
| Speakers/playback | Realtek Speakers |
| Video/other playback | NVIDIA HDMI "24W_LCD_TV" (this was the *default* playback device before tests) |

> The audio **GUIDs in section 10 are specific to this machine**. If you move to another PC
> they will differ — the code discovers most of them dynamically, but see the notes there.

---

## 3. Files — the complete inventory

### 3.1 The application (the only files that matter for running it)

| Path | Role |
|------|------|
| `C:\Users\ZAC\Documents\VoiceAccessTray.ps1` | **The application.** Tray icon, menu, and the whole logon sequence (wake + Command mode + hide). ~582 lines. |
| `C:\Users\ZAC\Documents\Hide-VoiceAccessBar.ps1` | Small standalone helper to hide/show/list the Voice Access window manually. Not required by the tray (the tray has its own copy of this logic), but handy for testing. |

### 3.2 Documentation & backups

| Path | Role |
|------|------|
| `C:\Users\ZAC\Documents\VoiceAccessTray-DOCUMENTATION.md` | **This file.** Full handoff. |
| `C:\Users\ZAC\Documents\VoiceAccessBackup\commands-mode-implementation.md` | Short description of the Command-mode feature. |
| `C:\Users\ZAC\Documents\VoiceAccessBackup\command-mode-experiments.md` | Table of every method that was tried to reach Command mode, and the result. |
| `C:\Users\ZAC\Documents\VoiceAccessBackup\VoiceAccessTray.2026-10-17_150944.ps1` | Backup of the tray **before** any Command-mode work. |
| `C:\Users\ZAC\Documents\VoiceAccessBackup\VoiceAccessTray.pre-commands.2026-10-17_201323.ps1` | Backup just before the Command-mode commit. |
| `C:\Users\ZAC\Documents\VoiceAccessBackup\Hide-VoiceAccessBar.2026-10-17_150944.ps1` | Backup of the helper. |

### 3.3 Operating system state (NOT files, but part of "the app")

| Thing | Where |
|-------|-------|
| Scheduled task | **`VoiceAccessTray`** — runs the tray at logon (see [section 8](#8-scheduled-task)). |
| Tray app preferences | Registry `HKCU\Software\VoiceAccessTray` → value **`AutoSetup`** (1 = logon sequence ON, 0 = OFF). |
| Voice Access microphone | Registry `HKCU\Software\Microsoft\VoiceAccess` → value **`VoiceAccessMicrophoneId`**. |
| Voice Access Windows autostart | Registry `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Accessibility` → value **`Configuration`** = `"voiceaccess"`. |
| Tray log file | `%LOCALAPPDATA%\VoiceAccessTray\tray.log` (i.e. `C:\Users\<user>\AppData\Local\VoiceAccessTray\tray.log`). |

### 3.4 Scratch/experiment files (disposable — not part of the shipping app)

`C:\Users\ZAC\AppData\Local\Temp\opencode\` contains ~90 throwaway scripts and logs used while
figuring out the Command-mode injection (`mode-attempt.ps1` is the main harness; `attempt-*.txt`
are its results). These are **not needed** to run the app. They are only useful as reference if
you want to re-derive how the injection method was found. Safe to ignore or delete.

---

## 4. How the tray application is structured (code walkthrough)

`VoiceAccessTray.ps1` runs top-to-bottom, then enters a WinForms message loop. Sections:

### 4.1 Elevation (lines 1–11)
The script declares `param([switch]$AutoHide)`. Hiding the Voice Access window requires
**Administrator** (Voice Access runs at a high integrity level / UI Access).

```powershell
if (-not <is admin>) {
    # relaunch itself elevated with -Verb RunAs, -STA, hidden window
    # passes -AutoHide through if it was given
    exit
}
```

So: **always launch it elevated** (directly as admin, or let it self-elevate via UAC).

### 4.2 Assemblies and native interop (lines 13–158)
Loads `System.Windows.Forms`, `System.Drawing`, `System.Speech` (TTS),
`UIAutomationClient`, `UIAutomationTypes` (UI Automation). Then `Add-Type`s four C# classes:

| C# class | Purpose | Key members |
|----------|---------|-------------|
| **`VEnum`** | Find the Voice Access window | `Find()` → list of `HWND`s whose process is `VoiceAccess` and whose window **title or class** contains `"Voice access"`. Also `ShowWindow`, `IsWindow`, `GetWindowText`, `GetClassName`. |
| **`ABar`** | Free the reserved top-screen strip | `SHAppBarMessage(ABM_REMOVE)`. The Voice Access bar registers as an **AppBar** and reserves screen space; merely hiding it with `ShowWindow(0)` is not enough — you must `ABM_REMOVE` it first. |
| **`WakeKeys`** | Send wake/sleep and Esc | `AltShiftB()` sends **Alt+Shift+B** (Voice Access wake/sleep toggle). `Esc()` sends Escape. |
| **`AudioPolicy`** | Control audio endpoints | Wraps undocumented COM `IMMDeviceEnumerator` + `IPolicyConfig`. `GetDefaultRender()`, `SetDefault(id)` (sets roles 0/1/2), `SetVisible(id,bool)` (`SetEndpointVisibility`), `CaptureState(guid)` → `"id|state"`. |

### 4.3 Constants (lines 160–168)
Registry paths, MMDevices paths, property-key names, and the log path (see files table).
Notable: `$PKEY_Name = "{a45c254e-df1c-4efd-8020-67d146a850e0},2"` is the audio device
**friendly name** property; `$PKEY_Desc = "{b3f8fa53-0004-438e-9003-51a46e139bfc},6"` is the
device **description** ("Realtek(R) Audio" etc.).

### 4.4 Functions
| Function | Does |
|----------|------|
| `Write-Log` | Appends a timestamped line to `tray.log`. |
| `Get-VoiceAccessState` | Reads the **visible** bar via UI Automation. Returns a hashtable: `Handle`, `Readable`, `Listening`, `Mic`, `Speech`, `Mode`. **A hidden bar cannot be read.** |
| `Invoke-HideVoiceBar` | `ABM_REMOVE` + `ShowWindow(SW_HIDE)` on every VA window, then a balloon tip. |
| `Invoke-ShowVoiceBar` | `ShowWindow(SW_SHOW)`. |
| `Invoke-StartVoiceAccess` | Starts `VoiceAccess.exe` if not running; waits up to 30 s for the bar and shows it. |
| `Get-GuidFromEndpointId` | Extracts the endpoint GUID (without braces) from a full device id string. |
| `Get-EndpointMenuName` | Looks up a capture endpoint's friendly menu label ("Name (Desc)") from the registry. |
| `Get-StereoMixCandidates` | Lists capture endpoints named **"Stereo Mix"** that are present (state low nibble 1=active or 2=disabled). Returns GUIDs without braces. |
| `Get-RealtekRenderShortId` | Finds the first **active Realtek playback** endpoint and returns its short id (this is the output Stereo Mix captures). |
| `Enable-StereoMix` | Calls `SetVisible(id,$true)` **with retries** until the endpoint reports state=1. Returns `@{Guid;Short}` or `$null`. |
| `Disable-StereoMix` | `SetVisible(id,$false)`. |
| `Select-VoiceMic` | **Switches Voice Access's microphone LIVE** (no restart) through the Voice Access Settings → "Select default microphone" menu using UI Automation. |
| `Invoke-CommandModeInjection` | Sets default playback to the Realtek speakers, speaks **"Commands mode"** via `System.Speech`, retries up to 4× until the bar shows `Command mode`, then restores the original default playback. |
| `Invoke-WakeVoiceAccess` | Ensures VA is **listening**. Shows the bar if needed, waits out a `"Loading"` state, and only then sends **Alt+Shift+B** if confirmed asleep. Returns `$true`/`$false`. |
| `Invoke-AutoSetup` | **The logon sequence** (see section 5). |
| `Get-WindowsAutoStart` / `Set-WindowsAutoStart` | Read/write the Windows VA autostart registry value. |
| `Get-AutoSetup` / `Set-AutoSetup` | Read/write the tray's `AutoSetup` ON/OFF preference (default ON). |

### 4.5 Tray icon and menu (lines 506–567)
`NotifyIcon` using the Voice Access icon (extracted from `VoiceAccess.exe`, with a fallback
system icon). Context menu items, in order:

- **Hide Voice Access bar**
- **Show Voice Access bar**
- **Start Voice Access**
- **Wake up (start listening)**
- **Run startup sequence now (wake up, Command mode, hide)**
- *(separator)*
- **Startup sequence at logon (wake up, Command mode, hide)** — **checkbox**, this is the ON/OFF button.
- **Start automatically with Windows** — checkbox (controls the Windows VA autostart value).
- *(separator)*
- **Exit**

Double-clicking the tray icon hides the bar.

### 4.6 Logon trigger (lines 569–580)
If the script was started with `-AutoHide` **and** the `AutoSetup` preference is ON, a
**4-second timer** waits for the desktop to settle and then calls `Invoke-AutoSetup` **once**.

`[System.Windows.Forms.Application]::Run()` keeps the process alive to service the tray.

---

## 5. The logon startup sequence, step by step (`Invoke-AutoSetup`)

Exactly what happens (this is the log's order too):

1. **Kill Voice Access.** `Stop-Process VoiceAccess`. This is required because Voice Access
   **latches its microphone at startup** — you cannot switch it to Stereo Mix by only changing
   the registry after it is already running. It must start *while* the registry points at Stereo Mix.
2. **Enable Stereo Mix** and **point VA's microphone at it.** Save the original microphone
   value first (`origMic`). Write `VoiceAccessMicrophoneId` = the real mic's path with the
   capture GUID replaced by the Stereo Mix GUID.
3. **Start Voice Access** (visible) and show its bar.
4. **Wake it up** → listening (`Invoke-WakeVoiceAccess`).
5. **Command mode** (`Invoke-CommandModeInjection`, only if Stereo Mix is available):
   a. Set the **default playback** device to the active **Realtek Speakers** (Stereo Mix captures
      only Realtek output).
   b. `SpeechSynthesizer.Speak("Commands mode")` — up to 4 attempts, 3 s apart.
   c. After each, read the bar; success = the mode text reads `Command mode`.
   d. Restore the original default playback.
6. **Switch the microphone back to the real one LIVE** (`Select-VoiceMic`) via the Settings menu.
   No restart ⇒ **Command mode is preserved** while the real mic is restored.
   Also restore the `VoiceAccessMicrophoneId` registry value and **disable Stereo Mix**.
7. **Notify** via balloon tip (Command mode active / default mode / warnings).
8. **Wait 5 seconds.**
9. **Hide the bar** (`ABM_REMOVE` + `SW_HIDE`).

Errors are caught, logged, and surfaced as a balloon tip.

---

## 6. The "Command mode" problem & the solution (the core of this project)

### 6.1 Why it is hard
- "Command mode" is a Voice Access **listening mode** (vs. the default dictation/typing mode).
- There is **no** programmatic API, no registry value, no button, no hotkey, no menu item and no
  context menu to enter it **on this build**. (All were tried — see `command-mode-experiments.md`.)
- The **only** trigger is **speaking the phrase "Commands mode"** while VA listens.
- The mode **does not survive a Voice Access restart** — every restart returns to the default mode.

### 6.2 Why you cannot just play TTS through the speakers into the real mic
The real microphone is a **Realtek mic array with echo cancellation / noise suppression**. When
TTS plays out of the speakers:
- sometimes the mic barely hears it,
- sometimes it mis-recognizes it (e.g. heard "Communication mode"),
- and the echo cancellation often **removes the speaker audio entirely**.

So the acoustic path is unreliable. (Documented as method #3/#4 in the experiments table.)

### 6.3 The working solution: digital injection via Stereo Mix + live mic switch-back
1. **Stereo Mix** is a virtual *recording* device that captures whatever plays on the **Realtek
   output** — digitally, with no room/acoustic step. So TTS is "heard" perfectly.
2. Temporarily: enable Stereo Mix, make VA start with the **Stereo Mix** microphone, set default
   playback = Realtek speakers, say "Commands mode".
3. Once Command mode is active, **switch VA's microphone back to the real one through its own
   Settings menu** — this happens **live, without restart**, so **Command mode is kept** and VA
   once again hears the real user.
4. Turn Stereo Mix back off and restore the default playback device.

This "hybrid" (inject digitally → switch mic back live) is the key insight that makes the feature
practical. It was verified end-to-end repeatedly.

### 6.4 Side effects / costs
- The phrase **"Commands mode" is briefly audible on the speakers** at logon. That sound *is*
  the mechanism; it cannot be removed without changing how the trick works.
- Enabling Stereo Mix takes a few seconds (the `SetEndpointVisibility` call is **flaky** —
  it intermittently returns `ERROR_NOT_FOUND` `0x80070490`; the retry loop in `Enable-StereoMix`
  handles it).
- If Stereo Mix is unavailable on some machine, the sequence still runs (wake + hide) but
  **skips Command mode** and tells the user.

---

## 7. Registry keys — full reference

| Key | Value | Meaning |
|-----|-------|---------|
| `HKCU\Software\VoiceAccessTray` | `AutoSetup` (DWORD/String; 1/0) | Tray checkbox "Startup sequence at logon". **Default 1 (ON)**. |
| `HKCU\Software\Microsoft\VoiceAccess` | `VoiceAccessMicrophoneId` (String) | The full microphone **device-interface path** Voice Access uses. Temporarily points at Stereo Mix during the sequence. |
| `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Accessibility` | `Configuration` (String) | `"voiceaccess"` = Windows starts Voice Access at logon. Controlled by the tray's "Start automatically with Windows" checkbox. |

Device-interface path format (example, real mic):
```
\\?\SWD#MMDEVAPI#{0.0.1.00000000}.{ee01d51c-5dd7-4d49-adb5-d31b7acf785d}#{2eef81be-33fa-4800-9670-1cd474972c3f}
```
`{0.0.1.00000000}.` prefix = **capture** endpoint; `.{GUID}` = the endpoint GUID; the trailing
`#{2eef81be-...}` is the interface GUID.

> Note the subtlety that caused an early bug: **the MMDevices registry key names include the
> braces** (`{GUID}`), but the **device id strings passed to the audio APIs must NOT have an extra
> level of braces**. The code normalizes GUIDs accordingly (strip braces, then re-add exactly one
> pair when building ids).

---

## 8. Scheduled task

| Field | Value |
|-------|-------|
| Name | `VoiceAccessTray` |
| State | Running |
| Run as | `ZAC`, **RunLevel = Highest** (elevated) |
| Trigger | **At logon** (enabled) |
| Action | `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -NoExit -WindowStyle Hidden -File "C:\Users\ZAC\Documents\VoiceAccessTray.ps1" -AutoHide` |

Because the task points at the script **file path**, editing the script and restarting the task
(or logging off/on) is enough to deploy a new version — **no reinstall needed**.

`-NoExit` keeps the PowerShell host alive; `-AutoHide` tells the script to run the logon sequence.

---

## 9. How to operate, test and debug

### 9.1 Normal use
Right-click the tray icon. The two checkboxes control:
- **Startup sequence at logon** (ON/OFF) — persisted.
- **Start automatically with Windows** — Windows VA autostart.

### 9.2 Run the sequence immediately (for testing)
Use the tray menu item **"Run startup sequence now ..."**, or launch:
```powershell
# elevated
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "C:\Users\ZAC\Documents\VoiceAccessTray.ps1" -AutoHide
```
> Launching elevated **from another script** with `Start-Process -Verb RunAs -Wait` can **hang**
> when the elevated child spawns the long-lived tray. Start it **without `-Wait`** and poll the
> log file instead.

### 9.3 Read the log
```powershell
Get-Content "$env:LOCALAPPDATA\VoiceAccessTray\tray.log"
```
A healthy run looks like:
```
[2026-10-17 20:29:18] AutoSetup: begin
[2026-10-17 20:29:18] AutoSetup: origMic=\\?\SWD#MMDEVAPI#{0.0.1.00000000}.{ee01d51c-...}...
[2026-10-17 20:29:21] AutoSetup: stereo=2c2c37af-5eb6-41c7-b26d-da6c30527a2e
[2026-10-17 20:29:21] AutoSetup: mic set to \\?\SWD#MMDEVAPI#{0.0.1.00000000}.{2c2c37af-...}...
[2026-10-17 20:29:30] AutoSetup: awake=True
[2026-10-17 20:29:37] AutoSetup: modeOk=True
[2026-10-17 20:29:37] AutoSetup: switch back to 'Microphone Array (Realtek(R) Audio)'
[2026-10-17 20:29:43] AutoSetup: switched=True
[2026-10-17 20:29:48] AutoSetup: hiding bar
[2026-10-17 20:29:48] AutoSetup: done
```
Key success markers: `stereo=` non-empty, `modeOk=True`, `switched=True`.

### 9.4 Restart the tray after editing the script
```powershell
# elevated: kill tray instances, clear log, start fresh
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*VoiceAccessTray.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Remove-Item "$env:LOCALAPPDATA\VoiceAccessTray\tray.log" -ErrorAction SilentlyContinue
Start-Process powershell -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-STA","-WindowStyle","Hidden","-File","C:\Users\ZAC\Documents\VoiceAccessTray.ps1","-AutoHide")
```

### 9.5 Check syntax after editing
```powershell
$t=$null;$e=$null
[System.Management.Automation.Language.Parser]::ParseFile("C:\Users\ZAC\Documents\VoiceAccessTray.ps1",[ref]$t,[ref]$e) | Out-Null
if ($e.Count -eq 0) { "Syntax OK" } else { $e | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" } }
```

### 9.6 Manual hide/show helper
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\ZAC\Documents\Hide-VoiceAccessBar.ps1"        # hide
powershell -ExecutionPolicy Bypass -File "C:\Users\ZAC\Documents\Hide-VoiceAccessBar.ps1" -Show  # show
powershell -ExecutionPolicy Bypass -File "C:\Users\ZAC\Documents\Hide-VoiceAccessBar.ps1" -List  # list windows only
```
It self-elevates.

---

## 10. Audio device reference (this machine)

| Device | GUID | Endpoint id (short) | Notes |
|--------|------|---------------------|-------|
| Real microphone ("Microphone Array (Realtek(R) Audio)") | `ee01d51c-5dd7-4d49-adb5-d31b7acf785d` | `{0.0.1.00000000}.{ee01d51c-...}` | capture; the normal mic |
| **Stereo Mix** (working one) | `2c2c37af-5eb6-41c7-b26d-da6c30527a2e` | `{0.0.1.00000000}.{2c2c37af-...}` | capture; enabled temporarily during the sequence |
| Stereo Mix (second, unusable) | `ccb4b94f-04a8-4fec-8295-e48d1cd47d5e` | — | filtered out (device not present) |
| Realtek Speakers | `bbe79e36-78db-465e-87d9-dbb3e72b7084` | `{0.0.0.00000000}.{bbe79e36-...}` | render; the output Stereo Mix captures |
| NVIDIA HDMI (original default) | `581a4708-...` | `{0.0.0.00000000}.{581a4708-...}` | render; restored after injection |
| Shared interface GUID | `2eef81be-33fa-4800-9670-1cd474972c3f` | — | suffix of the full device path |

- Capture short id prefix: `{0.0.1.00000000}.`  •  Render short id prefix: `{0.0.0.00000000}.`
- `DeviceState` low nibble: `1` = active, `2` = disabled, `4` = not present.
- **The code discovers Stereo Mix, the Realtek render, and the original default render
  dynamically**, so on a different PC it should mostly adapt — but the *menu label matching*
  (`"Microphone Array"` fallback in `Select-VoiceMic`) is Realtek-specific and may need editing.

---

## 11. UI Automation reference (how Voice Access is read/driven)

The bar is read with `AutomationElement.FromHandle(<VA HWND>)` and `FindFirst/FindAll`.

| AutomationId | Meaning |
|--------------|---------|
| `MicrophoneButtonControl` | Mic state; Name = `Microphone active` / `Microphone sleep`. |
| `SpeechTextBlock` | Status text, e.g. `Listening...`, `Loading...`. |
| `RecognitionModeTextBlock` | **Present only when a non-default mode is active.** Name includes `Command mode`. This is the success signal. |
| `SettingsButton` | Opens the Settings menu. |
| `MicrophoneList` | The "Select default microphone" submenu (Toggle pattern items). |

Settings menu children are `MenuItem`s; candidates seen on this PC:
"Microphone Array (Realtek(R) Audio)", "Microphone (Virtual Desktop Audio)",
"Microphone (2- Mic Device)", "Microphone (2- G435 Wireless Gaming Headset)".

**Critical rule:** a **hidden bar cannot be read** — always `ShowWindow(SW_SHOW)` before reading
state, and hide again afterwards.

---

## 12. Known issues, gotchas and limitations

1. **Command mode is not persistent.** It resets on every VA restart — hence the sequence runs at
   every logon.
2. **The TTS phrase is audible** on the speakers at logon (by design).
3. **`SetEndpointVisibility` is flaky** (`ERROR_NOT_FOUND`); handled by retries.
4. **Registry `DeviceState` writes are blocked by ACL** (`HKLM\...\MMDevices\...`). The code uses
   the `IPolicyConfig` COM API instead of editing the registry.
5. **Elevation required.** Hiding the bar and killing VA need Administrator (Voice Access runs
   with UI Access/high integrity).
6. **Hidden bar = unreadable.** See section 11.
7. **`return` inside `ForEach-Object` does not exit the enclosing function.** This caused a real
   bug (the render-id helper returned an array). Fixed by using a `foreach` statement. Watch for
   this pattern when editing.
8. **Brace handling for GUIDs** (section 7) — an easy source of "device not found" bugs.
9. **Multiple tray instances** can pile up if you start it several times; kill them by matching
   `CommandLine -like '*VoiceAccessTray.ps1*'`.
10. A scheduled-task `LastTaskResult` of `4294967295` (`0xFFFFFFFF`) simply means **the task is
    currently running** (the tray is long-lived), not an error.
11. `DoubleClick` must be wired with `add_DoubleClick({...})`, not `+=` (the `NotifyIcon` doesn't
    expose the event that way in PS 5.1).

---

## 13. Backups & rollback

Previous versions are in `C:\Users\ZAC\Documents\VoiceAccessBackup\` (see section 3.2). To roll
back, copy the desired `.ps1` over `C:\Users\ZAC\Documents\VoiceAccessTray.ps1` and restart the
tray. The pre-Command-mode backup (`VoiceAccessTray.2026-10-17_150944.ps1`) is the cleanest
"known good before this feature" state.

To fully remove the project:
1. Stop the tray, `Unregister-ScheduledTask -TaskName VoiceAccessTray`.
2. Delete the two `.ps1` files and (optionally) the backup folder and the log folder.
3. Optionally remove `HKCU\Software\VoiceAccessTray` and reset
   `HKCU\Software\Microsoft\VoiceAccess\VoiceAccessMicrophoneId` to your real mic.

---

## 14. History / how the solution was found

`command-mode-experiments.md` has the full table. Summary of the nine approaches tried:

| Method | Result |
|--------|--------|
| baseline (fresh start) | default mode (confirms mode doesn't persist) |
| TTS → default output (HDMI TV) | mic didn't hear it |
| TTS → speakers | mic mis-recognized ("Communication mode") |
| TTS → speakers (tuned voice) | echo cancellation removed it |
| **TTS → Stereo Mix (digital)** | **SUCCESS (reproduced)** |
| open Settings menu via UIA | no mode option exists |
| click mode text | mode element absent in default mode |
| right-click bar | no context menu |
| hotkeys (ctrl/alt + shift/m …) | no effect |

Conclusion: **digital injection through Stereo Mix is the only reliable programmatic trigger**;
combined with the **live microphone switch-back**, it yields a practical logon automation.

---

## 15. Glossary

- **Voice Access (VA)** — Windows 11 accessibility feature for hands-free control; shows a top bar.
- **Command mode** — VA listening mode where spoken commands are interpreted as commands rather
  than dictation. Non-persistent; entered only by saying "Commands mode".
- **Stereo Mix** — virtual recording device capturing the system's Realtek playback digitally.
- **AppBar** — a window that reserves screen edge space (like the taskbar); the VA bar is one, so
  hiding it requires `ABM_REMOVE`.
- **UI Automation (UIA)** — Windows accessibility API used here both to read VA state and to click
  its Settings menu.
- **IPolicyConfig** — undocumented COM interface used to set the default audio endpoint and to
  show/hide (enable/disable) audio endpoints.
- **TTS** — text-to-speech (`System.Speech.Synthesis.SpeechSynthesizer`), used to speak
  "Commands mode".

---

## 16. Quick "what do I do next" for a new agent

- **Understand:** read sections 5 and 6 — they are the whole point.
- **Run it:** tray menu → "Run startup sequence now". Watch `%LOCALAPPDATA%\VoiceAccessTray\tray.log`.
- **Edit it:** modify `C:\Users\ZAC\Documents\VoiceAccessTray.ps1`, syntax-check (9.5), restart the
  tray (9.4). The scheduled task already points at the file, so logon uses the new code.
- **Debug a failed run:** check the log markers (`stereo=`, `awake=`, `modeOk=`, `switched=`),
  confirm Stereo Mix enabled, confirm the mic reg value has exactly one pair of braces, and
  confirm the bar was visible when state was read.
