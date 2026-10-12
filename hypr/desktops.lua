-- Each desktop owns one workspace on every output. The shell reads a snapshot;
-- only this module changes state.
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
state.disconnected = state.disconnected or {}

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
      entry = { slots = { allocate() }, selected = 1 }
      desktop.outputs[name] = entry
    end
    pin_workspace(entry.slots[1], name)
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

local function on_monitor(workspace_id, output)
  pin_workspace(workspace_id, output)
  local workspace = hl.get_workspace(tostring(workspace_id))
  if workspace and workspace.monitor and workspace.monitor.name ~= output then
    hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(workspace_id), monitor = output }))
  end
  hl.dispatch(hl.dsp.focus({ monitor = output }))
  hl.dispatch(hl.dsp.focus({ workspace = tostring(workspace_id) }))
end

-- Hyprland's focus dispatchers can warp the pointer across outputs. Suppress
-- those warps while changing the displayed desktop, then restore the setting.
local function without_cursor_warps(callback)
  local warps_were_disabled = hl.get_config("cursor.no_warps")
  if not warps_were_disabled then hl.config({ cursor = { no_warps = true } }) end
  local ok, err = pcall(callback)
  if not warps_were_disabled then hl.config({ cursor = { no_warps = false } }) end
  if not ok then error(err) end
end

local function apply_current(focus_output)
  without_cursor_warps(function()
    local desktop = state.desktops[state.current]
    for _, monitor in ipairs(monitors()) do
      ensure_output(monitor.name)
      local entry = desktop.outputs[monitor.name]
      on_monitor(entry.slots[1], monitor.name)
    end
    if focus_output and hl.get_monitor(focus_output) then
      hl.dispatch(hl.dsp.focus({ monitor = focus_output }))
    end
  end)
end

-- Only the desktop being viewed may remain empty. Count every owned output.
local function occupied_desktops(closing_window)
  local occupied = {}
  for _, window in ipairs(hl.get_windows()) do
    if window ~= closing_window and window.mapped and not window.pinned then
      local desktop_id = locate(window.workspace)
      if desktop_id then occupied[desktop_id] = true end
    end
  end
  return occupied
end

local function collapse_empty(closing_window)
  if #monitors() == 0 then return end
  local occupied = occupied_desktops(closing_window)
  for id = #state.desktops, 1, -1 do
    if id ~= state.current and not occupied[id] then
      table.remove(state.desktops, id)
      for _, saved in pairs(state.disconnected) do
        if id <= #saved then table.remove(saved, id) end
      end
      if id < state.current then state.current = state.current - 1 end
      for next_id = id, #state.desktops do
        local desktop = state.desktops[next_id]
        if not desktop.renamed and desktop.name == "Desktop " .. (next_id + 1) then
          desktop.name = "Desktop " .. next_id
        end
      end
    end
  end
end

local function transaction(callback)
  if busy then return end
  busy = true
  local ok, err = pcall(function()
    callback()
    collapse_empty()
  end)
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
  assert(not slot or tonumber(slot) == 1, "Each desktop has one workspace per monitor")
  transaction(function()
    state.current = desktop_id
    apply_current(monitor.name)
  end)
end

local function step_destination(direction)
  local target = state.current + direction
  if target < 1 then
    target = #state.desktops
    local occupied = occupied_desktops()
    -- If Desktop 1 is empty, visit the existing last desktop so cleanup can
    -- remove Desktop 1 and renumber the destination. Otherwise, keep the
    -- empty-desktop step between occupied endpoints.
    if occupied[state.current] and occupied[target] then target = create() end
  elseif target > #state.desktops then
    if occupied_desktops()[state.current] then target = create() else target = 1 end
  end
  return target
end

function M.step(direction)
  assert(direction == -1 or direction == 1, "Direction must be -1 or 1")
  M.switch(step_destination(direction))
end

