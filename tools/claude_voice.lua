-- Claude Voice
-- FRONT thumb button (Ctrl+Option+Cmd+D): press = record, press = stop (text goes into Claude), press = send.
-- BACK thumb button (Ctrl+Option+Cmd+S): Claude's own dictation (faster): press = start, press again = stop and send.
-- Click the pink bubble while talking = cancel.
local M = {}
local HOME = os.getenv("HOME")
local DIR = HOME .. "/.claude-voice"
local WHISPER = "/opt/homebrew/bin/whisper-cli"
for _, w in ipairs({ "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli", "/opt/homebrew/bin/whisper-cpp", "/usr/local/bin/whisper-cpp" }) do if hs.fs.attributes(w) then WHISPER = w; break end end
-- the recorder is a small background job (launchd) that runs sox on the MacBook mic; macOS lists it as "sox" under Microphone
local JOB = "gui/" .. (hs.execute("id -u") or ""):gsub("%s", "") .. "/ai.unrealagency.claudevoice.rec"
local CLAUDE = "com.anthropic.claudefordesktop"
-- REVIEW = true: your text is pasted in Claude and waits for you (fix a word, then press Enter yourself).
-- REVIEW = false: it is sent right away and you go back to the app you were in.
local REVIEW = true
local WORDS = "Claude, Unreal Agency, Kaya, Gian, AdsPower, Higgsfield, Supabase, Discord, Twitter, OnlyFans."
local state, prev, bubble, tick, t0 = "idle", nil, nil, nil, 0
local endReview

local function hide()
  if tick then tick:stop(); tick = nil end
  if bubble then bubble:delete(); bubble = nil end
end

local function show(text, color)
  if bubble then bubble:delete() end
  -- the bubble shows on the screen where your mouse is, so you always see it
  local scr = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f = scr:frame()
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
  bubble:mouseCallback(function(_, msg) if msg ~= "mouseUp" then return end if state == "rec" then M.cancel() elseif state == "review" then endReview() end end)
  bubble:show()
end

local function stopRec() hs.execute("/bin/launchctl kill SIGINT " .. JOB .. " 2>/dev/null") end

local function sendToClaude(text)
  local old = hs.pasteboard.getContents()
  hs.pasteboard.setContents(text)
  local c = hs.application.get(CLAUDE)
  if c then c:activate() else hs.application.launchOrFocusByBundleID(CLAUDE) end
  hs.timer.doAfter(0.45, function()
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    if REVIEW then
      hs.timer.doAfter(1.5, function() if old then hs.pasteboard.setContents(old) end end)
      M.review()
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

-- review: the text waits in Claude; the mouse button (or Enter in Claude) sends it, even if you clicked elsewhere meanwhile
local reviewTimer, reviewTap, reviewFollow
endReview = function()
  if reviewTimer then reviewTimer:stop(); reviewTimer = nil end
  if reviewTap then reviewTap:stop(); reviewTap = nil end
  if reviewFollow then reviewFollow:stop(); reviewFollow = nil end
  if state == "review" then state = "idle"; hide() end
end
function M.review()
  if reviewTimer then reviewTimer:stop() end
  if reviewTap then reviewTap:stop() end
  if reviewFollow then reviewFollow:stop() end
  state = "review"
  -- the green bubble only shows for a few seconds, then hides; the front button still sends for 2 minutes
  show("✏️  Fix your text · front button again = SEND · click = close", { red = 0.12, green = 0.5, blue = 0.32, alpha = 0.95 })
  reviewFollow = hs.timer.doAfter(6, function() if state == "review" then hide() end end)
  reviewTimer = hs.timer.doAfter(120, endReview)
  -- you pressed Enter yourself in Claude: done, the next button press starts a new message
  reviewTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if e:getKeyCode() == 36 or e:getKeyCode() == 76 then local f = hs.application.frontmostApplication(); if f and f:bundleID() == CLAUDE then hs.timer.doAfter(0, endReview) end end
    return false
  end):start()
