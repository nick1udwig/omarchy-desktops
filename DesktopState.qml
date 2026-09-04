pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "DesktopModel.js" as Model

Item {
  id: root
  property var snapshot: ({})
  property string error: ""
  property var queue: []
  readonly property bool enabled: snapshot.enabled === true
  readonly property int current: snapshot.current || 1
  readonly property var desktops: Model.array(snapshot.desktops)
  readonly property var monitors: Model.array(snapshot.monitors)
  readonly property string focusedMonitor: snapshot.focusedMonitor || ""
  readonly property var toplevels: Hyprland.toplevels.values
  readonly property string statePath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-desktops-" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + ".json"

  function accept(text) {
    try { snapshot = JSON.parse(text) } catch (e) { console.warn("Invalid desktop snapshot:", e) }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.accept(text())
    onFileChanged: reload()
    onLoadFailed: root.snapshot = ({})
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // Also pick up enabling after shell startup, when there was no file to
      // watch, and disabling the controller on a configuration reload.
      if (event.name === "custom" || event.name === "configreloaded") stateFile.reload()
    }
  }

  function command(expression) {
    error = ""
    queue = queue.concat([expression])
    next()
  }

  function next() {
    if (action.running || queue.length === 0) return
    action.command = ["hyprctl", "eval", "assert(o.desktops, 'Desktops are unavailable'); " + queue[0]]
    queue = queue.slice(1)
    action.running = true
  }

  Process {
    id: action
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "ok") {
          root.error = "The desktop action could not be completed."
          console.warn("Desktop action:", text)
        }
      }
    }
    onExited: function(code) {
      if (code !== 0) root.error = "The desktop action could not be completed."
      stateFile.reload()
      Hyprland.refreshToplevels()
      Qt.callLater(root.next)
    }
  }

  function workspaceSlots(desktop, output, visibleSlot) { return Model.slots(snapshot, desktop, output, toplevels, visibleSlot) }
  function switchTo(desktop, output, slot) {
    command("o.desktops.switch(" + desktop + "," + Model.luaString(output) + "," + slot + ")")
  }
  function add() { command("o.desktops.add()") }
  function rename(desktop, name) { command("o.desktops.rename(" + desktop + "," + Model.luaString(name) + ")") }
  function focusWindow(address) { command("o.desktops.focus_window(" + Model.luaString(address) + ")") }
  function move(address, desktop, output, slot) {
    command("o.desktops.move(" + desktop + "," + Model.luaString(output) + "," + slot + "," + Model.luaString(address) + ",false)")
  }
}
