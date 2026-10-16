--!nonstrict
-- Keep Awake bar indicator. Lit (primary) while Keep Awake holds, a clock
-- while a start is scheduled, dim when off (hidden then if show_when_idle is
-- false). Click opens the panel; right click turns it on until midnight or
-- off.

local common = require("./lib/common.luau")

local function render()
  local s = common.snapshot()
  local showTime = noctalia.getConfig("show_time") == true
  local rows = {}
  if s.active then
    barWidget.setVisible(true)
    barWidget.setGlyph(common.GLYPH_ON)
    barWidget.setGlyphColor("primary")
    barWidget.setText(showTime and common.when(s.untilT) or "")
    barWidget.setColor("primary")
    table.insert(rows, { noctalia.tr("tooltip.active"), noctalia.tr("tooltip.until", { time = common.when(s.untilT) }) })
  elseif s.sStart > 0 then
    barWidget.setVisible(true)
    barWidget.setGlyph(common.GLYPH_SCHEDULED)
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText(showTime and common.when(s.sStart) or "")
    barWidget.setColor("on_surface_variant")
  else
    barWidget.setVisible(noctalia.getConfig("show_when_idle") == true)
    barWidget.setGlyph(common.GLYPH_IDLE)
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText("")
    table.insert(rows, { noctalia.tr("tooltip.title"), noctalia.tr("tooltip.off") })
  end
  if s.sStart > 0 then
    table.insert(rows, {
      noctalia.tr("tooltip.scheduled"),
      noctalia.tr("tooltip.range", { from = common.when(s.sStart), to = common.when(s.sUntil) }),
    })
  end
  barWidget.setTooltip(rows)
end

common.watch(render)

function update()
  render()
end

function onClick()
  noctalia.togglePanel(common.PANEL)
end

function onRightClick()
  if common.snapshot().active then
    common.send("off")
  else
    common.send("on")
  end
end
