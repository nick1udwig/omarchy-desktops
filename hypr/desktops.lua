-- Optional desktop collections. Each desktop owns independent workspace slots
-- on every output. The shell reads a snapshot; only this module changes state.
local options = _G.omarchy_desktops or {}
-- Omarchy's keybinding inspector evaluates this config with callable no-op
-- tables in place of the compositor API. Register bindings there, but do not
-- query monitors or touch the live session's state.
local live_compositor = type(hl.get_monitors) == "function"
if not options.enabled then
  o.desktops = nil
  local runtime, signature = os.getenv("XDG_RUNTIME_DIR"), os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
  if live_compositor and runtime and signature then
    -- Keep the session's assignments for re-enabling, but stop advertising an
    -- active controller to an already-running shell.
    os.remove(runtime .. "/omarchy-desktops-" .. signature .. ".json")
  end
  return
end

local M = {}
o.desktops = M
local slot_count = 10
local runtime = assert(os.getenv("XDG_RUNTIME_DIR"))
local signature = assert(os.getenv("HYPRLAND_INSTANCE_SIGNATURE"))
local base = runtime .. "/omarchy-desktops-" .. signature
local state_path = base .. ".lua"
local snapshot_path = base .. ".json"
local busy = false
local pinned_outputs = {}
local state = { version = 1, current = 1, next_workspace = 10000, desktops = {}, outputs = {} }

local function quote(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    return string.format('\\u%04x', c:byte())
  end) .. '"'
end

local function json(value)
  local kind = type(value)
  if kind == "string" then return quote(value) end
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind ~= "table" then return "null" end
  local out = {}
  if #value > 0 then
    for _, item in ipairs(value) do out[#out + 1] = json(item) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  for key, item in pairs(value) do out[#out + 1] = quote(key) .. ":" .. json(item) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function serialize(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local out = {}
  for key, item in pairs(value) do
    out[#out + 1] = "[" .. serialize(key) .. "]=" .. serialize(item)
  end
  return "{" .. table.concat(out, ",") .. "}"
end

local function write_atomic(path, contents)
  local file, err = io.open(path .. ".tmp", "w")
  if not file then error(err) end
  local written, write_error = file:write(contents)
  local closed, close_error = file:close()
  if not written or not closed then error(write_error or close_error) end
  assert(os.rename(path .. ".tmp", path))
end

local previous = live_compositor and loadfile(state_path, "t", {})
if previous then
  local ok, saved = pcall(previous)
  if ok and type(saved) == "table" and saved.version == 1 and type(saved.desktops) == "table"
    and type(saved.outputs) == "table" and saved.desktops[saved.current] then
    state = saved
  end
end

local function monitors()
  local result = {}
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.name and monitor.active_workspace then result[#result + 1] = monitor end
  end
  table.sort(result, function(a, b)
    if a.position.x ~= b.position.x then return a.position.x < b.position.x end
    return a.name < b.name
  end)
  return result
end

local function locate(workspace)
  if not workspace then return end
  local id = type(workspace) == "number" and workspace or workspace.id
  for desktop_id, desktop in ipairs(state.desktops) do
    for output, entry in pairs(desktop.outputs) do
      for slot, workspace_id in ipairs(entry.slots) do
        if workspace_id == id then return desktop_id, output, slot end
      end
    end
  end
end

local function allocate()
  repeat state.next_workspace = state.next_workspace + 1
  until not hl.get_workspace(tostring(state.next_workspace)) and not locate(state.next_workspace)
  return state.next_workspace
end

local function vacant_slot(entry)
  for slot, id in ipairs(entry.slots) do
    if not hl.get_workspace(tostring(id)) then return slot end
  end
  return #entry.slots + 1
end

local function pin_workspace(id, output)
  if pinned_outputs[id] == output then return end
  hl.workspace_rule({ workspace = tostring(id), monitor = output })
  pinned_outputs[id] = output
end

local function ensure_output(name)
  state.outputs[name] = true
  for _, desktop in ipairs(state.desktops) do
    local entry = desktop.outputs[name]
    if not entry then
      entry = { slots = {}, selected = 1 }
      desktop.outputs[name] = entry
    end
    while #entry.slots < slot_count do entry.slots[#entry.slots + 1] = allocate() end
    for _, id in ipairs(entry.slots) do pin_workspace(id, name) end
  end
end

local function create(name)
  local id = #state.desktops + 1
  state.desktops[id] = { name = name or ("Desktop " .. id), outputs = {} }
  for output in pairs(state.outputs) do ensure_output(output) end
  return id
end

local function save()
  local outputs = {}
  for _, monitor in ipairs(monitors()) do
    local width, height = monitor.width, monitor.height
    if (monitor.transform or 0) % 2 == 1 then width, height = height, width end
    outputs[#outputs + 1] = {
      name = monitor.name, x = monitor.position.x, y = monitor.position.y,
      width = width / monitor.scale, height = height / monitor.scale,
    }
  end
  local focused = hl.get_active_monitor()
  write_atomic(state_path, "return " .. serialize(state) .. "\n")
  write_atomic(snapshot_path, json({
    version = 1, enabled = true, current = state.current,
    desktops = state.desktops, monitors = outputs,
    focusedMonitor = focused and focused.name or "",
  }) .. "\n")
  hl.dispatch(hl.dsp.event("omarchy-desktops"))
end

local function remember()
  for _, monitor in ipairs(monitors()) do
    local desktop_id, output, slot = locate(monitor.active_workspace)
    if desktop_id == state.current then
      state.desktops[desktop_id].outputs[output].selected = slot
    end
  end
end

local function on_monitor(workspace_id, output)
  pin_workspace(workspace_id, output)
  local workspace = hl.get_workspace(tostring(workspace_id))
  if workspace and workspace.monitor and workspace.monitor.name ~= output then
    hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(workspace_id), monitor = output }))
  end
  hl.dispatch(hl.dsp.focus({ monitor = output }))
  hl.dispatch(hl.dsp.focus({ workspace = tostring(workspace_id) }))
