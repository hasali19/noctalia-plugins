--!nonstrict
-- HeadsetControl bar widget: battery status for connected headsets via
-- `headsetcontrol -o json`.
--
-- Drive it from the shell: noctalia msg plugin hasali19/headsetcontrol:battery focused refresh

-- Array of { name, batteryStatus, batteryLevel } for devices that report battery status.
-- batteryStatus: "BATTERY_AVAILABLE" | "BATTERY_CHARGING" | "BATTERY_UNAVAILABLE"
-- batteryLevel: 0-100, or -1 when charging and level is unknown
local devices = {}

-- Only show devices that are available or charging — skip BATTERY_UNAVAILABLE
-- (powered off / disconnected)
local function visibleDevices()
  local result = {}
  for _, device in ipairs(devices) do
    if device.batteryStatus ~= "BATTERY_UNAVAILABLE" then
      table.insert(result, device)
    end
  end
  return result
end

local function render()
  local visible = visibleDevices()
  if #visible == 0 then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)

  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  local children = {}

  for i, device in ipairs(visible) do
    if i > 1 then
      table.insert(children, ui.separator({ orientation = if vertical then "horizontal" else "vertical" }))
    end

    local charging = device.batteryStatus == "BATTERY_CHARGING"
    local lowBattery = device.batteryLevel >= 0 and device.batteryLevel <= 20
    local color = "on_surface"
    if charging then
      color = "primary"
    elseif lowBattery then
      color = "error"
    end

    local rowChildren = { ui.glyph({ name = "headphones", size = 14, color = color }) }
    if not vertical then
      local text
      if charging then
        text = if device.batteryLevel >= 0 then `⚡{device.batteryLevel}%` else "⚡"
      else
        text = `{device.batteryLevel}%`
      end
      table.insert(rowChildren, ui.label({ text = text, color = color }))
    end

    table.insert(children, ui.row({ gap = 4, align = "center" }, rowChildren))
  end

  barWidget.render(container({ gap = 6, align = "center" }, children))

  local names = {}
  for _, device in ipairs(visible) do
    if device.name and device.name ~= "" then
      table.insert(names, device.name)
    end
  end
  barWidget.setTooltip(table.concat(names, "\n"))
end

local function poll()
  noctalia.runAsync("headsetcontrol -o json", function(result)
    if result.exitCode ~= 0 then
      noctalia.log(`headsetcontrol exited with code {result.exitCode}`)
      devices = {}
      render()
      return
    end

    if result.stdout == "" then
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

    local parsed = {}
    for _, dev in ipairs(data.devices) do
      if dev.status == "success" and dev.battery then
        table.insert(parsed, {
          name = dev.device,
          batteryStatus = dev.battery.status,
          batteryLevel = dev.battery.level,
        })
      end
    end
    devices = parsed
    render()
  end)
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
