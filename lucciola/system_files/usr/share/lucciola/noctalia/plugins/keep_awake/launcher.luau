--!nonstrict
-- Keep Awake in the launcher: "/awake" lists the actions; in the global
-- search they appear for words like awake, sveglio, sospensione, coperchio.
-- "/awake 2h", "awake 45m", "awake 18:30" offer a matching duration or end.

local common = require("./lib/common.luau")

local WORDS = { "awake", "keep", "sveglio", "sveglia", "sospensione", "sospendi", "coperchio", "lid", "sleep", "suspend", "caffe" }

local function hasWord(q)
  for _, w in WORDS do
    if q:find(w, 1, true) or (#q >= 3 and w:find(q, 1, true) == 1) then
      return true
    end
  end
  return false
end

-- "2h", "2 ore", "90m", "45 min" -> seconds; "18:30" -> epoch (tomorrow if past).
local function parse(q)
  local n, unit = q:match("(%d+)%s*([hmo])")
  if n then
    local v = tonumber(n)
    if unit == "m" then
      return "dur", v * 60
    end
    return "dur", v * 3600
  end
  local hh, mm = q:match("(%d%d?)[:%.](%d%d)")
  if hh then
    local h, m = tonumber(hh), tonumber(mm)
    if h < 24 and m < 60 then
      local t = common.at(0, h * 60 + m)
      if t <= os.time() then
        t = common.at(1, h * 60 + m)
      end
      return "at", t
    end
  end
  return nil
end

function onQuery(text)
  local q = noctalia.string.trim(text):lower()
  local kind, value = parse(q)
  if q ~= "" and not hasWord(q) and not kind then
    launcher.setResults(text, {})
    return
  end
  local s = common.snapshot()
  local rows = {}
  if kind == "dur" then
    local h = value // 3600
    local m = (value % 3600) // 60
    local label = h > 0 and (m > 0 and `{h} h {m} min` or `{h} h`) or `{m} min`
    table.insert(rows, { id = "dur:" .. value, title = noctalia.tr("launcher.for", { duration = label }), glyph = common.GLYPH_ON, score = 100 })
  elseif kind == "at" then
    table.insert(rows, { id = "at:" .. value, title = noctalia.tr("launcher.until", { time = common.when(value) }), glyph = common.GLYPH_ON, score = 100 })
  end
  if s.active then
    table.insert(rows, {
      id = "off",
      title = noctalia.tr("launcher.off"),
      subtitle = noctalia.tr("tooltip.until", { time = common.when(s.untilT) }),
      glyph = common.GLYPH_IDLE,
      score = 90,
    })
  end
  table.insert(rows, { id = "on", title = noctalia.tr("launcher.tonight"), subtitle = noctalia.tr("launcher.subtitle"), glyph = common.GLYPH_ON })
  table.insert(rows, { id = "tomorrow", title = noctalia.tr("launcher.tomorrow"), subtitle = noctalia.tr("launcher.subtitle"), glyph = common.GLYPH_ON })
  table.insert(rows, { id = "dur:3600", title = noctalia.tr("launcher.for", { duration = "1 h" }), glyph = common.GLYPH_ON })
  if s.sStart > 0 then
    table.insert(rows, {
      id = "cancel",
      title = noctalia.tr("launcher.cancel"),
      subtitle = noctalia.tr("tooltip.range", { from = common.when(s.sStart), to = common.when(s.sUntil) }),
      glyph = common.GLYPH_SCHEDULED,
    })
  end
  table.insert(rows, { id = "panel", title = noctalia.tr("launcher.panel"), subtitle = noctalia.tr("launcher.panel_sub"), glyph = common.GLYPH_SCHEDULED })
  launcher.setResults(text, rows)
end

function onActivate(id)
  if id == "panel" then
    noctalia.togglePanel(common.PANEL)
  elseif id == "on" or id == "tomorrow" or id == "off" or id == "cancel" then
    common.send(id)
  else
    local kind, value = id:match("^(%a+):(%d+)$")
    if kind == "dur" then
      common.send("on", `+{value} seconds`)
    elseif kind == "at" then
      common.send("on", "@" .. value)
    end
  end
end
