.pragma library

// One queue for the entire overview, including every output and sidebar.
// Keep the cursor moving even when a source is waiting for compositor damage.
function createQueue() {
  return {
    entries: [],
    cursor: 0,
    add: function(view) { this.entries.push({ view: view, due: 0 }) },
    remove: function(view) {
      var index = this.entries.findIndex(function(entry) { return entry.view === view })
      if (index < 0) return
      this.entries.splice(index, 1)
      if (index < this.cursor) this.cursor--
      if (this.cursor >= this.entries.length) this.cursor = 0
    },
    tick: function(now) {
      var count = this.entries.length
      for (var i = 0; i < count; i++) {
        var entry = this.entries[this.cursor]
        this.cursor = (this.cursor + 1) % count
        if (!entry.view.captureEnabled || now < entry.due) continue
        if (!entry.view.refresh()) continue
        entry.due = now + entry.view.refreshInterval
        return true
      }
      return false
    }
  }
}
