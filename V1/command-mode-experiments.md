# Voice Access – "Commands mode" experiments

Date: 2026-10-17
Backup: `C:\Users\ZAC\Documents\VoiceAccessBackup\VoiceAccessTray.2026-10-17_150944.ps1` + `Hide-VoiceAccessBar.2026-10-17_150944.ps1`

Each attempt used the full sequence:
kill Voice Access -> start visible -> mic on (listening) -> attempt -> hide bar -> confirm `WA-Top=0`.

## Results

| # | Method | What it did | Result |
|---|--------|-------------|--------|
| 1 | baseline | fresh start, no action | Mode = default (Command mode does NOT persist across restart) |
| 2 | tts | TTS "Commands mode" to default output (TV/HDMI) | Failed – mic did not hear |
| 3 | tts-speakers | default output -> Realtek Speakers, TTS | Mic heard it but mis-recognized ("Communication mode.") |
| 4 | tts-speakers2 | tuned voice/volume/slow rate on speakers | Failed – mic auto echo-cancel removed the TTS, heard room instead |
| 5 | **tts-stereo** | enable **Stereo Mix**, set Voice Access mic = Stereo Mix, default output -> Realtek Speakers, TTS | **SUCCESS** – `Speech='Commands mode.'` -> `Mode='Command mode'` (reproduced twice) |
| 6 | uia-menu | open Settings menu, dump all items | No mode option (only mic/languages/pause/vocabulary/punctuation/profanity/startup/turn off) |
| 7 | uia-clickmode | click the mode text | Not possible – mode element absent in default mode |
| 8 | uia-rightclick | right-click the bar | No context menu |
| 9 | hotkeys | ctrl+shift+m / alt+shift+m / ctrl+alt+m / alt+m / ctrl+m | No effect |

## Conclusion

- The ONLY working way to make Voice Access enter "Commands mode" programmatically is **digital audio injection through Stereo Mix**:
  1. enable Stereo Mix (`IPolicyConfig::SetEndpointVisibility`),
  2. set `HKCU\Software\Microsoft\VoiceAccess\VoiceAccessMicrophoneId` = Stereo Mix,
  3. set default output = Realtek Speakers,
  4. restart Voice Access,
  5. TTS "Commands mode".
- Limitation: while Voice Access listens to Stereo Mix it **cannot hear the real microphone**. Because the mode resets on restart, you cannot simply switch the mic back afterwards (switching requires a restart, which drops the mode).
- Acoustic path (TTS out of speakers -> real mic) is unreliable: the Realtek mic array's echo cancellation removes the speaker audio.

## Practical status
Voice Access restored to normal (real mic = Microphone Array, Stereo Mix disabled again), running and hidden.
