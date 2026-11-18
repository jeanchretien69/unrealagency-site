-- Click-through (like Windows): one click on a window of another app (another screen) brings it to the front
-- AND delivers your click, so you are ready to type. Only for apps that normally "eat" the first click.
-- Add an app: put its bundle id in APPS (find it with: osascript -e 'id of app "Name"').
local C = {}
local APPS = {
  ["com.anthropic.claudefordesktop"] = true, -- Claude
  ["com.hnc.Discord"] = true,                -- Discord
  ["notion.id"] = true,                      -- Notion
}
local MARK = 4242
local T = hs.eventtap.event.types
local P = hs.eventtap.event.properties

local function winAt(p)
  for _, w in ipairs(hs.window.orderedWindows()) do
    local f = w:frame()
    if p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h then return w end
  end
end

local pending = nil
C.tap = hs.eventtap.new({ T.leftMouseDown, T.leftMouseUp }, function(e)
  if e:getProperty(P.eventSourceUserData) == MARK then return false end -- our own click
  local p = e:location()
  if e:getType() == T.leftMouseDown then
    pending = nil
    local front = hs.application.frontmostApplication()
    local fw = hs.window.focusedWindow()
    if fw then local f = fw:frame(); if p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h then return false end end
    local w = winAt(p); if not w then return false end
    local app = w:application(); local id = app and app:bundleID()
    if id and APPS[id] and not (front and front:bundleID() == id) then pending = { p = p, id = id } end
    return false
  end
  -- mouse up: the window is now in front; replay one single click at the same spot (never a double-click)
  if pending then
    local pd = pending; pending = nil
    hs.timer.doAfter(0.12, function()
      local f = hs.application.frontmostApplication(); if not (f and f:bundleID() == pd.id) then return end
      for _, t in ipairs({ T.leftMouseDown, T.leftMouseUp }) do
        local ev = hs.eventtap.event.newMouseEvent(t, pd.p)
        ev:setProperty(P.mouseEventClickState, 1); ev:setProperty(P.eventSourceUserData, MARK); ev:post()
      end
    end)
  end
  return false
end):start()

return C