function M.cycle_desktop(direction)
  assert(direction == -1 or direction == 1, "Direction must be -1 or 1")
  local target = (state.current - 1 + direction) % #state.desktops + 1
  if target ~= state.current then M.switch(target) end
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
  desktop.renamed = true
  save()
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
  assert(not slot or tonumber(slot) == 1, "Each desktop has one workspace per monitor")
  local entry = desktop.outputs[monitor.name]
  assert(entry and entry.slots[1], "Unknown workspace")
  local workspace_id = entry.slots[1]
  local focused = hl.get_active_monitor()
  transaction(function()
    -- Create the destination on the correct output without visiting it. Rules
    -- also handle an empty workspace recreated after Hyprland destroys it.
    pin_workspace(workspace_id, monitor.name)
    hl.dispatch(hl.dsp.window.move({ window = window, workspace = tostring(workspace_id), follow = false }))
    local workspace = hl.get_workspace(tostring(workspace_id))
    if workspace and workspace.monitor and workspace.monitor.name ~= monitor.name then
      hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(workspace_id), monitor = monitor.name }))
    end
    if follow then
      without_cursor_warps(function()
        state.current = desktop_id
        apply_current(monitor.name)
        hl.dispatch(hl.dsp.focus({ window = window }))
      end)
    elseif focused then
      hl.dispatch(hl.dsp.focus({ monitor = focused.name }))
    end
  end)
end

function M.move_step(direction, follow)
  assert(direction == -1 or direction == 1, "Direction must be -1 or 1")
  if not hl.get_active_window() then return end
  M.move(step_destination(direction), nil, nil, nil, follow)
end

function M.focus_window(address)
  local window = window_by_address(address)
  assert(window and window.mapped, "Window is unavailable")
  local desktop_id, output, slot = locate(window.workspace)
  if desktop_id then
    M.switch(desktop_id, output, slot)
  elseif window.workspace and window.workspace.id > 0 and not window.pinned then
    M.move(state.current, nil, nil, address, true)
  end
  hl.dispatch(hl.dsp.focus({ window = window }))
end

local function move_windows(source, destination, output)
  if source == destination then return {} end
  pin_workspace(destination, output)
  local workspace = hl.get_workspace(tostring(destination))
  if workspace and workspace.monitor and workspace.monitor.name ~= output then
    hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(destination), monitor = output }))
  end
  local moved = {}
  for _, window in ipairs(hl.get_windows()) do
    if window.mapped and not window.pinned and window.workspace and window.workspace.id == source then
      hl.dispatch(hl.dsp.window.move({ window = window, workspace = tostring(destination), follow = false }))
      if window.address then moved[#moved + 1] = window.address end
    end
  end
  return moved
end

-- On a reload from the multi-workspace version, keep each output's selected
-- workspace and bring its other windows into it before retiring extra slots.
local function normalize_entries()
  local available = monitors()
  if #available == 0 then return end
  for _, desktop in ipairs(state.desktops) do
    for output, entry in pairs(desktop.outputs) do
      local canonical = entry.slots[entry.selected] or entry.slots[1] or allocate()
      local destination_output = hl.get_monitor(output) and output or available[1].name
      for _, id in ipairs(entry.slots) do
        if id ~= canonical then move_windows(id, canonical, destination_output) end
      end
      entry.slots = { canonical }
      entry.selected = 1
      entry.previous = nil
    end
  end
  for _, saved in pairs(state.disconnected) do
    for _, entry in ipairs(saved) do
      entry.slots = { entry.slots[entry.selected] or entry.slots[1] or allocate() }
      entry.selected = 1
      entry.previous = nil
      entry.windows = entry.windows or {}
    end
  end
end

local function tracked_window(address)
  for _, saved in pairs(state.disconnected) do
    for _, entry in ipairs(saved) do
      if entry.windows and entry.windows[address] then return true end
    end
  end
end

local function update_tracked_window(address, workspace_id)
  for _, saved in pairs(state.disconnected) do
    for _, entry in ipairs(saved) do
      if entry.windows and entry.windows[address] then entry.windows[address] = workspace_id end
    end
  end
end

-- Merge a disconnected output's windows into the remaining output's one
-- workspace for the same desktop. Track their addresses for restoration.
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
    state.disconnected[output] = {}
    for desktop_id, desktop in ipairs(state.desktops) do
      local source, target = desktop.outputs[output], desktop.outputs[fallback]
      if source then
        local saved = { slots = { source.slots[1] }, selected = 1, windows = {} }
        state.disconnected[output][desktop_id] = saved
        for _, address in ipairs(move_windows(source.slots[1], target.slots[1], fallback)) do
          if tracked_window(address) then
            update_tracked_window(address, target.slots[1])
          else
            saved.windows[address] = target.slots[1]
          end
        end
        desktop.outputs[output] = nil
      end
    end
    state.outputs[output] = nil
  end
end

local function restore_output(output)
  local saved = state.disconnected[output]
  if not saved then return end
  for desktop_id, entry in ipairs(saved) do
    local id = entry.slots[1]
    if locate(id) then id = allocate() end
    pin_workspace(id, output)
    local workspace = hl.get_workspace(tostring(id))
    if workspace and workspace.monitor and workspace.monitor.name ~= output then
      hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = output }))
    end
    state.desktops[desktop_id].outputs[output] = { slots = { id }, selected = 1 }
    for address, expected in pairs(entry.windows or {}) do
      local window = hl.get_window("address:" .. address)
      if window and window.mapped and not window.pinned and window.workspace and window.workspace.id == expected then
        hl.dispatch(hl.dsp.window.move({ window = window, workspace = tostring(id), follow = false }))
        update_tracked_window(address, id)
      end
    end
  end
  state.outputs[output] = true
  state.disconnected[output] = nil
  return true
