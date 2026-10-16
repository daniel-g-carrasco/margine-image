--!nonstrict
-- Shared helpers for every Keep Awake entry. State comes from the service
-- through noctalia.state; commands go back to it the same way, so only the
-- service runs keep-awake.

local M = {}

M.PANEL = "lucciola/keep_awake:panel"
M.GLYPH_ON = "zzz-off"
M.GLYPH_SCHEDULED = "clock-play"
M.GLYPH_IDLE = "zzz"

function M.snapshot()
  return {
    ready = noctalia.state.get("ka.ready") == true,
    active = noctalia.state.get("ka.active") == true,
    untilT = noctalia.state.get("ka.until") or 0,
    sStart = noctalia.state.get("ka.sstart") or 0,
    sUntil = noctalia.state.get("ka.suntil") or 0,
  }
end

-- Whole days between the calendar date of t and today.
local function dayDiff(t)
  local a = os.date("*t", t)
  local n = os.date("*t")
  local ta = os.time({ year = a.year, month = a.month, day = a.day, hour = 12 })
  local tn = os.time({ year = n.year, month = n.month, day = n.day, hour = 12 })
  return math.floor((ta - tn) / 86400 + 0.5)
end

-- "23:59", "domani 08:00", "18/10 08:00"; midnight reads as the end of the
-- previous day ("mezzanotte", "domani a mezzanotte").
function M.when(t)
  if not t or t <= 0 then
    return ""
  end
  local d = dayDiff(t)
  local hm = os.date("%H:%M", t)
  if hm == "00:00" and d >= 1 then
    if d == 1 then
      return noctalia.tr("time.midnight")
    elseif d == 2 then
      return noctalia.tr("time.midnight_tomorrow")
    end
  end
  if d == 0 then
    return hm
  elseif d == 1 then
    return noctalia.tr("time.tomorrow", { time = hm })
  end
  return noctalia.tr("time.other", { date = os.date("%d/%m", t), time = hm })
end

-- Epoch of today + dayOffset at the given minutes after midnight.
function M.at(dayOffset, minutes)
  local n = os.date("*t")
  return os.time({
    year = n.year,
    month = n.month,
    day = n.day + dayOffset,
    hour = minutes // 60,
    min = minutes % 60,
    sec = 0,
  })
end

-- Hand a keep-awake command line to the service.
function M.send(...)
  local seq = (noctalia.state.get("ka.seq") or 0) + 1
  noctalia.state.set("ka.seq", seq)
  noctalia.state.set("ka.cmd", noctalia.json.encode({ seq = seq, args = { ... } }))
end

function M.watch(fn)
  for _, key in { "ka.ready", "ka.active", "ka.until", "ka.sstart", "ka.suntil" } do
    noctalia.state.watch(key, fn)
  end
end

return M
