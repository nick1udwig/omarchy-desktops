// Opt-in live stress fixture. Fixed-size windows avoid shrinking tiled apps.
// Start with one; the controller must verify it floats before raising count.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root
  property int count: 1
  property int clicks: 0
  property int keys: 0
  Variants {
    model: Array.from({length: root.count}, function(_, i) { return i })
    delegate: FloatingWindow {
      required property int modelData
      title: "Desktop performance probe " + modelData
      screen: Quickshell.screens[modelData % Quickshell.screens.length]
      implicitWidth: 320
      implicitHeight: 200
      minimumSize: Qt.size(320, 200)
      maximumSize: Qt.size(320, 200)
      color: Qt.hsla((modelData * 0.173) % 1, 0.6, 0.25, 1)
      Text { anchors.centerIn: parent; text: "Preview " + modelData; color: "white"; font.pixelSize: 24 }
      MouseArea { anchors.fill: parent; onClicked: root.clicks++ }
      Item { focus: true; Keys.onPressed: function(event) { root.keys++; event.accepted = true } }
    }
  }
  IpcHandler {
    target: "desktops-perf-probes"
    function setCount(value: int): void { root.count = Math.max(1, Math.min(64, value)) }
    function status(): string { return JSON.stringify({windows:root.count, clicks:root.clicks, keys:root.keys}) }
    function quit(): void { Qt.quit() }
  }
  Timer { interval: 120000; running: true; onTriggered: Qt.quit() }
}
