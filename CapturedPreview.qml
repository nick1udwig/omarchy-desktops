import QtQuick

ShaderEffect {
  id: root
  required property var cache
  required property var toplevel
  property bool capturing: false
  property int refreshInterval: 200
  property var capture: null
  readonly property bool hasContent: Boolean(capture && capture.hasContent)

  // Qt's built-in shader samples a texture provider directly.
  readonly property var source: capture ? capture.texture : null
  opacity: hasContent ? 1 : 0
  Behavior on opacity {
    enabled: !root.cache.scheduler.preparing
    NumberAnimation { duration: 100 }
  }
  Component.onCompleted: capture = cache.acquire(toplevel, root)
  Component.onDestruction: if (cache) cache.release(capture, root)
}
