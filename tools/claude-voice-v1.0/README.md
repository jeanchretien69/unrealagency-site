# Claude Voice v1.0 (approved by Gael on 2026-11-18) — working 100%

Talk to Claude from any app on the Mac, with the mouse.

## How it works
- **Mouse front button** (Mac Mouse Fix sends Ctrl+Option+Cmd+D): start talking (pink bubble, timer) · press again: the text is written by Whisper (offline) and pasted in the open Claude chat, NOT sent (green bubble).
- **Mouse back button** (Mac Mouse Fix sends Ctrl+Option+Cmd+S) = smart Enter: a voice message is waiting → sends it to Claude from any page or screen; otherwise → a normal Enter.
- Click the pink bubble = cancel. Click the green bubble = close without sending. The bubbles show on the screen where the mouse is.
- Recorder: a launchd background job `ai.unrealagency.claudevoice.rec` running sox on the **MacBook built-in mic** (AirPods never switch to call mode, music stays clean). macOS lists it as "sox" under Microphone.
- Language: auto (French or English).

## Pieces
- `claude_voice.lua` → `~/.hammerspoon/claude_voice.lua` (button logic, Hammerspoon)
- `update.sh` → recorder job, Lua, mic test, Hammerspoon restart
- `install.sh` → full install from zero (Homebrew, sox, whisper-cpp, Hammerspoon, speech model), then update.sh
- Mac Mouse Fix → Buttons: **Button 5 Click = ⌃⌥⌘D**, **Button 4 Click = ⌃⌥⌘S**. Scrolling: Smoothness Off.
- Permissions: Accessibility → Hammerspoon ON · Microphone → sox ON.

## Restore exactly this version
```
curl -fsSL https://unrealagency.ai/tools/claude-voice-v1.0/update.sh | bash
```
From a brand-new Mac: `curl -fsSL https://unrealagency.ai/tools/claude-voice-v1.0/install.sh | bash`, then set the two Mac Mouse Fix buttons above.