end

local function apply_current(focus_output)
  local desktop = state.desktops[state.current]
  for _, monitor in ipairs(monitors()) do
    ensure_output(monitor.name)
    local entry = desktop.outputs[monitor.name]
    on_monitor(entry.slots[entry.selected], monitor.name)
  end
  if focus_output and hl.get_monitor(focus_output) then
    hl.dispatch(hl.dsp.focus({ monitor = focus_output }))
  end
end

local function transaction(callback)
  if busy then return end
  busy = true
  local ok, err = pcall(callback)
  busy = false
  save()
  if not ok then error(err) end
end

function M.switch(desktop_id, output, slot)
  desktop_id = tonumber(desktop_id)
  assert(desktop_id and state.desktops[desktop_id], "Unknown desktop")
  local monitor
  if output then monitor = hl.get_monitor(output) else monitor = hl.get_active_monitor() end
  assert(monitor and monitor.name, "Monitor is unavailable")
  if slot then
    slot = tonumber(slot)
    local entry = state.desktops[desktop_id].outputs[monitor.name]
    assert(slot and entry and entry.slots[slot], "Unknown workspace")
  end
  transaction(function()
    remember()
    state.current = desktop_id
    if slot then
      local entry = state.desktops[desktop_id].outputs[monitor.name]
      if entry.selected ~= slot then entry.previous = entry.selected end
      entry.selected = slot
    end
    apply_current(monitor.name)
  end)
end

function M.step(direction)
  assert(direction == -1 or direction == 1, "Direction must be -1 or 1")
  local target = state.current + direction
  if target < 1 then return end
  if target > #state.desktops then create() end
  M.switch(target)
end

function M.add()
  local id = create()
  M.switch(id)
end

function M.rename(desktop_id, name)
  local desktop = state.desktops[tonumber(desktop_id)]
  assert(desktop, "Unknown desktop")
  assert(type(name) == "string" and name:match("%S") and utf8.len(name) and utf8.len(name) <= 80, "Use a name of 1–80 characters")
  desktop.name = name
  save()
end

function M.focus(slot, output)
  M.switch(state.current, output, slot)
end

function M.cycle(direction, previous_workspace)
  local monitor = hl.get_active_monitor()
  if not monitor then return end
  local entry = state.desktops[state.current].outputs[monitor.name]
  if not entry then return end
  local slot = previous_workspace and entry.previous or ((entry.selected - 1 + direction) % #entry.slots + 1)
  if slot then M.focus(slot, monitor.name) end
end

local function window_by_address(address)
  assert(type(address) == "string", "Invalid window address")
  local hex = address:gsub("^0x", "")
  assert(hex:match("^[%da-fA-F]+$"), "Invalid window address")
  return hl.get_window("address:0x" .. hex)
end

function M.move(desktop_id, output, slot, address, follow)
  local window
  if address then window = window_by_address(address) else window = hl.get_active_window() end
  assert(window and window.mapped, "Window is unavailable")
  assert(not window.pinned, "Unpin the window before moving it to another desktop")
  desktop_id = tonumber(desktop_id)
  local desktop = state.desktops[desktop_id]
  assert(desktop, "Unknown desktop")
  local monitor
  if output then monitor = hl.get_monitor(output) else monitor = window.monitor end
  assert(monitor and monitor.name, "Monitor is unavailable")
  local _, _, source_slot = locate(window.workspace)
  slot = tonumber(slot) or source_slot or 1
  local entry = desktop.outputs[monitor.name]
  assert(entry and entry.slots[slot], "Unknown workspace")
  local workspace_id = entry.slots[slot]
  local focused = hl.get_active_monitor()
  transaction(function()
    remember()
    -- Create the destination on the correct output without visiting it. Rules
    -- also handle an empty slot recreated after Hyprland destroys it.
    pin_workspace(workspace_id, monitor.name)
    hl.dispatch(hl.dsp.window.move({ window = window, workspace = tostring(workspace_id), follow = false }))
    local workspace = hl.get_workspace(tostring(workspace_id))
    if workspace and workspace.monitor and workspace.monitor.name ~= monitor.name then
      hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(workspace_id), monitor = monitor.name }))
    end
    if follow then
      state.current = desktop_id
      entry.selected = slot
      apply_current(monitor.name)
      hl.dispatch(hl.dsp.focus({ window = window }))
    elseif focused then
      hl.dispatch(hl.dsp.focus({ monitor = focused.name }))
    end
  end)
