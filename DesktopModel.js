function luaString(value) {
  return '"' + String(value).replace(/[\x00-\x1f\\"]/g, function(c) {
    if (c === '"' || c === "\\") return "\\" + c
    return "\\" + ("00" + c.charCodeAt(0)).slice(-3)
  }) + '"'
}

// IPC geometry uses Qt sequence wrappers, which have length/index access but
// do not necessarily pass JavaScript's Array.isArray().
// Native arrays are reused; callers treat the result as read-only.
function array(value) {
  if (Array.isArray(value)) return value
  if (!value || typeof value === "string" || typeof value.length !== "number") return []
  return Array.prototype.slice.call(value)
}

function slots(snapshot, desktopId, output, toplevels, visibleSlot) {
  var desktop = array(snapshot.desktops)[desktopId - 1]
  var entry = desktop && desktop.outputs ? desktop.outputs[output] : null
  if (!entry) return []
  var occupied = {}
  array(toplevels).forEach(function(w) {
    if (w.workspace) occupied[w.workspace.id] = true
  })
  return array(entry.slots).map(function(id, i) {
    return { id: id, slot: i + 1, selected: entry.selected === i + 1, occupied: !!occupied[id] }
  }).filter(function(item) { return item.slot <= 5 || item.slot === visibleSlot || item.selected || item.occupied })
}

function windowRect(client, monitor, width, height) {
  var at = array(client.at), size = array(client.size)
  var mw = Math.max(1, monitor.width), mh = Math.max(1, monitor.height)
  var scale = Math.min(width / mw, height / mh)
  var w = Math.max(8, Math.min(mw, Number(size[0]) || mw) * scale)
  var h = Math.max(8, Math.min(mh, Number(size[1]) || mh) * scale)
  return {
    x: (width - mw * scale) / 2 + Math.max(0, Math.min(mw - w / scale, (Number(at[0]) || 0) - monitor.x)) * scale,
    y: (height - mh * scale) / 2 + Math.max(0, Math.min(mh - h / scale, (Number(at[1]) || 0) - monitor.y)) * scale,
    width: w, height: h
  }
}

if (typeof module !== "undefined") module.exports = { luaString, array, slots, windowRect }
