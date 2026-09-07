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
    event = function(value) return action("event", value) end,
    focus = function(args) return action("focus", args) end,
    workspace = { move = function(args) return action("workspace_move", args) end },
    window = { move = function(args) return action("window_move", args) end },
  },
  dispatch = function(command)
    local args = command.args
    if command.kind == "focus" then
      if args.monitor then
        active_monitor = assert(find_monitor(args.monitor))
        event("monitor.focused", active_monitor)
      elseif args.workspace then
        local workspace = ensure_workspace(args.workspace, find_monitor(rules[tonumber(args.workspace)]))
        active_monitor = workspace.monitor
        active_monitor.active_workspace = workspace
        event("workspace.active", workspace)
      elseif args.window then active_window = args.window; active_monitor = args.window.monitor end
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

-- Keep both desktops occupied for the isolation and hotplug scenarios.
windows.anchor1 = { mapped = true, workspace = workspaces[1] }
local controller = load_controller()
assert(displays[1].active_workspace.id == 1 and displays[2].active_workspace.id == 2, "adoption preserves existing workspaces")
assert(selected(1, "left").slots[1] == 1 and selected(1, "right").slots[1] == 2, "each monitor has local workspace 1")
assert(snapshot():find('"width":720.0', 1, true) and snapshot():find('"height":1280.0', 1, true), "snapshot normalizes rotation and scale")
controller.focus(3, "left")
controller.focus(4, "right")
visible(1)
controller.step(1)
visible(2)
windows.anchor2 = { mapped = true, workspace = displays[2].active_workspace }
assert(active_monitor.name == "right", "desktop switching preserves the focused output")
controller.focus(2, "right")
controller.step(-1)
visible(1)
assert(selected(1, "left").selected == 3 and selected(1, "right").selected == 4, "return restores both independent selections")
controller.step(1)
visible(2)
assert(selected(2, "right").selected == 2, "each desktop remembers its own selections")
controller.focus(5, "right")
controller.cycle(0, true)
assert(selected(2, "right").selected == 2, "former-workspace stays inside the desktop")

active_window = { address = "0x123", mapped = true, monitor = displays[2], workspace = displays[2].active_workspace }
windows[active_window.address] = active_window
controller.move(1, nil, nil, nil, false)
assert(state().current == 2, "send window leaves current desktop unchanged")
assert(active_window.workspace.id == selected(1, "right").slots[2], "send preserves output and local slot")
visible(2)
controller.move(1, "left", 3, "0x123", true)
assert(active_window.monitor.name == "left", "explicit destination chooses the output")
assert(state().current == 1, "move-and-follow switches desktop")
visible(1)
active_window.pinned = true
assert(not pcall(controller.move, 2, nil, nil, nil, false), "pinned windows cannot silently defeat desktop isolation")
active_window.pinned = false
assert(not pcall(controller.move, 99), "invalid desktop is rejected")
assert(not pcall(controller.move, 2, "missing"), "missing output is rejected")
assert(not pcall(controller.move, 2, nil, 999), "invalid slot is rejected")
assert(not pcall(controller.focus_window, "0xdead"), "closed windows cannot accidentally target the active window")
assert(not pcall(controller.move, 2, nil, nil, "0xdead", false), "dragging a closed window cannot move a different window")

controller.rename(1, 'Code "work" \\ tests')
controller = load_controller()
assert(state().desktops[1].name == 'Code "work" \\ tests', "names survive config reload without evaluating their contents")
assert(state().current == 1 and selected(2, "right").selected == 2, "reload restores controller state")
visible(1)

