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

# ---------- 4. Tiny mic app (so macOS asks mic permission for it, not for a script) ----------
cat > "$DIR/rec.sh" <<EOF
#!/bin/bash
rm -f "$DIR/in.wav"
"$REC" -q -c 1 -r 16000 -b 16 "$DIR/in.wav" &
echo \$! > "$DIR/rec.pid"
wait
exit 0
EOF
chmod +x "$DIR/rec.sh"
APP="$HOME/Applications/Claude Voice Mic.app"; mkdir -p "$HOME/Applications"; rm -rf "$APP"
osacompile -o "$APP" -e 'do shell script "$HOME/.claude-voice/rec.sh >/dev/null 2>&1; true"'
PL="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Records your voice for Claude" "$PL" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription Records your voice for Claude" "$PL"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PL" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ai.unrealagency.claudevoice" "$PL" 2>/dev/null || true
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

# ---------- 5. The button logic (Hammerspoon) ----------
mkdir -p "$HOME/.hammerspoon"
cat > "$HOME/.hammerspoon/claude_voice.lua" <<'LUA'
-- Claude Voice: Ctrl+Option+Cmd+D (your mouse front button) = start talking, press again = your text goes into Claude to check, Enter sends.
-- Click the pink bubble while talking = cancel.
local M = {}
local HOME = os.getenv("HOME")
local DIR = HOME .. "/.claude-voice"
local WHISPER = "__WHISPER__"
local APP = HOME .. "/Applications/Claude Voice Mic.app"
local CLAUDE = "com.anthropic.claudefordesktop"
-- REVIEW = true: your text is pasted in Claude and waits for you (fix a word, then press Enter yourself).
-- REVIEW = false: it is sent right away and you go back to the app you were in.
local REVIEW = true
local WORDS = "Claude, Unreal Agency, Kaya, Gian, AdsPower, Higgsfield, Supabase, Discord, Twitter, OnlyFans."
local state, prev, bubble, tick, t0 = "idle", nil, nil, nil, 0

local function hide()
  if tick then tick:stop(); tick = nil end
  if bubble then bubble:delete(); bubble = nil end
end

local function show(text, color)
  if bubble then bubble:delete() end
  local f = hs.screen.mainScreen():frame()
  local w, h = 380, 40
  bubble = hs.canvas.new({ x = f.x + (f.w - w) / 2, y = f.y + 10, w = w, h = h })
  bubble:level(hs.canvas.windowLevels.overlay)
  bubble:behavior({ "canJoinAllSpaces", "stationary" })
  bubble[1] = { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 20, yRadius = 20 },
                fillColor = color or { red = 0.93, green = 0.2, blue = 0.45, alpha = 0.95 } }
  bubble[2] = { type = "text", text = text, textColor = { white = 1 }, textSize = 13, textAlignment = "center",
                frame = { x = 0, y = 11, w = w, h = h - 11 } }
  bubble:clickActivating(false)
  bubble:canvasMouseEvents(true, true)
  bubble:mouseCallback(function(_, msg) if msg == "mouseUp" and state == "rec" then M.cancel() end end)
  bubble:show()
end

local function recPid() return (hs.execute("cat '" .. DIR .. "/rec.pid' 2>/dev/null") or ""):gsub("%s", "") end
local function stopRec() local p = recPid(); if p ~= "" then hs.execute("kill -INT " .. p .. " 2>/dev/null") end end

local function sendToClaude(text)
  local old = hs.pasteboard.getContents()
  hs.pasteboard.setContents(text)
  local c = hs.application.get(CLAUDE)
  if c then c:activate() else hs.application.launchOrFocusByBundleID(CLAUDE) end
  hs.timer.doAfter(0.45, function()
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    if REVIEW then
      hs.alert.show("✏️  Check your text, then press Enter to send", 3)
      hs.timer.doAfter(1.5, function() if old then hs.pasteboard.setContents(old) end end)
      return
    end
    hs.timer.doAfter(0.35, function()
      hs.eventtap.keyStroke({}, "return", 0)
      hs.timer.doAfter(0.35, function()
        if prev and prev:bundleID() ~= CLAUDE then prev:activate() end
        hs.timer.doAfter(1.5, function() if old then hs.pasteboard.setContents(old) end end)
      end)
    end)
  end)
end

function M.start()
  if state ~= "idle" then return end
  prev = hs.application.frontmostApplication()
  os.remove(DIR .. "/rec.pid"); os.remove(DIR .. "/in.wav")
  hs.execute("open -g '" .. APP .. "'")
  state, t0 = "rec", os.time()
  hs.sound.getByName("Tink"):play()
  local function upd()
    local s = os.time() - t0
    show(string.format("🎙  %d:%02d   ·   press again to send   ·   click = cancel", s // 60, s % 60))
  end
  upd(); tick = hs.timer.doEvery(1, upd)
end

function M.cancel()
  stopRec(); hide(); state = "idle"
  hs.sound.getByName("Basso"):play()
end

function M.stop()
  if state ~= "rec" then return end
  state = "busy"
  if tick then tick:stop(); tick = nil end
  stopRec()
  hs.sound.getByName("Pop"):play()
  show("✍️  Writing your message…", { red = 0.4, green = 0.3, blue = 0.65, alpha = 0.95 })
  hs.timer.doAfter(0.8, function()
    os.remove(DIR .. "/out.txt")
    hs.task.new(WHISPER, function()
      local f = io.open(DIR .. "/out.txt"); local text = f and f:read("a") or ""; if f then f:close() end
      text = text:gsub("%[BLANK_AUDIO%]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
      hide(); state = "idle"
      if text == "" then
        hs.alert.show("🎙 Nothing heard. If this keeps happening: System Settings → Privacy & Security → Microphone → turn on “Claude Voice Mic”", 6)
        return
      end
      sendToClaude(text)
    end, { "-m", DIR .. "/model.bin", "-f", DIR .. "/in.wav", "-l", "auto", "-nt", "-np",
           "--prompt", WORDS, "-otxt", "-of", DIR .. "/out" }):start()
  end)
end

function M.toggle() if state == "idle" then M.start() elseif state == "rec" then M.stop() end end

M.key = hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "d", M.toggle)
hs.autoLaunch(true)
hs.accessibilityState(true)
return M
LUA
sed -i '' "s#__WHISPER__#$WHISPER#" "$HOME/.hammerspoon/claude_voice.lua"
grep -q 'require("claude_voice")' "$HOME/.hammerspoon/init.lua" 2>/dev/null || echo 'claudeVoice = require("claude_voice")' >> "$HOME/.hammerspoon/init.lua"
defaults write org.hammerspoon.Hammerspoon MJShowDockIconKey -bool NO

# ---------- 6. Start + ask permissions once ----------
step "Asking for the microphone. Click ALLOW on the popup."
open -g "$APP"; sleep 4
kill -INT "$(cat "$DIR/rec.pid" 2>/dev/null)" 2>/dev/null || true
killall Hammerspoon 2>/dev/null || true; sleep 1
open -a Hammerspoon

printf '\n\033[1;32m✅ Claude Voice installed.\033[0m\n'
echo "Last step: if macOS asks, turn ON Hammerspoon in System Settings → Privacy & Security → Accessibility."
echo "Then press Ctrl+Option+Cmd+D (or your mouse front button) to talk, press again to send to Claude."
