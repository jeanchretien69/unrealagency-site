-- Claude Voice
-- FRONT thumb button (Ctrl+Option+Cmd+D): press = record, press = stop (text goes into Claude), press = send.
-- BACK thumb button (Ctrl+Option+Cmd+S): Claude's own mic, pressed directly: press = start, press again = stop and send.
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
-- BACK thumb button (Mac Mouse Fix sends Ctrl+Option+Cmd+S): Claude's own mic, clicked for you.
-- Claude is in front: press 1 = its mic starts right away (no app switch) · press 2 = mic stops, text lands, sent (Enter).
-- Claude not in front: same, but Claude comes forward first and you go back to your app after sending.
-- (Claude has no keyboard shortcut for its chat mic, so the mic button is found and pressed through Accessibility.)
local ax = hs.axuielement
local nState, nPrev, nTimer = "idle", nil, nil
local START = { "dictat", "microphone", "voice input", "record", "speak", "micro" }
local STOP = { "stop", "done", "finish", "transcri", "confirm", "dictat", "microphone", "micro" }
local function label(e)
  local t = {}
  for _, a in ipairs({ "AXDescription", "AXTitle", "AXHelp", "AXRoleDescription" }) do
    local v = e:attributeValue(a); if type(v) == "string" and v ~= "" and a ~= "AXRoleDescription" then t[#t + 1] = v end
  end
  return table.concat(t, " "):lower()
end
local function claudeFront(after)
  local f = hs.application.frontmostApplication()
  if f and f:bundleID() == CLAUDE then return after() end
  local c = hs.application.get(CLAUDE)
  if c then c:activate() else hs.application.launchOrFocusByBundleID(CLAUDE) end
  local tries = 0
  hs.timer.waitUntil(function() tries = tries + 1; local f = hs.application.frontmostApplication(); return tries > 40 or (f and f:bundleID() == CLAUDE) end,
    function() hs.timer.doAfter(0.15, after) end, 0.05)
end
-- find Claude's mic button (words = what its label may contain), press it; done(ok)
local function pressMic(words, done)
  local c = hs.application.get(CLAUDE); if not c then return done(false) end
  local app = ax.applicationElement(c)
  pcall(function() app:setAttributeValue("AXManualAccessibility", true) end) -- Electron: show the page's buttons
  local win = app:attributeValue("AXFocusedWindow") or app
  win:elementSearch(function(_, found)
    local best, all = nil, {}
    for i = 1, (found and #found or 0) do
      local e = found[i]; local l = label(e)
      if l ~= "" then all[#all + 1] = l end
      if not l:find("voice mode") then
        for rank, w in ipairs(words) do
          if l:find(w, 1, true) and (not best or rank < best.rank) then best = { e = e, rank = rank } end
        end
      end
    end
    if best then best.e:performAction("AXPress"); return done(true) end
    local f = io.open(DIR .. "/claude_buttons.txt", "w"); if f then f:write(table.concat(all, "\n")); f:close() end
    hs.alert.show("🎙 Can't find Claude's mic button (button names saved in ~/.claude-voice/claude_buttons.txt)", 5)
    done(false)
  end, ax.searchCriteriaFunction({ attribute = "AXRole", value = "AXButton" }))
end
function M.native()
  if state ~= "idle" then return end -- the front-button recorder is busy: don't mix the two
  if nState == "idle" then
    nState = "busy"
    nPrev = hs.application.frontmostApplication()
    claudeFront(function()
      pressMic(START, function(ok)
        if not ok then nState = "idle"; return end
        nState = "on"; hs.sound.getByName("Tink"):play()
        show("🎙  Claude mic ON   ·   back button again = SEND", { red = 0.2, green = 0.45, blue = 0.9, alpha = 0.95 })
        hs.timer.doAfter(3, function() if nState == "on" then hide() end end)
        nTimer = hs.timer.doAfter(300, function() if nState == "on" then nState = "idle"; hide() end end)
      end)
    end)
  elseif nState == "on" then
    nState = "busy"; if nTimer then nTimer:stop(); nTimer = nil end
    claudeFront(function()
      pressMic(STOP, function()
        show("✍️  Sending…", { red = 0.4, green = 0.3, blue = 0.65, alpha = 0.95 })
        hs.timer.doAfter(1.8, function()
          hs.eventtap.keyStroke({}, "return", 0)
          hs.sound.getByName("Pop"):play(); hide(); nState = "idle"
          hs.timer.doAfter(0.4, function() if nPrev and nPrev:bundleID() ~= CLAUDE then nPrev:activate() end end)
        end)
      end)
    end)
  end
end
M.enterKey = hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "s", M.native)
hs.autoLaunch(true)
hs.accessibilityState(true)
return M