end
function M.send()
  endReview()
  local back = hs.application.frontmostApplication()
  local c = hs.application.get(CLAUDE); if c then c:activate() end
  local tries = 0
  hs.timer.waitUntil(function()
    tries = tries + 1; local f = hs.application.frontmostApplication()
    if f and f:bundleID() ~= CLAUDE and c and tries % 10 == 0 then c:activate() end
    return tries > 60 or (f and f:bundleID() == CLAUDE)
  end, function()
    hs.timer.doAfter(0.2, function()
      hs.eventtap.keyStroke({}, "return", 0)
      hs.sound.getByName("Pop"):play()
      hs.timer.doAfter(0.4, function() if back and back:bundleID() ~= CLAUDE then back:activate() end end)
    end)
  end, 0.05)
end

function M.start()
  if state ~= "idle" then return end
  prev = hs.application.frontmostApplication()
  os.remove(DIR .. "/in.wav")
  hs.execute("/bin/launchctl kickstart -k " .. JOB .. " 2>/dev/null")
  state, t0 = "rec", os.time()
  hs.sound.getByName("Tink"):play()
  local function upd()
    local s = os.time() - t0
    show(string.format("🎙  %d:%02d   ·   press again = stop   ·   click = cancel", s // 60, s % 60))
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
        hs.alert.show("🎙 Nothing heard. If this keeps happening: System Settings → Privacy & Security → Microphone → turn on “sox”", 6)
        return
      end
      sendToClaude(text)
    end, { "-m", DIR .. "/model.bin", "-f", DIR .. "/in.wav", "-l", "auto", "-nt", "-np",
           "--prompt", WORDS, "-otxt", "-of", DIR .. "/out" }):start()
  end)
end

function M.toggle() if state == "idle" then M.start() elseif state == "rec" then M.stop() elseif state == "review" then M.send() end end

M.key = hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "d", M.toggle)
-- BACK thumb button (Mac Mouse Fix sends Ctrl+Option+Cmd+S): Claude's own dictation, inside the Claude chat.
-- press 1 = bring Claude forward + start its mic (Cmd+D) · press 2 = stop its mic (Cmd+D), wait for the text, send (Enter), go back.
local nState, nPrev, nTimer = "idle", nil, nil
local function claudeFront(after)
  local c = hs.application.get(CLAUDE)
  if c then c:activate() else hs.application.launchOrFocusByBundleID(CLAUDE) end
  local tries = 0
  hs.timer.waitUntil(function() tries = tries + 1; local f = hs.application.frontmostApplication(); return tries > 40 or (f and f:bundleID() == CLAUDE) end,
    function() hs.timer.doAfter(0.15, after) end, 0.05)
end
function M.native()
  if state ~= "idle" then return end -- the front-button recorder is busy: don't mix the two
  if nState == "idle" then
    nPrev = hs.application.frontmostApplication()
    claudeFront(function()
      hs.eventtap.keyStroke({ "cmd" }, "d", 0)
      nState = "on"; hs.sound.getByName("Tink"):play()
      show("🎙  Claude dictation   ·   back button again = SEND", { red = 0.2, green = 0.45, blue = 0.9, alpha = 0.95 })
      nTimer = hs.timer.doAfter(300, function() if nState == "on" then nState = "idle"; hide() end end)
    end)
  elseif nState == "on" then
    nState = "busy"; if nTimer then nTimer:stop(); nTimer = nil end
    claudeFront(function()
      hs.eventtap.keyStroke({ "cmd" }, "d", 0)
      show("✍️  Sending…", { red = 0.4, green = 0.3, blue = 0.65, alpha = 0.95 })
      hs.timer.doAfter(1.4, function()
        hs.eventtap.keyStroke({}, "return", 0)
        hs.sound.getByName("Pop"):play(); hide(); nState = "idle"
        hs.timer.doAfter(0.4, function() if nPrev and nPrev:bundleID() ~= CLAUDE then nPrev:activate() end end)
      end)
    end)
  end
end
M.enterKey = hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "s", M.native)
hs.autoLaunch(true)
hs.accessibilityState(true)
return M
