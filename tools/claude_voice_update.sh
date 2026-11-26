#!/bin/bash
# Claude Voice update: newest button logic, and the recorder as a small background job (launchd)
# that runs sox on the MacBook's built-in mic. No more helper app (it sometimes hung or showed "Press Run").
DIR="$HOME/.claude-voice"; mkdir -p "$DIR"
echo "▶ Updating Claude Voice…"
for b in /opt/homebrew/bin /usr/local/bin; do [ -x "$b/sox" ] && SOX="$b/sox"; done
[ -n "$SOX" ] || { echo "❌ sox is missing: run the full installer first (curl -fsSL https://unrealagency.ai/tools/voice-mac.sh | bash)"; exit 1; }
# stop anything left over from the old versions
pkill -f "Claude Voice Mic" 2>/dev/null; pkill -f claude-voice/rec.sh 2>/dev/null; pkill -x sox 2>/dev/null
rm -rf "$HOME/Applications/Claude Voice Mic.app" "$DIR/rec.pid"
# the MacBook's built-in microphone (never the AirPods: their mic switches them to call mode and ruins the music)
MIC=$(system_profiler SPAudioDataType 2>/dev/null | awk '/^        [^ ].*:$/{n=$0; sub(/^ +/,"",n); sub(/:$/,"",n); inp=0} /Input Channels/{inp=1} /Transport: Built-in/{ if (inp){ print n; exit } }')
echo "$MIC" > "$DIR/mic.txt"
if [ -n "$MIC" ]; then IN="<string>-t</string><string>coreaudio</string><string>$MIC</string>"; echo "   mic: $MIC"; else IN="<string>-d</string>"; echo "   mic: default"; fi
LABEL=ai.unrealagency.claudevoice.rec
PL="$HOME/Library/LaunchAgents/$LABEL.plist"; mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$SOX</string><string>-q</string>$IN<string>-c</string><string>1</string><string>-r</string><string>16000</string><string>-b</string><string>16</string><string>$DIR/in.wav</string></array>
  <key>RunAtLoad</key><false/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null; launchctl bootstrap "gui/$(id -u)" "$PL"
curl -fsSL https://unrealagency.ai/tools/claude_voice.lua -o "$HOME/.hammerspoon/claude_voice.lua"
# click-through: one click on Claude/Discord/Notion in another screen = in front AND clicked
curl -fsSL https://unrealagency.ai/tools/claude_click.lua -o "$HOME/.hammerspoon/claude_click.lua"
grep -q 'require("claude_click")' "$HOME/.hammerspoon/init.lua" 2>/dev/null || echo 'claudeClick = require("claude_click")' >> "$HOME/.hammerspoon/init.lua"
echo "▶ Test: say a few words now (4 seconds). If macOS asks for the microphone, click ALLOW."
rm -f "$DIR/in.wav"; launchctl kickstart -k "gui/$(id -u)/$LABEL"; sleep 4; launchctl kill SIGINT "gui/$(id -u)/$LABEL" 2>/dev/null; sleep 1
if [ -s "$DIR/in.wav" ]; then
  AMP=$("$SOX" "$DIR/in.wav" -n stat 2>&1 | awk '/Maximum amplitude/{print $3}')
  echo "✅ Mic OK: $(wc -c < "$DIR/in.wav" | tr -d ' ') bytes, loudness $AMP (above 0.02 = it heard you)"
else
  echo "⚠️ Nothing recorded. Allow \"sox\" in System Settings → Privacy & Security → Microphone, then run this again."
fi
killall Hammerspoon 2>/dev/null; sleep 1; open -a Hammerspoon
echo "✅ Claude Voice updated. Mouse front button = talk · again = text in Claude · again = send."

# reload Hammerspoon so the new buttons work right away
osascript -e 'tell application "Hammerspoon" to quit' 2>/dev/null; sleep 1; open -g -a Hammerspoon
echo "✅ Buttons updated: FRONT = record / stop / send (Claude Voice) · BACK = Claude mic on · again = stop (fix the text if you want) · again = send"   # reload Hammerspoon