end

function M.move_step(direction, follow)
  assert(direction == -1 or direction == 1, "Direction must be -1 or 1")
  if not hl.get_active_window() then return end
  local target = state.current + direction
  if target < 1 then return end
  if target > #state.desktops then create() end
  M.move(target, nil, nil, nil, follow)
end

function M.focus_window(address)
  local window = window_by_address(address)
  assert(window and window.mapped, "Window is unavailable")
  local desktop_id, output, slot = locate(window.workspace)
  if desktop_id then M.switch(desktop_id, output, slot) end
  hl.dispatch(hl.dsp.focus({ window = window }))
end

-- A disconnected output's existing workspaces join a remaining output within
-- the same desktop. Reuse uncreated slots first; never combine or close windows.
-- With no outputs connected, defer recovery until one becomes available.
local function recover_outputs()
  local connected, available = {}, monitors()
  for _, monitor in ipairs(available) do connected[monitor.name] = true end
  if #available == 0 then return end
  local focused = hl.get_active_monitor()
  local fallback = focused and connected[focused.name] and focused.name or available[1].name
  local removed = {}
  for output in pairs(state.outputs) do
    if not connected[output] then removed[#removed + 1] = output end
  end
  table.sort(removed)
  for _, output in ipairs(removed) do
    for _, desktop in ipairs(state.desktops) do
      local source, target = desktop.outputs[output], desktop.outputs[fallback]
      if source then
        for _, id in ipairs(source.slots) do
          if hl.get_workspace(tostring(id)) then
            target.slots[vacant_slot(target)] = id
            pin_workspace(id, fallback)
            hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = fallback }))
          end
        end
        desktop.outputs[output] = nil
      end
    end
    state.outputs[output] = nil
  end
end

