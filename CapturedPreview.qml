import QtQuick
import Quickshell.Wayland
import "vendor/expose/WindowModel.js" as WindowModel

ScreencopyView {
  id: root
  required property var scheduler
  property var toplevel: null
  readonly property var source: WindowModel.waylandFor(toplevel)
  readonly property var windowSize: WindowModel.ipcFor(toplevel).size || []
  readonly property bool validSize: windowSize[0] > 0 && windowSize[1] > 0
  property bool capturing: false
  property int refreshInterval: 200
  property bool captureStopped: false
  readonly property bool captureEnabled: capturing && visible && Boolean(source) && validSize && !captureStopped
  readonly property bool captureStarted: Boolean(captureSource)

  // Setting a source starts a full-resolution export even with live: false.
  // The scheduler bounds startup concurrency separately from steady refreshes.
  captureSource: null
  live: false
  paintCursor: false
  opacity: hasContent ? 1 : 0
  Behavior on opacity {
    enabled: !root.scheduler.preparing
    NumberAnimation { duration: 100 }
  }
  onSourceChanged: { captureSource = null; captureStopped = false }
  onValidSizeChanged: { if (!validSize) captureSource = null; captureStopped = false }
  onStopped: captureStopped = true

  function refresh() {
    if (!captureEnabled) return false
    if (captureSource !== source) {
      captureSource = source
      return true
    }
    // A source captures its initial frame automatically. Wait for it before
    // requesting more; a stopped/destroyed stream must not be polled.
    if (!hasContent) return false
    captureFrame()
    return true
  }

  Component.onCompleted: scheduler.registerView(root)
  Component.onDestruction: if (scheduler) scheduler.unregisterView(root)
}
