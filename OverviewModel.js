.pragma library
.import "vendor/expose/WindowModel.js" as WindowModel

function selectedWorkspace(snapshot, desktopId, output) {
  var desktop = snapshot.desktops && snapshot.desktops[desktopId - 1]
  var entry = desktop && desktop.outputs && desktop.outputs[output]
  if (!entry || !entry.slots || !entry.slots[entry.selected - 1]) return null
  return { id: entry.slots[entry.selected - 1], slot: entry.selected }
}

function windowsFor(snapshot, desktopId, output, toplevels, query) {
  var workspace = selectedWorkspace(snapshot, desktopId, output)
  if (!workspace) return []
  var needle = String(query || "").trim().toLowerCase()
  return Array.prototype.filter.call(toplevels || [], function(top) {
    return WindowModel.isEligible(top)
      && WindowModel.isOnScreen(top, output, true)
      && WindowModel.isOnWorkspace(top, workspace)
      && (!needle || WindowModel.searchTextFor(top).indexOf(needle) !== -1)
  })
}

function sameWindows(left, right) {
  return left.length === right.length && left.every(function(top, i) { return top === right[i] })
}

function dropTarget(snapshot, top, desktop, output) {
  var workspace = selectedWorkspace(snapshot, desktop, output)
  if (!workspace || !top || !WindowModel.isEligible(top)
      || (top.lastIpcObject && top.lastIpcObject.pinned)
      || (top.workspace && top.workspace.id === workspace.id)) return null
  return { address: String(top.address), desktop: desktop, output: output, slot: workspace.slot }
}

// Spatial selection follows upstream Exposé's nearest-neighbor scoring.
function directionalIndex(layout, selected, dx, dy) {
  var current = layout[selected]
  if (!current) return 0
  var result = selected, best = Infinity
  layout.forEach(function(rect, i) {
    if (!rect || i === selected) return
    var x = rect.x + rect.width / 2 - current.x - current.width / 2
    var y = rect.y + rect.height / 2 - current.y - current.height / 2
    var primary = dx ? x * dx : y * dy
    if (primary <= 0) return
    var cross = dx ? Math.abs(y) : Math.abs(x)
    var score = primary + cross * cross / Math.max(1, primary) * 2
    if (score < best) { result = i; best = score }
  })
  return result
}
