import QtQuick
import Quickshell.Hyprland
import qs.Commons
import "."

Rectangle {
  id: root
  required property var overview
  required property Item dragLayer
  required property int desktopId
  required property var output
  required property int workspaceId
  required property int slotNumber
  property bool selected: false
  property bool current: false
  property bool capturing: false
  signal activated()
  radius: Style.space(5)
  color: Qt.alpha(Color.foreground, 0.055)
  border.width: selected || drop.containsDrag ? 2 : 1
  border.color: selected || drop.containsDrag ? Color.accent : Qt.alpha(Color.foreground, current ? 0.5 : 0.12)

  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activated() }

  Item {
    id: windows
    anchors { fill: parent; margins: Style.space(5); bottomMargin: Style.space(26) }
    clip: false
    Repeater {
      model: Hyprland.toplevels
      Loader {
        required property var modelData
        active: (root.capturing || root.overview.draggedWindow === modelData.address) && modelData.workspace !== null && modelData.workspace.id === root.workspaceId
        sourceComponent: WindowPreview {
          toplevel: modelData
          output: root.output
          areaWidth: windows.width
          areaHeight: windows.height
          overview: root.overview
          dragLayer: root.dragLayer
        }
      }
    }
  }

  Text {
    anchors { left: parent.left; bottom: parent.bottom; margins: Style.space(7) }
    text: String(root.slotNumber === 10 ? 0 : root.slotNumber)
    color: root.current ? Color.accent : Color.foreground
    font.pixelSize: Style.font.caption
    font.bold: root.current
  }

  DropArea {
    id: drop
    anchors.fill: parent
    keys: ["omarchy-window"]
    onDropped: function(event) {
      if (event.source && event.source.windowAddress) {
        DesktopState.move(event.source.windowAddress, root.desktopId, root.output.name, root.slotNumber)
        event.acceptProposedAction()
      }
    }
  }
}
