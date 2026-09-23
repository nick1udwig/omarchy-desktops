import QtQuick
import QtQuick.Window
import Quickshell.Wayland
import "vendor/expose/WindowModel.js" as WindowModel

Item {
  id: root
  required property var scheduler
  required property var toplevel
  property real pixelRatio: 1
  property var consumers: []
  readonly property var activeConsumers: consumers.filter(function(view) { return view.capturing })
  readonly property var source: WindowModel.waylandFor(toplevel)
  readonly property var windowSize: WindowModel.ipcFor(toplevel).size || []
  readonly property bool validSize: windowSize[0] > 0 && windowSize[1] > 0
  property bool captureStopped: false
  property bool textureReady: false
  readonly property var renderWindow: root.Window.window
  onRenderWindowChanged: {
    // A monitor-layout remap discards the scene graph. Retained native
    // buffers must be rendered into the new context before revealing again.
    if (!renderWindow && textureReady) {
      textureReady = false
      if (scheduler) scheduler.invalidate()
    }
    if (renderWindow && copy.hasContent) texture.scheduleUpdate()
  }
  readonly property bool captureEnabled: activeConsumers.length > 0 && Boolean(source) && validSize && !captureStopped
  readonly property bool awaitingMetadata: activeConsumers.length > 0 && Boolean(source)
    && windowSize.length < 2 && !captureStopped
  readonly property bool captureStarted: Boolean(copy.captureSource)
  readonly property bool hasContent: copy.hasContent && textureReady
  readonly property int refreshInterval: activeConsumers.reduce(function(rate, view) { return Math.min(rate, view.refreshInterval) }, 1000)
  readonly property alias texture: texture

  function status() {
    return { enabled: captureEnabled, started: captureStarted, frame: copy.hasContent,
      texture: textureReady, stopped: captureStopped,
      width: width, height: height }
  }

  // Render only at the largest displayed size. Both consumers sample this
  // texture directly; neither requests another full-window compositor export.
  width: consumers.reduce(function(size, view) { return Math.max(size, view.width) }, 1)
  height: consumers.reduce(function(size, view) { return Math.max(size, view.height) }, 1)
  // Keep the producer outside the surface while its texture is prepared.
  // Opacity/visibility hiding would stop Qt from painting it.
  x: -width - 1
  y: -height - 1
  onSourceChanged: { copy.captureSource = null; captureStopped = false }
  onValidSizeChanged: { if (!validSize) copy.captureSource = null; captureStopped = false }
  onCaptureEnabledChanged: if (captureEnabled) scheduler.schedule()

  function refresh() {
    if (!captureEnabled) return false
    // Draft Quickshell API: ask the compositor to render directly at the
    // largest consumer's physical texture size. Stock Quickshell keeps its
    // native-resolution path. Apply only when requesting a frame, so layout
    // animation cannot create an extra stream of capture requests.
    if (copy.captureSize !== undefined) copy.captureSize = texture.textureSize
    if (copy.captureSource !== source) { copy.captureSource = source; return true }
    if (!copy.hasContent) return false
    copy.captureFrame()
    return true
  }

  ScreencopyView {
    id: copy
    anchors.fill: parent
    live: false
    paintCursor: false
    onStopped: root.captureStopped = true
    onHasContentChanged: {
      root.textureReady = false
      if (hasContent) texture.scheduleUpdate()
    }
  }
  ShaderEffectSource {
    id: texture
    anchors.fill: parent
    sourceItem: copy
    hideSource: true
    live: true
    // Small allocation steps avoid reallocating on every animation pixel.
    textureSize: Qt.size(Math.ceil(root.width * root.pixelRatio / 64) * 64, Math.ceil(root.height * root.pixelRatio / 64) * 64)
    onTextureSizeChanged: {
      if (root.scheduler.preparing) root.textureReady = false
      if (copy.hasContent) scheduleUpdate()
    }
    // hasContent alone precedes GPU import. Wait for the texture to be drawn.
    onScheduledUpdateCompleted: root.textureReady = copy.hasContent
  }

  Component.onCompleted: scheduler.registerView(root)
  Component.onDestruction: if (scheduler) scheduler.unregisterView(root)
}