-- Incorporate pre-existing workspaces without changing their IDs. New outputs
-- adopt unowned workspaces into the current desktop and get local slot numbers.
local function initialize()
  if #state.desktops == 0 then create() end
  for _, monitor in ipairs(monitors()) do
    local first = not state.outputs[monitor.name]
    if first then
      local slots = {}
      for _, workspace in ipairs(hl.get_workspaces()) do
        if workspace.id > 0 and workspace.monitor and workspace.monitor.name == monitor.name and not locate(workspace) then
          slots[#slots + 1] = workspace.id
        end
      end
      table.sort(slots)
      local entry = { slots = slots, selected = 1 }
      state.desktops[state.current].outputs[monitor.name] = entry
      for i, id in ipairs(slots) do if monitor.active_workspace.id == id then entry.selected = i end end
    end
    ensure_output(monitor.name)
  end
  recover_outputs()
  -- Workspaces may have appeared while the feature was disabled. Adopt those
  -- too, including inactive workspaces with windows that emit no new events.
  local existing = hl.get_workspaces()
  table.sort(existing, function(a, b) return a.id < b.id end)
  for _, workspace in ipairs(existing) do
    if workspace.id > 0 and not locate(workspace) and workspace.monitor and hl.get_monitor(workspace.monitor.name) then
      local entry = state.desktops[state.current].outputs[workspace.monitor.name]
      entry.slots[#entry.slots + 1] = workspace.id
      if workspace.monitor.active_workspace.id == workspace.id then entry.selected = #entry.slots end
    end
  end
end

local function workspace_relocated(workspace, monitor)
  if busy or not workspace or not monitor or not hl.get_monitor(monitor.name) then return end
  local desktop_id, output, slot = locate(workspace)
  if not desktop_id or output == monitor.name or not hl.get_monitor(output) then return end
  transaction(function()
    remember()
    local focused = hl.get_active_monitor()
    ensure_output(monitor.name)
    local desktop = state.desktops[desktop_id]
    desktop.outputs[output].slots[slot] = allocate()
    local target = desktop.outputs[monitor.name]
    local target_slot = vacant_slot(target)
    target.slots[target_slot] = workspace.id
    pin_workspace(workspace.id, monitor.name)
    if monitor.active_workspace and monitor.active_workspace.id == workspace.id then
      target.previous = target.selected
      target.selected = target_slot
      state.current = desktop_id
    end
    apply_current(focused and focused.name)
  end)
  return true
end

local function workspace_changed(workspace)
  if busy or not workspace or workspace.id < 1 then return end
  -- Native workspace-to-monitor bindings are still usable. Update ownership
  -- before reacting to activation on that output, regardless of event order.
  if workspace_relocated(workspace, workspace.monitor) then return end
  local desktop_id, output, slot = locate(workspace)
  if desktop_id then
    -- Hyprland can report workspace events during output removal, before the
    -- final layout event. Recovery will restore the whole desktop afterwards.
    if not hl.get_monitor(output) then return end
    local entry = state.desktops[desktop_id].outputs[output]
    if entry.selected ~= slot then entry.previous = entry.selected; entry.selected = slot end
    if desktop_id ~= state.current then
      M.switch(desktop_id, output, slot)
    else
      save()
    end
  elseif workspace.monitor then
    -- Explicit external workspace commands join the current desktop. Never
    -- strand windows on a workspace that our bar and overview cannot reach.
    ensure_output(workspace.monitor.name)
    local entry = state.desktops[state.current].outputs[workspace.monitor.name]
    entry.slots[#entry.slots + 1] = workspace.id
    entry.previous = entry.selected
    entry.selected = #entry.slots
    save()
  end
end

local function adopt_window_workspace(window, workspace)
  if busy then return end
  workspace = workspace or (window and window.workspace)
  if not workspace or workspace.id < 1 or locate(workspace) or not workspace.monitor then return end
  local output = workspace.monitor.name
  if not hl.get_monitor(output) then return end
  ensure_output(output)
  local entry = state.desktops[state.current].outputs[output]
  entry.slots[#entry.slots + 1] = workspace.id
  save()
end

local function refresh_layout()
  if busy then return end
  transaction(function()
    local focused = hl.get_active_monitor()
    initialize()
    apply_current(focused and focused.name)
  end)
end

if live_compositor then
  hl.on("hyprland.start", refresh_layout)
  hl.on("workspace.active", workspace_changed)
  hl.on("workspace.move_to_monitor", workspace_relocated)
  hl.on("window.open", adopt_window_workspace)
  hl.on("window.move_to_workspace", adopt_window_workspace)
  hl.on("monitor.focused", function() if not busy then save() end end)
  hl.on("monitor.layout_changed", refresh_layout)

  refresh_layout()
end

if _G.omarchy_default_bindings == false or options.bindings == false then return M end

local function bind(key, description, callback)
  hl.unbind(key)
  o.bind(key, description, callback)
end

for slot = 1, 10 do
  local key = "code:" .. (slot + 9)
  bind("SUPER + " .. key, "Desktop workspace " .. slot, function() M.focus(slot) end)
  bind("SUPER + SHIFT + " .. key, "Move window to desktop workspace " .. slot, function() M.move(state.current, nil, slot, nil, true) end)
  bind("SUPER + SHIFT + ALT + " .. key, "Send window to desktop workspace " .. slot, function() M.move(state.current, nil, slot, nil, false) end)
end
bind("SUPER + TAB", "Next desktop workspace", function() M.cycle(1) end)
bind("SUPER + SHIFT + TAB", "Previous desktop workspace", function() M.cycle(-1) end)
bind("SUPER + CTRL + TAB", "Former desktop workspace", function() M.cycle(0, true) end)
bind("SUPER + mouse_down", "Next desktop workspace", function() M.cycle(1) end)
bind("SUPER + mouse_up", "Previous desktop workspace", function() M.cycle(-1) end)
bind("CTRL + SUPER + UP", "Previous desktop", function() M.step(-1) end)
bind("CTRL + SUPER + DOWN", "Next desktop", function() M.step(1) end)
bind("CTRL + SHIFT + SUPER + UP", "Move window to previous desktop", function() M.move_step(-1, true) end)
bind("CTRL + SHIFT + SUPER + DOWN", "Move window to next desktop", function() M.move_step(1, true) end)
bind("SUPER + D", "Desktop overview", "omarchy-shell shell toggle " .. (options.overview_plugin or "nick.desktops"))

return M
