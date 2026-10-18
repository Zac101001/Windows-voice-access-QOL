# Voice Access Bar Control — Installer

Installer standalone pentru aplicație. Nu are nevoie de nimic instalat (nu cere PowerShell
separat pentru instalare — .exe-urile sunt compilate C#/.NET Framework, prezent pe orice Windows 10/11).

## Fișiere rezultate (în `dist\`)

| Fișier | Rol |
|--------|-----|
| `VoiceAccessTraySetup.exe` | **Installer** cu interfață: butoane **Install** / **Uninstall** / **Close**. Conține încorporat scriptul aplicației și uninstaller-ul, deci e complet independent. |
| `VoiceAccessTrayUninstall.exe` | **Fișier de uninstall** separat. Șterge task-ul, fișierele, shortcut-urile, intrarea din „Apps & features", preferințele și log-ul. |

## Ce face instalarea

1. Copiază aplicația în `C:\Program Files\VoiceAccessTray\`.
2. Înregistrează task-ul programat **VoiceAccessTray** (la logon, RunLevel Highest, timp nelimitat).
3. Creează shortcut-uri în Start Menu: aplicația + **Uninstall Voice Access Bar Control**.
4. Adaugă intrarea în **Setări → Apps → Voice Access Bar Control** (cu buton de Uninstall).
5. Oprește instanța veche (dacă rulează) și pornește tray-ul imediat.

## Cum se folosește

- Instalare: dublu-clic pe `VoiceAccessTraySetup.exe` → **Install** (cere Administrator; se auto-elevă).
- Instalare silențioasă: `VoiceAccessTraySetup.exe -silent`
- Dezinstalare, oricare metodă:
  - butonul **Uninstall** din fereastra installer-ului, sau
  - `VoiceAccessTrayUninstall.exe` (`-quiet` pentru mod silențios), sau
  - **Setări → Apps → Voice Access Bar Control → Uninstall**, sau
  - Start Menu → **Uninstall Voice Access Bar Control**, sau
  - meniul tray → **Uninstall Voice Access Bar Control...**

## Rebuild

```
powershell -ExecutionPolicy Bypass -File build.ps1
```

`build.ps1`:
1. copiază `..\V2\VoiceAccessTray.ps1` în `payload\`;
2. compilează `VoiceAccessTrayUninstall.exe` din `src\Uninstall.cs`;
3. compilează `VoiceAccessTraySetup.exe` din `src\Setup.cs`, încorporând ca resurse scriptul
   și uninstaller-ul.

Compilator folosit: `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (inclus în Windows).

## Structură

```
Installer\
  build.ps1              # scriptul de build
  src\Setup.cs           # sursa installer-ului (GUI + logica de instalare)
  src\Uninstall.cs       # sursa uninstaller-ului
  payload\               # copia scriptului aplicației (generată la build)
  dist\                  # .exe-urile rezultate
```

## Note

- Nu atinge microfonul real sau setările Voice Access la instalare/dezinstalare; doar
  aplicația, task-ul și shortcut-urile.
- La dezinstalare, setarea `HKCU\Software\VoiceAccessTray` și folderul de log
  `%LOCALAPPDATA%\VoiceAccessTray` sunt șterse; `VoiceAccessMicrophoneId` rămâne pe microfonul real.
