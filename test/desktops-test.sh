#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua
desktop_test_dir=$(mktemp -d)
trap 'rm -rf "$desktop_test_dir"' EXIT

XDG_RUNTIME_DIR="$desktop_test_dir" HYPRLAND_INSTANCE_SIGNATURE=test OMARCHY_DESKTOPS_PATH="$ROOT" lua - <<'LUA'
local handlers, bindings, workspaces, rules = {}, {}, {}, {}
local displays = {
  { name = "left", position = { x = 0, y = 0 }, width = 1920, height = 1080, scale = 1 },
  { name = "right", position = { x = 1920, y = 0 }, width = 2560, height = 1440, scale = 2, transform = 1 },
}
local active_monitor = displays[1]
local windows = {}
local active_window
local cursor = { x = 417.25, y = 266.5 }
local no_warps = false
local fail_focus_once = false
local cursor_warps = 0
local function warp_to(monitor)
  if not no_warps then
    cursor_warps = cursor_warps + 1
    cursor.x = monitor.position.x + monitor.width / 2
    cursor.y = monitor.position.y + monitor.height / 2
  end
end

local function ensure_workspace(id, monitor)
  id = tonumber(id)
  if not workspaces[id] then workspaces[id] = { id = id, monitor = monitor or active_monitor } end
  return workspaces[id]
end
for i, monitor in ipairs(displays) do monitor.active_workspace = ensure_workspace(i, monitor) end
local initial_workspaces = { 1, 2 }
local function event(name, ...) if handlers[name] then handlers[name](...) end end
local function find_monitor(name)
  for _, monitor in ipairs(displays) do if monitor.name == name then return monitor end end