hl.dispatch(hl.dsp.focus({ workspace = tostring(selected(2, "right").slots[3]) }))
assert(state().current == 2, "an external focus into a different desktop switches the whole desktop")
visible(2)
hl.dispatch(hl.dsp.focus({ workspace = "888" }))
assert(selected(2, "right").slots[#selected(2, "right").slots] == 888, "external workspaces remain reachable in the overview")
controller.switch(1)
controller.focus_window("0x123")
visible(1)

-- Losing an empty Hyprland workspace does not change its logical slot.
local empty = selected(1, "left").slots[8]
workspaces[empty] = nil
controller.focus(8, "left")
assert(displays[1].active_workspace.id == empty, "empty slots are recreated with stable IDs")

local inactive = ensure_workspace(889, displays[1])
event("window.open", { workspace = inactive })
assert(selected(1, "left").slots[#selected(1, "left").slots] == 889, "a rule opening a window on an inactive workspace remains reachable")
assert(selected(1, "left").selected == 8, "adopting an inactive workspace does not switch the view")
event("window.move_to_workspace", active_window, ensure_workspace(890, displays[1]))
assert(selected(1, "left").slots[#selected(1, "left").slots] == 890, "external silent moves remain reachable")

-- Hyprland migrates workspaces before delivering the final output layout.
local disconnected = displays[2]
local before_disconnect = state()
local recovered_id = selected(2, "right").slots[3]
displays = { displays[1] }
active_monitor = displays[1]
for _, workspace in pairs(workspaces) do
  if workspace.monitor == disconnected then workspace.monitor = active_monitor end
end
event("workspace.active", workspaces[recovered_id])
event("monitor.layout_changed")
assert(state().outputs.right == nil, "disconnected output no longer has unreachable groups")
for _, desktop in ipairs(state().desktops) do assert(desktop.outputs.right == nil) end
local found = false
for _, id in ipairs(selected(2, "left").slots) do if id == recovered_id then found = true end end
assert(found, "disconnected workspace keeps its desktop when recovered to another output")
visible(1)
controller.switch(2)
visible(2)
assert(active_window.mapped, "hotplug never closes windows")

-- Resume can disconnect just one display. Its windows and selections must
-- return even if Hyprland config was reloaded while that output was absent.
controller = load_controller()
disconnected.active_workspace = ensure_workspace(891, disconnected)
displays[2] = disconnected
event("monitor.layout_changed")
for desktop_id, desktop in ipairs(before_disconnect.desktops) do
  local before, after = desktop.outputs.right, selected(desktop_id, "right")
  assert(after.selected == before.selected, "reconnect restores the selected workspace on each desktop")
  for slot, id in ipairs(before.slots) do
    assert(after.slots[slot] == id, "reconnect preserves original workspace IDs and slot numbers")
    if workspaces[id] then assert(workspaces[id].monitor == disconnected, "existing windows return to their output") end
  end
end
assert(selected(2, "right").slots[#selected(2, "right").slots] == 891, "reconnect also adopts workspaces created by Hyprland")
visible(2)
local assigned = {}
for _, desktop in ipairs(state().desktops) do
  for _, entry in pairs(desktop.outputs) do
    for _, id in ipairs(entry.slots) do assert(not assigned[id], "workspace ownership stays unique"); assigned[id] = true end
  end
end
local reconnected = displays
displays = {}
active_monitor = nil
event("monitor.layout_changed")
assert(state().outputs.left and state().outputs.right, "headless interval preserves assignments")
displays = reconnected
active_monitor = displays[1]
event("monitor.layout_changed")
visible(2)

-- Native workspace-to-monitor operations update ownership, in either event order.
local native_source = selected(2, "left").selected
local native_workspace = workspaces[selected(2, "left").slots[native_source]]
native_workspace.monitor = displays[2]
displays[2].active_workspace = native_workspace
event("workspace.active", native_workspace)
event("workspace.move_to_monitor", native_workspace, displays[2])
assert(selected(2, "left").slots[native_source] ~= native_workspace.id, "moved workspace releases its old output slot")
local native_target = selected(2, "right")
assert(native_target.slots[native_target.selected] == native_workspace.id, "native monitor move is adopted and selected on its destination")
visible(2)
local inactive_native = workspaces[selected(1, "left").slots[1]]
inactive_native.monitor = displays[2]
event("workspace.move_to_monitor", inactive_native, displays[2])
assert(state().current == 2, "moving an inactive workspace does not change desktops")
visible(2)

for _, key in ipairs({ "CTRL + SUPER + UP", "CTRL + SUPER + DOWN", "CTRL + SHIFT + SUPER + UP", "CTRL + SHIFT + SUPER + DOWN" }) do
  assert(type(bindings[key]) == "function", "desktop shortcut is registered: " .. key)
end
assert(bindings["SUPER + D"] == "omarchy-shell shell toggle nick.desktops", "Super+D toggles this plugin's overview")
for _, key in ipairs({ "CTRL + ALT + UP", "CTRL + ALT + DOWN", "CTRL + ALT + SHIFT + UP", "CTRL + ALT + SHIFT + DOWN", "SUPER + CTRL + SPACE" }) do
  assert(bindings[key] == nil, "old desktop shortcut is no longer registered: " .. key)
end
bindings["CTRL + SUPER + UP"]()
assert(state().current == 1, "Ctrl+Super+Up selects the previous desktop")
visible(1)
bindings["CTRL + SUPER + DOWN"]()
assert(state().current == 2, "Ctrl+Super+Down selects the next desktop")
visible(2)
controller.move(2, "left", 1, "0x123", true)
bindings["CTRL + SHIFT + SUPER + UP"]()
assert(state().current == 1 and active_window.workspace.id == selected(1, "left").slots[1], "Ctrl+Shift+Super+Up brings the window to the previous desktop")
visible(1)
bindings["CTRL + SHIFT + SUPER + DOWN"]()
assert(state().current == 2 and active_window.workspace.id == selected(2, "left").slots[1], "Ctrl+Shift+Super+Down brings the window to the next desktop")
visible(2)
assert(not pcall(controller.step, 0) and not pcall(controller.move_step, 20, false), "invalid directions are rejected")
omarchy_desktops.enabled = false
assert(load_controller() == nil and o.desktops == nil, "disabled controller is not callable")
assert(io.open(os.getenv("XDG_RUNTIME_DIR") .. "/omarchy-desktops-test.json") == nil, "disabled controller removes its live snapshot")
assert(state().current == 2, "disabling retains assignments for this session")
ensure_workspace(892, displays[1])
omarchy_desktops.enabled = true
omarchy_desktops.bindings = false
bindings = {}
controller = load_controller()
assert(next(bindings) == nil, "custom bindings may be managed separately")
assert(selected(2, "left").slots[#selected(2, "left").slots] == 892, "re-enabling adopts workspaces created while disabled")
controller.rename(2, string.rep("é", 60))
assert(state().desktops[2].name == string.rep("é", 60), "desktop names accept Unicode characters")
visible(2)
-- Outputs can return in either order after a dock briefly disconnects. A
-- workspace passing through two fallback monitors still has only one home.
local left, right = displays[1], displays[2]
local dock = { name = "dock", position = { x = 4000, y = 0 }, width = 1920, height = 1080, scale = 1 }
dock.active_workspace = ensure_workspace(893, dock)
displays[3] = dock
event("monitor.layout_changed")
local function unplug(monitor, fallback)
  for i, display in ipairs(displays) do if display == monitor then table.remove(displays, i); break end end
  active_monitor = fallback or find_monitor("left") or dock
  for _, workspace in pairs(workspaces) do
    if workspace.monitor == monitor then workspace.monitor = active_monitor end
  end
  event("monitor.layout_changed")
end
local function reconnect(monitor)
  displays[#displays + 1] = monitor
  event("monitor.layout_changed")
end
for _, order in ipairs({ { left, right }, { right, left } }) do
  local before = state()
  unplug(right)
  unplug(left)
  controller = load_controller()
  reconnect(order[1])
  reconnect(order[2])
  local assigned = {}
  for desktop_id, desktop in ipairs(state().desktops) do
    for output, entry in pairs(desktop.outputs) do
      for slot, id in ipairs(entry.slots) do
        assert(not assigned[id], "staggered reconnect must not duplicate workspace ownership")
        assigned[id] = true
        if output ~= "dock" then
          local original = before.desktops[desktop_id].outputs[output]
          local original_id = original.slots[slot]
          if original_id and (workspaces[original_id] or slot == original.selected) then
            assert(id == original_id, "staggered reconnect restores occupied and selected slots")
            if workspaces[id] then assert(workspaces[id].monitor.name == output, "staggered reconnect returns windows to their original output") end
          end
        end
      end
    end
  end
  visible(2)
end
local moved_id = right.active_workspace.id
unplug(right, dock)
local moved = workspaces[moved_id]
moved.monitor = left
event("workspace.move_to_monitor", moved, left)
reconnect(right)
assert(moved.monitor == left, "an intentional workspace move while undocked supersedes automatic restoration")
-- Empty desktops collapse only once they are no longer being viewed.
windows = {}
controller.focus(1, "left")
assert(#state().desktops == 1 and state().current == 1, "cleanup retains the current empty desktop")
controller.add()
assert(#state().desktops == 1 and state().current == 1, "repeated creation cannot accumulate empty desktops")
controller.step(1)
assert(#state().desktops == 1, "stepping past an empty desktop replaces it")
local keeper = { address = "0x456", mapped = true, monitor = left,
  workspace = ensure_workspace(selected(1, "right").slots[9], right) }
windows[keeper.address] = keeper
controller.rename(1, "Keep me")
controller.add()
assert(#state().desktops == 2, "a window on a hidden workspace of another output keeps its desktop")
controller.rename(2, "Temporary")
controller.switch(1)
assert(#state().desktops == 1 and state().desktops[1].name == "Keep me", "leaving an empty desktop removes it and preserves custom names")
controller.add()
controller.switch(1)
keeper.mapped = false
event("window.close", keeper)
assert(#state().desktops == 1, "closing the last window keeps the viewed desktop")
controller.add()
assert(#state().desktops == 1 and state().desktops[1].name == "Desktop 1", "leaving a formerly occupied desktop collapses and renumbers it")
keeper.mapped = true
keeper.workspace = ensure_workspace(selected(1, "left").slots[1], left)
keeper.monitor = left
controller.add()
controller.move(2, "left", 1, keeper.address, true)
assert(#state().desktops == 1 and state().current == 1, "moving the last window and following collapses its source")
visible(1)
controller.add()
controller.move(2, "left", 1, keeper.address, false)
assert(#state().desktops == 1, "silently emptying an inactive desktop collapses it")
controller.add()
controller.switch(1)
-- Make a destination occupied so switching back does not remove it.
local second = { address = "0x789", mapped = true, monitor = left,
  workspace = keeper.workspace }
windows[second.address] = second
controller.add()
controller.move(2, "left", 1, second.address, false)
controller.switch(1)
controller.move(2, "left", 1, keeper.address, false)
assert(#state().desktops == 2 and state().current == 1, "silently emptying the viewed desktop keeps it until departure")
controller.switch(2)
assert(#state().desktops == 1 and state().current == 1, "departing after a silent move collapses the emptied source")
controller.add()
keeper.mapped = false
second.mapped = false
event("window.close", second)
assert(#state().desktops == 1 and state().current == 1, "closing windows on an inactive desktop collapses it")
keeper.mapped = true
keeper.workspace = ensure_workspace(selected(1, "left").slots[1], left)
-- An external activation also performs cleanup after switching all outputs.
controller.add()
local target = keeper.workspace
hl.dispatch(hl.dsp.focus({ workspace = tostring(target.id) }))
assert(#state().desktops == 1 and state().current == 1, "external activation collapses the empty desktop left behind")
visible(1)
controller = load_controller()
assert(#state().desktops == 1, "collapsed desktops stay removed after reload")
controller.add()
unplug(right, left)
local saved_right = state().disconnected.right[2].slots[1]
controller.move(2, "left", 1, keeper.address, true)
assert(#state().desktops == 1 and #state().disconnected.right == 1, "collapse compacts disconnected output restoration entries")
assert(state().disconnected.right[1].slots[1] == saved_right, "restoration stays attached to the surviving desktop")
controller = load_controller()
reconnect(right)
assert(selected(1, "right").slots[1] == saved_right, "reconnect after collapse and reload restores the surviving output slots")
visible(1)
print("ok - desktop isolation, restore, movement, external workspaces, reload, hotplug, disabling, and scaled output geometry")
LUA

run_node_test <<'JS'
const model = requireFromRoot('DesktopModel.js')
assertDeepEqual(model.array({0:12, 1:34, length:2}), [12,34], 'Qt IPC sequences retain their geometry')
assertEqual(model.luaString('"\\\n\u0001'), '"\\"\\\\\\010\\001"', 'Lua arguments quote control characters without allowing code injection')
const state = { desktops: [{ outputs: { left: { slots: [1,2,3,4,5,6,7,8,9,10], selected: 9 } } }] }
assertDeepEqual(model.slots(state, 1, 'left', [{workspace:{id:7}}]).map(s=>s.slot), [1,2,3,4,5,7,9], 'overview includes occupied and selected slots beyond the initial five')
assertDeepEqual(model.slots(state, 2, 'left', []), [], 'stale desktop selection is safe')
const monitor = { x: 1920, y: 0, width: 720, height: 1280 }
const rect = model.windowRect({ at: [1920,0], size:[720,1280] }, monitor, 180, 120)
assertEqual(rect.height, 120, 'portrait window fits the preview height')
assert(rect.width < 180 && rect.x > 0, 'portrait preview is centered without stretching')
const clipped = model.windowRect({ at:[-500,0], size:[4000,1280] }, monitor, 180,120)
assert(clipped.x >= 0 && clipped.width <= 180, 'offscreen and oversized windows stay inside the tile')
JS
