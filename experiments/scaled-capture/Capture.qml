import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "production" as Desktops

ShellRoot {
  id: root
  property var selected: []
  property double startedAt: 0
  property double firstFrameAt: 0
  property int missingAtReveal: -1
  property string saved: ""
  readonly property var candidates: Hyprland.toplevels.values.filter(function(top) { return top.title.indexOf("Capture probe ") === 0 })
  function begin() {
    if (selected.length) throw new Error("Reset captures before beginning a cold sample")
    firstFrameAt = 0
    missingAtReveal = -1
    saved = ""
    startedAt = Date.now()
    captureScheduler.active = true
    captureScheduler.preparing = true
    captureScheduler.ready = false
    captureScheduler.startedAt = startedAt
    selected = candidates.slice()
    captureScheduler.schedule()
  }
  function snapshot() {
    var sizes = []
    var pending = 0
    for (var key in previewCache.sources) {
      var producer = previewCache.sources[key]
      if (!producer.hasContent) pending++
      // Read the native ScreencopyView size without changing the production API.
      for (var i = 0; i < producer.children.length; ++i) {
        var child = producer.children[i]
        if (child.sourceSize !== undefined)
          sizes.push([child.sourceSize.width, child.sourceSize.height])
      }
    }
    return { candidates: candidates.length, selected: selected.length, views: captureScheduler.viewCount,
      ready: captureScheduler.ready, pending: pending, missingAtReveal: missingAtReveal,
      preparationMs: captureScheduler.preparationMs, firstFrameMs: firstFrameAt ? firstFrameAt - startedAt : null,
      sizes: sizes, pixelRatio: previewCache.pixelRatio, saved: saved }
  }
  PanelWindow {
    id: panel
    implicitWidth: 2560
    implicitHeight: 1440
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    Desktops.CaptureScheduler {
      id: captureScheduler
      refreshAllowed: false
      onReadyChanged: if (ready) root.missingAtReveal = queue.pending()
    }
    Desktops.CaptureCache {
      id: previewCache
      scheduler: captureScheduler
      pixelRatio: panel.screen ? panel.screen.devicePixelRatio : 1
    }
    Item {
      id: overview
      anchors.fill: parent
      opacity: captureScheduler.ready ? 1 : 0
      Rectangle { anchors.fill: parent; color: "#202020" }
      Grid {
        anchors.fill: parent
        columns: 8
        Repeater {
          id: previews
          model: root.selected
          delegate: Desktops.CapturedPreview {
            required property var modelData
            width: 320
            height: 180
            cache: previewCache
            toplevel: modelData
            capturing: true
          }
        }
      }
    }
    Connections {
      target: panel.contentItem.Window.window
      function onFrameSwapped() {
        if (captureScheduler.ready && !root.firstFrameAt) root.firstFrameAt = Date.now()
      }
    }
  }
  IpcHandler {
    target: "capture-benchmark"
    function status(): string { return JSON.stringify(root.snapshot()) }
    function begin(): void { root.begin() }
    function close(): void { captureScheduler.active = false; captureScheduler.ready = false }
    function reopen(): void {
      if (!root.selected.length) throw new Error("No retained previews")
      root.firstFrameAt = 0
      root.missingAtReveal = -1
      root.startedAt = Date.now()
      captureScheduler.active = true
      captureScheduler.begin()
    }
    function reset(): void { captureScheduler.active = false; captureScheduler.ready = false; root.selected = [] }
    function save(path: string): void {
      if (!root.firstFrameAt || root.missingAtReveal !== 0) throw new Error("Preview is not complete")
      overview.grabToImage(function(result) {
        if (result.saveToFile(path)) root.saved = path
      })
    }
    function quit(): void { Qt.quit() }
  }
  Timer { interval: 240000; running: true; onTriggered: Qt.quit() }
}
