import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  readonly property int count: Number(Quickshell.env("CAPTURE_COUNT") || 1)
  readonly property int sourceWidth: Number(Quickshell.env("CAPTURE_WIDTH") || 2560)
  readonly property int sourceHeight: Number(Quickshell.env("CAPTURE_HEIGHT") || 1440)
  property bool transparent: Quickshell.env("CAPTURE_TRANSPARENT") === "1"
  Variants {
    model: Array.from({length: root.count}, function(_, i) { return i })
    delegate: FloatingWindow {
      required property int modelData
      title: "Capture probe " + modelData
      implicitWidth: root.sourceWidth
      implicitHeight: root.sourceHeight
      minimumSize: Qt.size(root.sourceWidth, root.sourceHeight)
      maximumSize: minimumSize
      color: root.transparent ? "transparent" : "#ff0000"
      Rectangle { width: parent.width / 2; height: parent.height / 2; color: "#ff0000" }
      Rectangle { x: parent.width / 2; width: parent.width / 2; height: parent.height / 2; color: root.transparent ? "transparent" : "#00ff00" }
      Rectangle { y: parent.height / 2; width: parent.width / 2; height: parent.height / 2; color: "#0000ff" }
      Rectangle { x: parent.width / 2; y: parent.height / 2; width: parent.width / 2; height: parent.height / 2; color: "#ffff00" }
      Text { anchors.centerIn: parent; text: "Window " + modelData; font.pixelSize: 64; color: "white" }
    }
  }
  IpcHandler {
    target: "capture-source"
    function setTransparent(enabled: int): void { root.transparent = enabled !== 0 }
  }
  Timer { interval: 240000; running: true; onTriggered: Qt.quit() }
}