end

-- Incorporate pre-existing workspaces without losing their windows. A new
-- output keeps its active workspace; other positive workspaces are merged.
local function initialize()
  local available = monitors()
  if #available == 0 then return end
  if #state.desktops == 0 then create() end
  normalize_entries()
  for _, monitor in ipairs(available) do
    restore_output(monitor.name)
    local first = not state.outputs[monitor.name]
    if first then
      local id = monitor.active_workspace and monitor.active_workspace.id
      if not id or id < 1 or locate(id) then
        id = nil
        for _, workspace in ipairs(hl.get_workspaces()) do
          if workspace.id > 0 and workspace.monitor and workspace.monitor.name == monitor.name and not locate(workspace) then
            id = workspace.id
            break
          end
        end
      end
      state.desktops[state.current].outputs[monitor.name] = { slots = { id or allocate() }, selected = 1 }
    end
    ensure_output(monitor.name)
  end
  recover_outputs()
  -- Include inactive workspaces with windows that emit no new events, such as
  -- workspaces created while the feature was disabled.
  local existing = hl.get_workspaces()
  table.sort(existing, function(a, b) return a.id < b.id end)
  for _, workspace in ipairs(existing) do
    if workspace.id > 0 and not locate(workspace) and workspace.monitor and hl.get_monitor(workspace.monitor.name) then
      local entry = state.desktops[state.current].outputs[workspace.monitor.name]
      move_windows(workspace.id, entry.slots[1], workspace.monitor.name)
    end
  end
end

local function workspace_relocated(workspace, monitor)
  if busy or not workspace or not monitor or not hl.get_monitor(monitor.name) then return end
  local desktop_id, output = locate(workspace)
  if not desktop_id or output == monitor.name or not hl.get_monitor(output) then return end
  transaction(function()
    local focused = hl.get_active_monitor()
    ensure_output(monitor.name)
    local target = state.desktops[desktop_id].outputs[monitor.name].slots[1]
    move_windows(workspace.id, target, monitor.name)
    pin_workspace(workspace.id, output)
    local source = hl.get_workspace(tostring(workspace.id))
    if source and source.monitor and source.monitor.name ~= output then
      hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(workspace.id), monitor = output }))
    end
    apply_current(focused and focused.name)
  end)
  return true
