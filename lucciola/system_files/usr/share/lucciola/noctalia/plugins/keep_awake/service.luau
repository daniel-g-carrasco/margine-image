--!nonstrict
-- Keep Awake service: the only entry that runs keep-awake. It polls
-- `keep-awake status --json` and publishes the result through noctalia.state
-- (ka.active, ka.until, ka.sstart, ka.suntil), and runs the commands the other
-- entries publish on ka.cmd, refreshing right after each one.
--
--   noctalia msg plugin lucciola/keep_awake:service all refresh

noctalia.setUpdateInterval(5000)

local function command()
  local candidates = {
    noctalia.getConfig("command"),
    "/usr/libexec/lucciola/keep-awake",
    "~/.local/bin/lucciola-keep-awake",
  }
  for _, c in candidates do
    if c and c ~= "" then
      local p = noctalia.expandPath(c)
      if noctalia.fileExists(p) then
        return p
      end
    end
  end
  return nil
end

local function refresh()
  local cmd = command()
  if not cmd then
    noctalia.state.set("ka.ready", false)
    return
  end
  noctalia.runAsync({ cmd, "status", "--json" }, function(r)
    if r.exitCode ~= 0 then
      noctalia.log(`keep-awake status failed: {r.stderr}`)
      return
    end
    local s = noctalia.json.decode(r.stdout)
    if type(s) ~= "table" then
      return
    end
    noctalia.state.set("ka.active", s.active == true)
    noctalia.state.set("ka.until", s["until"] or 0)
    noctalia.state.set("ka.sstart", s.scheduled_start or 0)
    noctalia.state.set("ka.suntil", s.scheduled_until or 0)
    noctalia.state.set("ka.ready", true)
  end)
end

function update()
  refresh()
end

noctalia.state.watch("ka.cmd", function(raw)
  local req = raw and noctalia.json.decode(raw)
  if type(req) ~= "table" or type(req.args) ~= "table" then
    return
  end
  local cmd = command()
  if not cmd then
    noctalia.notifyError(noctalia.tr("error.title"), noctalia.tr("error.no_command"))
    return
  end
  local argv = { cmd }
  for _, a in req.args do
    table.insert(argv, tostring(a))
  end
  noctalia.runAsync(argv, function(r)
    if r.exitCode ~= 0 then
      noctalia.notifyError(noctalia.tr("error.title"), noctalia.string.trim(r.stderr or ""))
    end
    refresh()
  end)
end)

function onIpc(event, _payload)
  if event == "refresh" then
    refresh()
  end
end

refresh()
