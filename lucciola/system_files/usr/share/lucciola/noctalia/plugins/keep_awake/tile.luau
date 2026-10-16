--!nonstrict
-- Keep Awake control-centre tile: click turns it on until midnight or off,
-- right click opens the panel with durations and the scheduler.

local common = require("./lib/common.luau")

local function render()
  local s = common.snapshot()
  shortcut.setIcon(common.GLYPH_ON, common.GLYPH_IDLE)
  shortcut.setActive(s.active)
  shortcut.setEnabled(s.ready)
  if s.active then
    shortcut.setLabel(noctalia.tr("tile.until", { time = common.when(s.untilT) }))
  elseif s.sStart > 0 then
    shortcut.setLabel(noctalia.tr("tile.from", { time = common.when(s.sStart) }))
  else
    shortcut.setLabel(noctalia.tr("tile.label"))
  end
end

common.watch(render)
render()

function onClick()
  if common.snapshot().active then
    common.send("off")
  else
    common.send("on")
  end
end

function onRightClick()
  noctalia.togglePanel(common.PANEL)
end
