import QtQuick
import QtQml.Models
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
  property string filterText: ""
  property string keyboardOutput: ""
  property string draggedWindow: ""
  property int modelRevision: 0
  property int wallpaperRevision: 0
  property var panels: ({})
  property var iconCache: ({})
  readonly property var toplevels: Hyprland.toplevels.values
  readonly property int selectedDesktop: DesktopState.current
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string wallpaper: "file://" + stateHome + "/omarchy/current/background?desktops=" + wallpaperRevision

  function open(payloadJson) {
    Style.refresh()
    filterText = ""
    draggedWindow = ""
    keyboardOutput = DesktopState.focusedMonitor || (Quickshell.screens[0] ? Quickshell.screens[0].name : "")
    DesktopState.error = ""
    wallpaperRevision++
    Hyprland.refreshToplevels()
    opened = true
    modelRevision++
    Qt.callLater(function() { root.focusOutput(root.keyboardOutput) })
  }

  function close() { opened = false; draggedWindow = "" }

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
    for (var name in panels) if (panels[name].visible) result = result.concat(panels[name].geometry())
    return result
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { if (root.opened) root.modelRevision++ }
  }

  Instantiator {
    model: root.opened ? Hyprland.toplevels : null
    delegate: Connections {
      required property var modelData
      target: modelData
      function onWorkspaceChanged() { root.modelRevision++ }
      function onMonitorChanged() { root.modelRevision++ }
      function onLastIpcObjectChanged() { root.modelRevision++ }
      function onWaylandHandleChanged() { root.modelRevision++ }
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
      return JSON.stringify({ opened: root.opened, desktop: root.selectedDesktop, filter: root.filterText, keyboardOutput: root.keyboardOutput, outputs: outputs })
    }
    function close(): void { root.close() }
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
