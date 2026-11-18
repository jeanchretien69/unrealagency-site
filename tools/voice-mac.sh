#!/bin/bash
# Claude Voice for Mac: press your mouse button (or Ctrl+Option+Cmd+D) to start talking,
# press again to stop. Your words are written by Whisper (offline, on your Mac) and sent to
# the Claude chat you have open, then you are put back in the app you were using.
# Install / update:  curl -fsSL https://unrealagency.ai/tools/voice-mac.sh | bash
set -e
DIR="$HOME/.claude-voice"; mkdir -p "$DIR"
step(){ printf '\n\033[1;35m▶ %s\033[0m\n' "$1"; }

# ---------- 1. Homebrew (the Mac app store for tools) ----------
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
if ! command -v brew >/dev/null 2>&1; then
  step "Installing Homebrew. Type your Mac password when asked (nothing shows while you type), then Enter."
  sudo -v < /dev/tty
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
fi
BREW="$(brew --prefix)"

# ---------- 2. Recorder, Whisper, Hammerspoon ----------
step "Installing the recorder, Whisper and Hammerspoon (a few minutes the first time)"
brew list sox >/dev/null 2>&1 || brew install sox
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp
[ -d /Applications/Hammerspoon.app ] || brew install --cask hammerspoon
xattr -dr com.apple.quarantine /Applications/Hammerspoon.app 2>/dev/null || true
WHISPER="$BREW/bin/whisper-cli"; [ -x "$WHISPER" ] || WHISPER="$BREW/bin/whisper-cpp"
REC="$BREW/bin/rec"

# ---------- 3. Speech model (one time) ----------
if [ "$(uname -m)" = arm64 ]; then M=ggml-large-v3-turbo-q5_0.bin; else M=ggml-small.bin; fi
if [ ! -s "$DIR/$M" ]; then
  step "Downloading the speech model (about 500 MB, one time only)"
  curl -fL --progress-bar -o "$DIR/$M.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$M"
  mv "$DIR/$M.part" "$DIR/$M"
fi
ln -sf "$DIR/$M" "$DIR/model.bin"

# ---------- 4. Recorder job, button logic, permissions (same as the updater) ----------
mkdir -p "$HOME/.hammerspoon"
grep -q 'require("claude_voice")' "$HOME/.hammerspoon/init.lua" 2>/dev/null || echo 'claudeVoice = require("claude_voice")' >> "$HOME/.hammerspoon/init.lua"
defaults write org.hammerspoon.Hammerspoon MJShowDockIconKey -bool NO
curl -fsSL https://unrealagency.ai/tools/claude_voice_update.sh | bash
echo "Last step: if macOS asks, turn ON Hammerspoon in System Settings → Privacy & Security → Accessibility."
