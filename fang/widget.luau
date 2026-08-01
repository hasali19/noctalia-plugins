--!nonstrict
-- Fang bar widget: battery status for Razer mice via the Fang DBus service
-- (dev.hasali.Fang). A long-lived `gdbus monitor` stream reacts to device
-- and DPI changes immediately; a periodic poll (get_devices.py) is the
-- fallback against missed signals.
--
-- Drive it from the shell: noctalia msg plugin hasali19/fang:battery focused refresh

local scriptPath = `{noctalia.pluginDir()}/get_devices.py`

-- Array of { path, name, battery, charging, connected }
local devices = {}

local function render()
  if #devices == 0 then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)

  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  local children = {}

  for i, device in ipairs(devices) do
    if i > 1 then
      table.insert(children, ui.separator({ orientation = if vertical then "horizontal" else "vertical" }))
    end

    local color = "on_surface"
    if device.charging then
      color = "primary"
    elseif device.battery <= 20 then
      color = "error"
    end

    local rowChildren = { ui.glyph({ name = "mouse", size = 14, color = color }) }
    if not vertical then
      local text = if device.charging then `⚡{device.battery}%` else `{device.battery}%`
      table.insert(rowChildren, ui.label({ text = text, color = color }))
    end

    table.insert(children, ui.row({
      gap = 4,
      align = "center",
      opacity = if device.connected then 1.0 else 0.4,
    }, rowChildren))
  end

  barWidget.render(container({ gap = 6, align = "center" }, children))

  local names = {}
  for _, device in ipairs(devices) do
    if device.name and device.name ~= "" then
      table.insert(names, device.name)
    end
  end
  barWidget.setTooltip(table.concat(names, "\n"))
end

local function poll()
  noctalia.runAsync(`python3 '{scriptPath}'`, function(result)
    if result.exitCode ~= 0 then
      devices = {}
      render()
      return
    end

    local data, err = noctalia.json.decode(result.stdout)
    if err or type(data) ~= "table" or type(data.devices) ~= "table" then
      devices = {}
      render()
      return
    end

    devices = data.devices
    render()
  end)
end

-- ── DBus signal monitor (react immediately to device/DPI changes) ─────────

local function handleSignalLine(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  if trimmed == "" then
    return
  end

  local colonIdx = trimmed:find(": ", 1, true)
  if not colonIdx then
    return
  end

  local sigPath = trimmed:sub(1, colonIdx - 1)
  local rest = trimmed:sub(colonIdx + 2)

  local parenIdx = rest:find(" %(")
  if not parenIdx then
    return
  end

  local fullName = rest:sub(1, parenIdx - 1)
  local argsStr = rest:sub(parenIdx + 2, #rest - 1)

  local lastDot = fullName:find("%.[^.]*$")
  if not lastDot then
    return
  end

  local iface = fullName:sub(1, lastDot - 1)
  local member = fullName:sub(lastDot + 1)

  -- Remove devices immediately when the DeviceManager's Devices property
  -- changes, without waiting for the poll.
  if
    iface == "org.freedesktop.DBus.Properties"
    and member == "PropertiesChanged"
    and argsStr:find("'dev.hasali.Fang.DeviceManager'", 1, true)
    and argsStr:find("'Devices'", 1, true)
  then
    local currentPaths = {}
    for path in argsStr:gmatch("'(/dev/hasali/Fang/[^']*)'") do
      currentPaths[path] = true
    end
    local filtered = {}
    for _, device in ipairs(devices) do
      if currentPaths[device.path] then
        table.insert(filtered, device)
      end
    end
    devices = filtered
    render()
  end

  -- Notify when the Dpi property changes on a mouse device
  if iface == "org.freedesktop.DBus.Properties" and member == "PropertiesChanged" then
    if argsStr:find("'dev.hasali.Fang.Mouse'", 1, true) then
      local newDpi = argsStr:match("'Dpi': <[a-z0-9]+ (%d+)>")
      if newDpi then
        local deviceName = "Mouse"
        for _, device in ipairs(devices) do
          if device.path == sigPath and device.name and device.name ~= "" then
            deviceName = device.name
            break
          end
        end
        noctalia.notify(deviceName, `DPI changed to {newDpi}`)
      end
    end
  end

  poll()
end

if noctalia.commandExists("gdbus") then
  noctalia.runStream("gdbus monitor --system --dest dev.hasali.Fang", handleSignalLine)
end

function update()
  noctalia.setUpdateInterval((noctalia.getConfig("poll_interval") or 30) * 1000)
  poll()
end

function onClick()
  poll()
end

function onIpc(event)
  if event == "refresh" then
    poll()
  end
end

poll()