end
local function action(kind, args) return { kind = kind, args = args } end
hl = {
  get_monitors = function() return displays end,
  get_monitor = find_monitor,
  get_active_monitor = function() return active_monitor end,
  get_active_window = function() return active_window end,
  get_config = function(key)
    assert(key == "cursor.no_warps")
    return no_warps
  end,
  config = function(values)
    assert(type(values.cursor.no_warps) == "boolean")
    no_warps = values.cursor.no_warps
  end,
  get_windows = function()
    local result = {}
    for _, window in pairs(windows) do result[#result + 1] = window end
    return result
  end,
  get_window = function(selector) return windows[selector:gsub("^address:", "")] end,
  get_workspace = function(id) return workspaces[tonumber(id)] end,
  get_workspaces = function()
    local result = {}
    for _, workspace in pairs(workspaces) do result[#result + 1] = workspace end
    return result
  end,
  workspace_rule = function(rule) rules[tonumber(rule.workspace)] = rule.monitor end,
  unbind = function(key) bindings[key] = nil end,
  on = function(name, callback) handlers[name] = callback end,
  dsp = {
    global = function(value) return action("global", value) end,
    event = function(value) return action("event", value) end,
    focus = function(args) return action("focus", args) end,
    workspace = { move = function(args) return action("workspace_move", args) end },
    window = { move = function(args) return action("window_move", args) end },
  },
  dispatch = function(command)
    local args = command.args
    if command.kind == "focus" then
      if fail_focus_once then fail_focus_once = false; error("simulated focus failure") end
      if args.monitor then
        active_monitor = assert(find_monitor(args.monitor))
        warp_to(active_monitor)
        event("monitor.focused", active_monitor)
      elseif args.workspace then
        local workspace = ensure_workspace(args.workspace, find_monitor(rules[tonumber(args.workspace)]))
        active_monitor = workspace.monitor
        active_monitor.active_workspace = workspace
        warp_to(active_monitor)
        event("workspace.active", workspace)
      elseif args.window then active_window = args.window; active_monitor = args.window.monitor; warp_to(active_monitor) end
    elseif command.kind == "workspace_move" then
      ensure_workspace(args.workspace).monitor = assert(find_monitor(args.monitor))
    elseif command.kind == "window_move" then
      local window = args.window or active_window
      local workspace = ensure_workspace(args.workspace, find_monitor(rules[tonumber(args.workspace)]))
      window.workspace = workspace
      window.monitor = workspace.monitor
      assert(args.follow == false, "window movement must not independently switch a single monitor")
    end
  end,
}
o = { bind = function(key, description, callback) bindings[key] = callback end }
omarchy_desktops = { enabled = true }
local function load_controller() return dofile(os.getenv("OMARCHY_DESKTOPS_PATH") .. "/hypr/desktops.lua") end
local function state() return dofile(os.getenv("XDG_RUNTIME_DIR") .. "/omarchy-desktops-test.lua") end
local function snapshot() return assert(io.open(os.getenv("XDG_RUNTIME_DIR") .. "/omarchy-desktops-test.json")):read("*a") end
local function selected(desktop, output) return state().desktops[desktop].outputs[output] end
local function visible(desktop)
  for _, monitor in ipairs(displays) do
    local entry = selected(desktop, monitor.name)
    assert(monitor.active_workspace.id == entry.slots[entry.selected], "all monitors must show the same desktop")
  end
end

-- Startup absorbs windows from unowned native workspaces into the desktop.
windows.anchor1 = { address = "0x101", mapped = true, monitor = displays[1], workspace = workspaces[1] }
windows["0x101"] = windows.anchor1
windows.stranded = { address = "0x102", mapped = true, monitor = displays[2], workspace = ensure_workspace(10, displays[2]) }
windows["0x102"] = windows.stranded
active_window = windows.stranded
local controller = load_controller()
assert(cursor.x == 417.25 and cursor.y == 266.5 and not no_warps and cursor_warps == 0,
  "controller startup preserves precise cursor position and restores the cursor setting")
assert(#selected(1, "left").slots == 1 and #selected(1, "right").slots == 1, "one workspace is owned per output")
assert(windows.stranded.workspace.id == selected(1, "right").slots[1], "startup recovers a window from a native workspace")
assert(snapshot():find('"width":720.0', 1, true) and snapshot():find('"height":1280.0', 1, true), "snapshot normalizes rotation and scale")
visible(1)

-- A prior controller may have many occupied slots. The selected workspace
-- becomes canonical, and every other slot's windows are brought into it.
local saved = io.open(os.getenv("XDG_RUNTIME_DIR") .. "/omarchy-desktops-test.lua", "w")
saved:write('return {version=1,current=1,next_workspace=20000,desktops={{name="Desktop 1",outputs={left={slots={1,11},selected=1},right={slots={2,12},selected=2}}}},outputs={left=true,right=true},disconnected={}}')
saved:close()
windows.legacy_left = { address = "0x103", mapped = true, monitor = displays[1], workspace = ensure_workspace(11, displays[1]) }
windows.legacy_right = { address = "0x104", mapped = true, monitor = displays[2], workspace = ensure_workspace(12, displays[2]) }
windows["0x103"], windows["0x104"] = windows.legacy_left, windows.legacy_right
controller = load_controller()
assert(selected(1, "left").slots[1] == 1 and selected(1, "right").slots[1] == 12, "selected legacy workspaces become canonical")
assert(#selected(1, "left").slots == 1 and #selected(1, "right").slots == 1, "legacy extra slots are retired")
assert(windows.legacy_left.workspace.id == 1 and windows.stranded.workspace.id == 12, "windows from retired slots are preserved")
assert(windows.legacy_right.workspace.id == 12 and state().desktops[1].outputs.right.selected == 1, "legacy selection is normalized")
visible(1)

-- Moving between desktops uses the destination's sole workspace.
local warps_before_step = cursor_warps
controller.step(1)
assert(state().current == 2 and #state().desktops == 2, "next desktop is created when needed")
assert(cursor.x == 417.25 and cursor.y == 266.5 and not no_warps
  and cursor_warps == warps_before_step and active_monitor == displays[1],
  "desktop step leaves the cursor fixed and restores focus to the original output")
visible(2)
local destination_right = selected(2, "right").slots[1]
local warps_before_follow = cursor_warps
controller.move(2, "right", nil, "0x102", true)
assert(windows.stranded.workspace.id == destination_right and state().current == 2, "move-and-follow uses the destination workspace")
assert(cursor.x == 417.25 and cursor.y == 266.5 and not no_warps and cursor_warps == warps_before_follow
  and active_monitor == displays[2] and active_window == windows.stranded,
  "move-and-follow focuses its window on another output without moving the cursor")
controller.move(1, "right", nil, "0x102", false)
assert(windows.stranded.workspace.id == 12 and state().current == 2, "silent overview moves stay in the correct desktop")
assert(not pcall(controller.move, 2, nil, 2, "0x102", false), "extra workspace slots are rejected")
assert(not pcall(controller.switch, 1, nil, 2), "switching to a retired slot is rejected")
assert(not pcall(controller.move, 99), "invalid desktop is rejected")
assert(not pcall(controller.move, 2, "missing"), "missing output is rejected")
assert(not pcall(controller.focus_window, "0xdead"), "closed windows cannot target the active window")
controller.rename(1, 'Code "work" \\ tests')
controller = load_controller()
assert(state().desktops[1].name == 'Code "work" \\ tests', "desktop names survive reload")
assert(state().current == 2 and #selected(1, "right").slots == 1, "one-workspace state survives reload")
visible(2)

-- Native workspace activation and external window rules cannot create a
-- hidden second workspace. The controller brings their windows home.
local external = ensure_workspace(888, displays[2])
windows.external = { address = "0x105", mapped = true, monitor = displays[2], workspace = external }
windows["0x105"] = windows.external
hl.dispatch(hl.dsp.focus({ workspace = "888" }))
assert(windows.external.workspace.id == selected(2, "right").slots[1], "external activation recovers its windows")
visible(2)
local inactive = ensure_workspace(889, displays[1])
windows.inactive = { address = "0x106", mapped = true, monitor = displays[1], workspace = inactive }
windows["0x106"] = windows.inactive
event("window.open", windows.inactive)
assert(windows.inactive.workspace.id == selected(2, "left").slots[1], "window rules targeting an inactive workspace are recovered")
local moved = ensure_workspace(890, displays[2])
windows.external.workspace, windows.external.monitor = moved, displays[2]
event("window.move_to_workspace", windows.external, moved)
assert(windows.external.workspace.id == selected(2, "right").slots[1], "external silent moves are recovered")

-- A native move of an owned workspace transfers its windows into the target
-- output's workspace while keeping each output's identity stable.
controller.switch(1)
local source_id = selected(1, "right").slots[1]
local target_id = selected(1, "left").slots[1]
workspaces[source_id].monitor = displays[1]
event("workspace.move_to_monitor", workspaces[source_id], displays[1])
assert(windows.stranded.workspace.id == target_id and windows.legacy_right.workspace.id == target_id, "native workspace moves merge windows into the destination output")
assert(selected(1, "right").slots[1] == source_id and workspaces[source_id].monitor == displays[2], "source output retains its one workspace")
visible(1)

-- Hotplug merges windows on the fallback output and restores their original
-- workspace when the monitor returns, including across controller reload.
controller.move(1, "right", nil, "0x102", true)
local right_id = selected(1, "right").slots[1]
local left_id = selected(1, "left").slots[1]
local disconnected = displays[2]
displays = { displays[1] }
active_monitor = displays[1]
for _, workspace in pairs(workspaces) do
  if workspace.monitor == disconnected then workspace.monitor = active_monitor end
end
event("monitor.layout_changed")
assert(state().outputs.right == nil and #selected(1, "left").slots == 1, "disconnect keeps one fallback workspace")
assert(windows.stranded.workspace.id == left_id and state().disconnected.right[1].windows["0x102"] == left_id, "disconnected windows remain visible and tracked")
visible(1)
controller = load_controller()
disconnected.active_workspace = ensure_workspace(891, disconnected)
displays[2] = disconnected
event("monitor.layout_changed")
assert(selected(1, "right").slots[1] == right_id and windows.stranded.workspace.id == right_id, "reconnect restores original output and windows")
for _, desktop in ipairs(state().desktops) do
  for _, entry in pairs(desktop.outputs) do assert(#entry.slots == 1 and entry.selected == 1, "hotplug preserves one workspace per output") end
end
visible(1)

-- A headless interval leaves state intact until an output is available again.
local connected = displays
displays = {}
active_monitor = nil
event("monitor.layout_changed")
assert(state().outputs.left and state().outputs.right, "headless interval preserves assignments")
displays = connected
active_monitor = displays[1]
event("monitor.layout_changed")
visible(1)

-- Successive disconnects keep the first output's windows reachable and
-- return them to their original output even when it reconnects first.
local dock = { name = "dock", position = { x = 4000, y = 0 }, width = 1920, height = 1080, scale = 1 }
dock.active_workspace = ensure_workspace(900, dock)
displays[3] = dock
event("monitor.layout_changed")
local original_right = selected(1, "right").slots[1]
local original_left = selected(1, "left").slots[1]
displays = { connected[1], dock }
active_monitor = connected[1]
for _, workspace in pairs(workspaces) do
  if workspace.monitor == connected[2] then workspace.monitor = connected[1] end
end
event("monitor.layout_changed")
displays = { dock }
active_monitor = dock
for _, workspace in pairs(workspaces) do
  if workspace.monitor == connected[1] then workspace.monitor = dock end
end
event("monitor.layout_changed")
assert(windows.stranded.workspace.id == selected(1, "dock").slots[1], "successive disconnects keep windows on the remaining output")
displays[2] = connected[2]
event("monitor.layout_changed")
assert(windows.stranded.workspace.id == original_right, "first output to reconnect recovers its tracked windows")
displays[3] = connected[1]
event("monitor.layout_changed")
assert(selected(1, "left").slots[1] == original_left and selected(1, "right").slots[1] == original_right,
  "both outputs recover their original workspace identities")
for _, desktop in ipairs(state().desktops) do
  for _, entry in pairs(desktop.outputs) do assert(#entry.slots == 1, "staggered reconnect keeps one workspace per output") end
end
visible(1)

-- Retiring shortcuts must also remove the stock native workspace bindings.
for keycode = 10, 19 do
  local key = "code:" .. keycode
  assert(bindings["SUPER + " .. key] == nil and bindings["SUPER + SHIFT + " .. key] == nil
    and bindings["SUPER + SHIFT + ALT + " .. key] == nil, "native workspace shortcut is absent: " .. key)
end
for _, key in ipairs({ "SUPER + CTRL + TAB", "SUPER + mouse_down", "SUPER + mouse_up",
  "SUPER + SHIFT + ALT + LEFT", "SUPER + SHIFT + ALT + RIGHT", "SUPER + SHIFT + ALT + UP", "SUPER + SHIFT + ALT + DOWN" }) do
  assert(bindings[key] == nil, "native workspace navigation is absent: " .. key)
end
for _, key in ipairs({ "CTRL + SUPER + UP", "CTRL + SUPER + DOWN", "CTRL + SHIFT + SUPER + UP", "CTRL + SHIFT + SUPER + DOWN" }) do
  assert(type(bindings[key]) == "function", "desktop shortcut is registered: " .. key)
end
assert(type(bindings["SUPER + TAB"]) == "function" and type(bindings["SUPER + SHIFT + TAB"]) == "function",
  "Super+Tab cycles desktops instead of workspaces")
local count_before_cycle = #state().desktops
bindings["SUPER + TAB"]()
assert(#state().desktops == count_before_cycle, "Super+Tab does not create a desktop")
bindings["SUPER + SHIFT + TAB"]()
visible(state().current)
assert(bindings["SUPER + D"].kind == "global" and bindings["SUPER + D"].args == "omarchy-desktops:toggle", "Super+D opens the overview")

-- Moving a window past Desktop 1 must use the same new-bottom destination as
-- stepping past Desktop 1, and follow the moved window there.
active_window = windows.anchor1
cursor.x, cursor.y = 2289.125, 911.875
local before_wrap = #state().desktops
assert(state().current == 1 and before_wrap >= 1, "window move boundary starts on Desktop 1")
local warps_before_wrap = cursor_warps
bindings["CTRL + SHIFT + SUPER + UP"]()
assert(state().current == before_wrap + 1 and #state().desktops == before_wrap + 1,
  "moving a window up from Desktop 1 creates and follows a desktop at the bottom")
assert(active_window.workspace.id == selected(before_wrap + 1, "left").slots[1], "upward wrap moves the focused window")
visible(before_wrap + 1)
controller.move(1, "left", nil, active_window.address, true)
assert(state().current == 1 and #state().desktops == before_wrap, "returning the window removes the empty new desktop")
assert(cursor.x == 2289.125 and cursor.y == 911.875 and not no_warps and cursor_warps == warps_before_wrap,
  "upward move-and-follow also preserves the cursor")

-- The controller respects an existing no-warps preference and restores its
-- temporary override if Hyprland rejects a focus dispatch.
no_warps = true
controller.switch(1)
assert(no_warps and cursor.x == 2289.125 and cursor.y == 911.875, "existing no-warps preference is retained")
no_warps = false
fail_focus_once = true
assert(not pcall(controller.switch, 1), "focus failure is propagated")
assert(not no_warps and cursor.x == 2289.125 and cursor.y == 911.875,
  "focus failure restores the prior cursor setting")
controller.switch(1)

omarchy_desktops.enabled = false
assert(load_controller() == nil and o.desktops == nil, "disabled controller is not callable")
assert(io.open(os.getenv("XDG_RUNTIME_DIR") .. "/omarchy-desktops-test.json") == nil, "disabling removes its live snapshot")
assert(state().current == 1, "disabling retains assignments in the session")
omarchy_desktops.enabled = true
omarchy_desktops.bindings = false
bindings = {}
controller = load_controller()
assert(next(bindings) == nil, "custom bindings may be managed separately")
assert(#selected(1, "left").slots == 1 and #selected(1, "right").slots == 1, "re-enabling retains one workspace per output")
controller.rename(1, string.rep("é", 60))
assert(state().desktops[1].name == string.rep("é", 60), "desktop names accept Unicode characters")
visible(1)
print("ok - one workspace per desktop/output, legacy migration, external recovery, hotplug, and bindings")
LUA

run_node_test <<'JS'
const model = requireFromRoot('DesktopModel.js')
assertDeepEqual(model.array({0:12, 1:34, length:2}), [12,34], 'Qt IPC sequences retain their geometry')
assertEqual(model.luaString('"\\\n\u0001'), '"\\"\\\\\\010\\001"', 'Lua arguments quote control characters without allowing code injection')
const monitor = { x: 1920, y: 0, width: 720, height: 1280 }
const rect = model.windowRect({ at: [1920,0], size:[720,1280] }, monitor, 180, 120)
assertEqual(rect.height, 120, 'portrait window fits the preview height')
assert(rect.width < 180 && rect.x > 0, 'portrait preview is centered without stretching')
const clipped = model.windowRect({ at:[-500,0], size:[4000,1280] }, monitor, 180,120)
assert(clipped.x >= 0 && clipped.width <= 180, 'offscreen and oversized windows stay inside the tile')
JS
