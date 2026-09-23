.pragma library
.import "vendor/expose/WindowModel.js" as WindowModel

function selectedWorkspace(snapshot, desktopId, output) {
  var desktop = snapshot.desktops && snapshot.desktops[desktopId - 1]
  var entry = desktop && desktop.outputs && desktop.outputs[output]
  if (!entry || !entry.slots || !entry.slots[entry.selected - 1]) return null
  return { id: entry.slots[entry.selected - 1], slot: entry.selected }
}

// Read each window's metadata once for all desktop thumbnails and grids.
// Populate in source order so pinned windows keep their position in every
// workspace. Rebuilding is reactive; opening and searching reuse the lists.
function indexWindows(snapshot, toplevels) {
  var index = Object.create(null), outputs = Object.create(null)
  var desktops = snapshot.desktops || []
  for (var d = 0; d < desktops.length; d++) {
    var result = index[d + 1] = Object.create(null)
    var names = Object.keys(desktops[d].outputs || {})
    for (var m = 0; m < names.length; m++) {
      var name = names[m], workspace = selectedWorkspace(snapshot, d + 1, name)
      if (!workspace) continue
      var group = outputs[name]
      if (!group) group = outputs[name] = { workspaces: Object.create(null), lists: [] }
      var key = String(Number(workspace.id))
      var list = group.workspaces[key]
      if (!list) {
        list = group.workspaces[key] = []
        group.lists.push(list)
      }
      result[name] = list
    }
  }
  for (var i = 0; i < (toplevels || []).length; i++) {
    var top = toplevels[i]
    if (!WindowModel.isEligible(top) || !top.monitor || !top.workspace) continue
    var output = outputs[String(top.monitor.name || "")]
    if (!output) continue
    if (WindowModel.ipcFor(top).pinned === true) {
      for (var p = 0; p < output.lists.length; p++) output.lists[p].push(top)
    } else {
      var id = Number(top.workspace.id)
      var matches = isFinite(id) && id !== 0 ? output.workspaces[String(id)] : null
      if (matches) matches.push(top)
    }
  }
  return index
}

function windowsFor(index, desktopId, output, query) {
  var windows = index && index[desktopId] && index[desktopId][output] || []
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return windows
  return windows.filter(function(top) {
    return WindowModel.searchTextFor(top).indexOf(needle) !== -1
  })
}

function sameWindows(left, right) {
  // During QML construction the deferred index/source binding can still be
  // undefined. Treat it as empty until the first membership batch arrives.
  left = left || []
  right = right || []
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
