import QtQuick
import Quickshell.Wayland

ScreencopyView {
  id: root
  required property var scheduler
  property var source: null
  property bool capturing: false
  property int refreshInterval: 200
  property bool captureStopped: false
  readonly property bool captureEnabled: capturing && visible && Boolean(source) && !captureStopped

  // Setting a source starts a full-resolution export even with live: false.
  // Let the shared scheduler start it, including the first frame, so opening
  // the overview cannot launch all of its captures at once.
  captureSource: null
  live: false
  paintCursor: false
  onSourceChanged: { captureSource = null; captureStopped = false }
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
