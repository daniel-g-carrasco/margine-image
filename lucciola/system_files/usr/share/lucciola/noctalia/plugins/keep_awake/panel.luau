--!nonstrict
-- Keep Awake panel: status, quick durations, and a scheduler (start "now" or
-- on a day and time, end on a day and time).

local common = require("./lib/common.luau")

-- Times every 30 minutes, plus 23:59 so "until the end of the day" is there.
local TIMES = {}
local TIME_MIN = {}
for m = 0, 23 * 60 + 30, 30 do
  table.insert(TIMES, string.format("%02d:%02d", m // 60, m % 60))
  table.insert(TIME_MIN, m)
end
table.insert(TIMES, "23:59")
table.insert(TIME_MIN, 23 * 60 + 59)

local function timeIndex(minutes)
  for i, m in TIME_MIN do
    if m == minutes then
      return i - 1
    end
  end
  return 0
end

-- Select indexes are 0-based. Start day 0 means "now".
local startDay = 2 -- tomorrow
local startTime = timeIndex(8 * 60)
local endDay = 1 -- tomorrow
local endTime = timeIndex(23 * 60 + 59)
local message = ""

local function startDays()
  return { noctalia.tr("panel.now"), noctalia.tr("panel.today"), noctalia.tr("panel.tomorrow"), noctalia.tr("panel.day_after") }
end

local function endDays()
  return { noctalia.tr("panel.today"), noctalia.tr("panel.tomorrow"), noctalia.tr("panel.day_after") }
end

local function chosenStart()
  if startDay == 0 then
    return nil
  end
  return common.at(startDay - 1, TIME_MIN[startTime + 1])
end

local function chosenEnd()
  return common.at(endDay, TIME_MIN[endTime + 1])
end

local function statusBlock(s)
  local title, detail, color
  if s.active then
    title = noctalia.tr("panel.status_on")
    detail = noctalia.tr("tooltip.until", { time = common.when(s.untilT) })
    color = "primary"
  else
    title = noctalia.tr("panel.status_off")
    detail = noctalia.tr("panel.status_off_detail")
    color = "on_surface_variant"
  end
  local lines = {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({ name = s.active and common.GLYPH_ON or common.GLYPH_IDLE, size = 22, color = color }),
      ui.column({ gap = 2, flexGrow = 1 }, {
        ui.label({ text = title, fontSize = 15, fontWeight = "bold", color = color }),
        ui.label({ text = detail, fontSize = 12, color = "on_surface_variant" }),
      }),
      ui.button({
        text = s.active and noctalia.tr("panel.turn_off") or noctalia.tr("panel.turn_on"),
        variant = s.active and "destructive" or "primary",
        controlSize = "sm",
        onClick = function()
          common.send(s.active and "off" or "on")
        end,
      }),
    }),
  }
  if s.sStart > 0 then
    table.insert(lines, ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = common.GLYPH_SCHEDULED, size = 16, color = "secondary" }),
      ui.label({
        text = noctalia.tr("panel.scheduled_line", { from = common.when(s.sStart), to = common.when(s.sUntil) }),
        fontSize = 12,
        color = "secondary",
        flexGrow = 1,
      }),
      ui.button({ text = noctalia.tr("panel.cancel_schedule"), variant = "ghost", controlSize = "sm", onClick = function()
        common.send("cancel")
      end }),
    }))
  end
  return ui.column({ gap = 10, padding = 12, fill = "surface_variant/0.4", radius = 10 }, lines)
end

local function quickButton(label, ...)
  local args = { ... }
  return ui.button({
    text = label,
    variant = "outline",
    controlSize = "sm",
    flexGrow = 1,
    onClick = function()
      common.send(table.unpack(args))
    end,
  })
end

local function render()
  local s = common.snapshot()
  panel.render(ui.column({ gap = 14, padding = 16 }, {
    ui.label({ text = "Keep Awake", fontSize = 16, fontWeight = "bold", color = "primary" }),
    statusBlock(s),

    ui.label({ text = noctalia.tr("panel.quick"), fontSize = 13, fontWeight = "bold" }),
    ui.row({ gap = 8 }, {
      quickButton(noctalia.tr("panel.q_1h"), "on", "+1 hour"),
      quickButton(noctalia.tr("panel.q_3h"), "on", "+3 hours"),
    }),
    ui.row({ gap = 8 }, {
      quickButton(noctalia.tr("panel.q_tonight"), "on"),
      quickButton(noctalia.tr("panel.q_tomorrow"), "tomorrow"),
    }),

    ui.separator({}),
    ui.label({ text = noctalia.tr("panel.schedule"), fontSize = 13, fontWeight = "bold" }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = noctalia.tr("panel.from"), width = 44 }),
      ui.select({ options = startDays(), selectedIndex = startDay, controlSize = "sm", flexGrow = 1, onChange = function(v)
        startDay = tonumber(v) or 0
        message = ""
        render()
      end }),
      ui.select({ options = TIMES, selectedIndex = startTime, controlSize = "sm", width = 96, enabled = startDay ~= 0, onChange = function(v)
        startTime = tonumber(v) or 0
        message = ""
        render()
      end }),
    }),
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = noctalia.tr("panel.to"), width = 44 }),
      ui.select({ options = endDays(), selectedIndex = endDay, controlSize = "sm", flexGrow = 1, onChange = function(v)
        endDay = tonumber(v) or 0
        message = ""
        render()
      end }),
      ui.select({ options = TIMES, selectedIndex = endTime, controlSize = "sm", width = 96, onChange = function(v)
        endTime = tonumber(v) or 0
        message = ""
        render()
      end }),
    }),
    ui.label({ text = message, fontSize = 12, color = "error", visible = message ~= "" }),
    ui.row({ justify = "end" }, {
      ui.button({
        text = startDay == 0 and noctalia.tr("panel.start_now") or noctalia.tr("panel.do_schedule"),
        variant = "primary",
        onClick = "onSchedule",
      }),
    }),
  }))
end

function onSchedule()
  local now = os.time()
  local startT = chosenStart()
  local endT = chosenEnd()
  if startT and startT <= now then
    message = noctalia.tr("panel.err_past")
  elseif endT <= (startT or now) then
    message = noctalia.tr("panel.err_order")
  else
    message = ""
    if startT then
      common.send("schedule", "@" .. startT, "@" .. endT)
    else
      common.send("on", "@" .. endT)
    end
  end
  render()
end

common.watch(function()
  render()
end)

function onOpen(_context)
  message = ""
  render()
end
