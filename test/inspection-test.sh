#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

XDG_RUNTIME_DIR=/unused HYPRLAND_INSTANCE_SIGNATURE=inspection OMARCHY_DESKTOPS_PATH="$ROOT" lua - <<'LUA'
local bindings, unbound = {}, {}
local noop
noop = setmetatable({}, {
  __index = function(_, key)
    assert(type(key) ~= "number", "keybinding inspection must not iterate mock monitor results")
    return noop
  end,
  __call = function() return noop end,
})
hl = setmetatable({
  unbind = function(key) unbound[key] = true end,
  on = function() error("keybinding inspection must not subscribe to compositor events") end,
}, { __index = function() return noop end })
o = { bind = function(key, description, callback)
  assert(unbound[key], "overridden bindings are unbound before registration")
  bindings[key] = callback
end }

-- Read the module before blocking I/O. The inspector runs in the live session:
-- even reading its saved Lua state is unnecessary, and deleting it is unsafe.
local controller = assert(loadfile(os.getenv("OMARCHY_DESKTOPS_PATH") .. "/hypr/desktops.lua"))
local function forbidden() error("keybinding inspection must not access session state") end
loadfile, io.open, os.remove, os.rename = forbidden, forbidden, forbidden, forbidden
omarchy_desktops = { enabled = true }
assert(controller() == o.desktops, "mock inspection loads without compositor initialization")
local count = 0
for _ in pairs(bindings) do count = count + 1 end
assert(count == 40, "all workspace and desktop bindings remain discoverable")
assert(bindings["SUPER + D"] == "omarchy-shell shell toggle nick.desktops")
assert(type(bindings["CTRL + SUPER + DOWN"]) == "function")
assert(type(bindings["CTRL + SHIFT + SUPER + UP"]) == "function")

bindings = {}
omarchy_desktops.enabled = false
assert(controller() == nil and o.desktops == nil)
assert(next(bindings) == nil, "disabled inspection registers no bindings and leaves session files untouched")
omarchy_desktops.enabled = true
omarchy_desktops.bindings = false
assert(controller() == o.desktops and next(bindings) == nil, "custom bindings also skip compositor initialization during inspection")
omarchy_desktops.bindings = nil
omarchy_default_bindings = false
assert(controller() == o.desktops and next(bindings) == nil, "global default-bindings opt-out is honored during inspection")
print("ok - keybinding inspection registers shortcuts without compositor calls or session-state I/O")
LUA
