-- One-click focus, for ALL apps and ALL screens (like Windows):
-- a click on a window that is not the active one brings it to the front AND your click lands, ready to type.
-- How: that first click is held back, the window is focused, then the same click is replayed once (never twice).
-- Ctrl+Option+Cmd+K turns it off/on.
local C = { on = true }
local MARK = 4243
local T = hs.eventtap.event.types
local P = hs.eventtap.event.properties

local function inside(f, p) return p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h end
local function winAt(p)
  for _, w in ipairs(hs.window.orderedWindows()) do
    if inside(w:frame(), p) then return w end
  end
end
local function post(t, p, flags)
  local ev = hs.eventtap.event.newMouseEvent(t, p)
  ev:setProperty(P.mouseEventClickState, 1); ev:setProperty(P.eventSourceUserData, MARK)
  if flags then ev:setFlags(flags) end
  ev:post()
end

local held = nil -- { p, flags, downSent, upWaiting }
C.tap = hs.eventtap.new({ T.leftMouseDown, T.leftMouseUp }, function(e)
  if not C.on or e:getProperty(P.eventSourceUserData) == MARK then return false end
  local p = e:location()
  if e:getType() == T.leftMouseDown then
    held = nil
    local fw = hs.window.focusedWindow()
    if fw and inside(fw:frame(), p) then return false end -- already the active window: normal click
    local w = winAt(p)
    if not w or not w:isStandard() or w == fw then return false end -- dock, menu bar, desktop, popups: untouched
    local h = { p = p, flags = e:getFlags(), downSent = false, upWaiting = false }; held = h
    w:focus()
    local tries = 0
    hs.timer.waitUntil(function()
      tries = tries + 1
      local f = hs.window.focusedWindow()
      return tries > 12 or (f and f:id() == w:id())
    end, function()
      if held ~= h then return end
      post(T.leftMouseDown, h.p, h.flags); h.downSent = true
      if h.upWaiting then hs.timer.doAfter(0.02, function() post(T.leftMouseUp, h.p, h.flags) end); held = nil end
    end, 0.02)
    return true -- hold the original click back
  end
  -- mouse up
  if held then
    if held.downSent then held = nil; return false end -- our replayed click is down: let the real release through
    held.upWaiting = true; return true -- release comes before the replay: send it right after
  end
  return false
end):start()

C.key = hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "k", function()
  C.on = not C.on
  hs.alert.show(C.on and "🖱  One-click focus: ON" or "🖱  One-click focus: OFF", 1.5)
end)

return C
