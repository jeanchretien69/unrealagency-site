#!/bin/bash
# Claude Voice update: newest button logic + recorder, and a mic app that is a plain shell app
# (the old AppleScript "applet" sometimes stopped on a "Press Run to run this script" window).
set -e
DIR="$HOME/.claude-voice"; mkdir -p "$DIR"
echo "▶ Updating Claude Voice…"
curl -fsSL https://unrealagency.ai/tools/claude_voice_rec.sh -o "$DIR/rec.sh"; chmod +x "$DIR/rec.sh"
curl -fsSL https://unrealagency.ai/tools/claude_voice.lua -o "$HOME/.hammerspoon/claude_voice.lua"
rm -f "$DIR/mic.txt"
pkill -f "Claude Voice Mic" 2>/dev/null || true; pkill -f claude-voice/rec.sh 2>/dev/null || true
APP="$HOME/Applications/Claude Voice Mic.app"; mkdir -p "$HOME/Applications"; rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/MacOS/ClaudeVoiceMic" <<'EOF'
#!/bin/bash
exec "$HOME/.claude-voice/rec.sh"
EOF
chmod +x "$APP/Contents/MacOS/ClaudeVoiceMic"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ClaudeVoiceMic</string>
  <key>CFBundleIdentifier</key><string>ai.unrealagency.claudevoicemic</string>
  <key>CFBundleName</key><string>Claude Voice Mic</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Records your voice for Claude</string>
</dict></plist>
EOF
codesign --force -s - "$APP" >/dev/null 2>&1 || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "▶ Asking for the microphone: click ALLOW if a popup appears (speak a little)."
open -g "$APP"; sleep 4
kill -INT "$(cat "$DIR/rec.pid" 2>/dev/null)" 2>/dev/null || true; sleep 1
if [ -s "$DIR/in.wav" ]; then echo "✅ Mic OK ($(wc -c < "$DIR/in.wav" | tr -d ' ') bytes recorded)"; else echo "⚠️ No recording yet: if you saw a popup, click Allow and run this again."; fi
killall Hammerspoon 2>/dev/null || true; sleep 1; open -a Hammerspoon
echo "✅ Claude Voice updated. Mouse front button = talk / put text in Claude / send."