end

local function workspace_changed(workspace)
  if busy or not workspace or workspace.id < 1 then return end
  if workspace_relocated(workspace, workspace.monitor) then return end
  local desktop_id, output = locate(workspace)
  if desktop_id then
    if not hl.get_monitor(output) then return end
    if desktop_id ~= state.current then
      M.switch(desktop_id, output)
    else
      save()
    end
  elseif workspace.monitor then
    if not hl.get_monitor(workspace.monitor.name) then return end
    transaction(function()
      local focused = hl.get_active_monitor()
      ensure_output(workspace.monitor.name)
      local target = state.desktops[state.current].outputs[workspace.monitor.name].slots[1]
      move_windows(workspace.id, target, workspace.monitor.name)
      apply_current(focused and focused.name)
    end)
  end
end

local function adopt_window_workspace(window, workspace)
  if busy then return end
  workspace = workspace or (window and window.workspace)
  if not workspace or workspace.id < 1 or locate(workspace) or not workspace.monitor then return end
  local output = workspace.monitor.name
  if not hl.get_monitor(output) then return end
  transaction(function()
    ensure_output(output)
    local target = state.desktops[state.current].outputs[output].slots[1]
    move_windows(workspace.id, target, output)
  end)
  return true
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
  hl.on("window.move_to_workspace", function(window, workspace)
    if not adopt_window_workspace(window, workspace) and not busy then collapse_empty(); save() end
  end)
  hl.on("window.close", function(window)
    if not busy then collapse_empty(window); save() end
  end)
  hl.on("monitor.focused", function() if not busy then save() end end)
  hl.on("monitor.layout_changed", refresh_layout)

  refresh_layout()
end

if _G.omarchy_default_bindings == false or options.bindings == false then return M end

local function bind(key, description, callback)
  hl.unbind(key)
  o.bind(key, description, callback)
end

-- Remove stock native-workspace shortcuts as well as the old desktop-slot
-- shortcuts. Leaving one behind would create a workspace outside the model.
for keycode = 10, 19 do
  local key = "code:" .. keycode
  hl.unbind("SUPER + " .. key)
  hl.unbind("SUPER + SHIFT + " .. key)
  hl.unbind("SUPER + SHIFT + ALT + " .. key)
end
for _, key in ipairs({
  "SUPER + CTRL + TAB",
  "SUPER + mouse_down", "SUPER + mouse_up",
  "SUPER + SHIFT + ALT + LEFT", "SUPER + SHIFT + ALT + RIGHT",
  "SUPER + SHIFT + ALT + UP", "SUPER + SHIFT + ALT + DOWN",
}) do
  hl.unbind(key)
end
bind("SUPER + TAB", "Next desktop", function() M.cycle_desktop(1) end)
bind("SUPER + SHIFT + TAB", "Previous desktop", function() M.cycle_desktop(-1) end)
bind("CTRL + SUPER + UP", "Previous desktop", function() M.step(-1) end)
bind("CTRL + SUPER + DOWN", "Next desktop", function() M.step(1) end)
bind("CTRL + SHIFT + SUPER + UP", "Move window to previous desktop", function() M.move_step(-1, true) end)
bind("CTRL + SHIFT + SUPER + DOWN", "Move window to next desktop", function() M.move_step(1, true) end)
local overview_plugin = options.overview_plugin or "nick1udwig.desktops"
if overview_plugin == "nick1udwig.desktops" or overview_plugin == "nick.desktops" then
  bind("SUPER + D", "Desktop overview", hl.dsp.global("omarchy-desktops:toggle"))
else
  bind("SUPER + D", "Desktop overview", "omarchy-shell shell toggle " .. overview_plugin)
end

return M
