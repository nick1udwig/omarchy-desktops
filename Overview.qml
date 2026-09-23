import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "vendor/expose/IconResolver.js" as IconResolver
import "OverviewModel.js" as Model
import "."

Item {
  id: root
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property bool opened: false
  property double openedAt: 0
  property double openWorkMs: 0
  property string filterText: ""
  property string keyboardOutput: ""
  property string draggedWindow: ""
  readonly property string dragMimeType: "application/x-omarchy-window"
  property var pendingDrop: null
  property string wallpaperRevision: ""
  onWallpaperRevisionChanged: {
    // Follow the new inode after an atomic symlink replacement too.
    wallpaperWatch.watchChanges = false
    wallpaperWatch.watchChanges = true
  }
  property var panels: ({})
  property var iconCache: ({})
  readonly property alias captureScheduler: captures
  readonly property bool firstFrameReady: opened && Object.keys(panels).length > 0
    && Object.keys(panels).every(function(name) { return root.panels[name].firstFrameAt > 0 })
  readonly property var toplevels: Hyprland.toplevels.values
  readonly property alias windowIndex: windowLists.value
  readonly property int selectedDesktop: DesktopState.current
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string wallpaper: "file://" + stateHome + "/omarchy/current/background?desktops=" + wallpaperRevision

  function open(payloadJson) {
    openedAt = Date.now()
    filterText = ""
    draggedWindow = ""
    keyboardOutput = DesktopState.focusedMonitor || (Quickshell.screens[0] ? Quickshell.screens[0].name : "")
    DesktopState.error = ""
    // Quickshell tracks membership/title events, but not every resize/pin.
    // Keep this asynchronous refresh until geometry has an event-driven feed.
    Hyprland.refreshToplevels()
    // A keypress may arrive before a queued membership update. Flush only
    // when dirty so its new previews join the readiness gate on this opening.
    windowLists.rebuild()
    captures.begin()
    opened = true
    Qt.callLater(function() { root.focusOutput(root.keyboardOutput) })
    openWorkMs = Date.now() - openedAt
  }

  function close() { opened = false; draggedWindow = ""; pendingDrop = null }

  // Hyprland delivers this directly to the resident shell: no sh, timeout,
  // or short-lived Qt IPC client is needed on the keypress path.
  GlobalShortcut {
    appid: "omarchy-desktops"
    name: "toggle"
    description: "Desktop overview"
    onPressed: {
      if (root.shell) root.shell.toggle(root.shell.pluginId, "{}")
      else if (root.opened) root.close()
      else root.open("{}")
    }
  }

  function beginDrag(address) { draggedWindow = address; pendingDrop = null }
  function dropTarget(desktop, output) {
    if (!opened || !draggedWindow) return null
    var top = toplevels.find(function(w) { return w.address === root.draggedWindow })
    return Model.dropTarget(DesktopState.snapshot, top, desktop, output)
  }
  function stageDrop(event, desktop, output) {
    event.accepted = false
    var target = dropTarget(desktop, output)
    if (!target || event.getDataAsString(dragMimeType) !== draggedWindow) return
    pendingDrop = target
    event.accept(Qt.MoveAction)
  }
  function finishDrag(address, accepted) {
    if (draggedWindow !== address) return
    var target = accepted ? pendingDrop : null
    draggedWindow = ""
    pendingDrop = null
    // Moving destroys the source delegate. Wait until Qt releases its grab.
    if (target) Qt.callLater(function() {
      DesktopState.move(target.address, target.desktop, target.output, target.slot)
    })
  }

  function registerPanel(name, panel) {
    var next = Object.assign({}, panels)
    if (panel) next[name] = panel
    else delete next[name]
    panels = next
    if (opened && !panels[keyboardOutput]) {
      keyboardOutput = Object.keys(panels)[0] || ""
      Qt.callLater(function() { root.focusOutput(root.keyboardOutput) })
    }
  }

  function focusOutput(name) {
    if (!opened || !panels[name]) return
    keyboardOutput = name
    panels[name].focusSearch()
  }

  function nextOutput(direction) {
    var names = Array.prototype.map.call(Quickshell.screens, function(s) { return s.name })
    if (!names.length) return
    var index = Math.max(0, names.indexOf(keyboardOutput))
    focusOutput(names[(index + direction + names.length) % names.length])
  }

  function chooseDesktop(id, output) {
    var entry = Model.selectedWorkspace(DesktopState.snapshot, id, output)
    if (entry) {
      focusOutput(output)
      DesktopState.switchTo(id, output, entry.slot)
    }
  }

  function focusWindow(address) {
    if (!address) return
    DesktopState.focusWindow(address)
    close()
  }

  function iconFor(top) {
    var identity = IconResolver.identityFor(top)
    if (Object.prototype.hasOwnProperty.call(iconCache, identity.key)) return iconCache[identity.key]
    var entries = DesktopEntries.applications ? DesktopEntries.applications.values : []
    var entry = IconResolver.findEntry(entries, identity.candidates)
    var name = entry ? String(entry.icon || "application-x-executable") : String(identity.candidates[0] || "application-x-executable")
    var library = shell && shell.appLibrary ? shell.appLibrary : null
    var result = library && typeof library.iconSource === "function" ? String(library.iconSource(name) || "") : ""
    if (!result) result = Quickshell.iconPath(name, true) || Quickshell.iconPath("application-x-executable", true)
    iconCache[identity.key] = result
    return result
  }

  function geometry() {
    var result = []
    for (var name in panels) if (panels[name].showing) result = result.concat(panels[name].geometry())
    return result
  }

  WindowIndex {
    id: windowLists
    snapshot: DesktopState.snapshot
    toplevels: root.toplevels
  }

  CaptureScheduler {
    id: captures
    active: root.opened && root.draggedWindow === ""
    refreshAllowed: root.firstFrameReady
    onReadyChanged: if (ready && root.opened) Qt.callLater(function() { root.focusOutput(root.keyboardOutput) })
  }

  // Reopening usually uses the same wallpaper. Reuse its decoded image and
  // GPU texture; invalidate only when the target file actually changes.
  Process {
    id: wallpaperStamp
    command: ["stat", "-Lc", "%d:%i:%s:%y", root.stateHome + "/omarchy/current/background"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: if (text.trim()) root.wallpaperRevision = Qt.md5(text.trim())
    }
  }

  FileView {
    id: wallpaperWatch
    path: root.stateHome + "/omarchy/current/background"
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: wallpaperStamp.running = true
  }
  // An atomic symlink replacement leaves the old image inode intact. Watch
  // the directory too, so changing wallpapers is seen while closed.
  FileView {
    path: root.stateHome + "/omarchy/current"
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: wallpaperStamp.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") Style.refresh()
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.iconCache = ({}) }
  }

  IpcHandler {
    target: "desktops-overview"
    function status(): string {
      var outputs = []
      for (var name in root.panels) outputs.push(root.panels[name].status())
      return JSON.stringify({ opened: root.opened, openedAt: root.openedAt, openWorkMs: root.openWorkMs,
        desktop: root.selectedDesktop, filter: root.filterText, keyboardOutput: root.keyboardOutput,
        captures: { active: captures.active, views: captures.viewCount, requests: captures.requests,
          ready: captures.ready, preparationMs: captures.preparationMs, missingAtReveal: captures.missingAtReveal }, outputs: outputs })
    }
    function close(): void { root.close() }
    function captureStatus(): string {
      return JSON.stringify(captures.queue.entries.map(function(entry) { return entry.view.status() }))
    }
    function geometry(): string { return JSON.stringify(root.geometry()) }
  }

  Variants {
    model: Quickshell.screens
    delegate: OverviewScreen {
      required property var modelData
      screen: modelData
      manager: root
    }
  }
}
