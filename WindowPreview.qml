import QtQuick
import Quickshell.Wayland
import qs.Commons
import "DesktopModel.js" as Model

Rectangle {
  id: root
  required property var toplevel
  required property var output
  required property real areaWidth
  required property real areaHeight
  required property var overview
  required property Item dragLayer
  readonly property string windowAddress: toplevel.address
  readonly property bool hasPreview: preview.hasContent
  readonly property var client: toplevel.lastIpcObject || ({})
  readonly property var placement: Model.windowRect(client, output, areaWidth, areaHeight)
  x: placement.x
  y: placement.y
  width: placement.width
  height: placement.height
  color: Color.background
  border.width: 1
  border.color: pointer.containsMouse ? Color.accent : Qt.alpha(Color.foreground, 0.3)
  radius: Style.space(3)

  ScreencopyView {
    id: preview
    anchors { fill: parent; margins: 1 }
    captureSource: root.toplevel.wayland
    live: true
    constraintSize: Qt.size(root.width, root.height)
  }

  Text {
    anchors.centerIn: parent
    width: Math.max(0, parent.width - 8)
    visible: !preview.hasContent
    text: root.client.class || root.toplevel.title || "Window"
    textFormat: Text.PlainText
    color: Color.foreground
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
  }

  Rectangle {
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
    height: Math.min(parent.height, Style.space(19))
    color: Qt.alpha(Color.background, 0.88)
    visible: root.width > Style.space(70) && root.height > Style.space(30)
    Text {
      anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
      text: root.toplevel.title
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Color.foreground
      font.pixelSize: Style.font.caption * 0.85
      verticalAlignment: Text.AlignVCenter
    }
  }

  Drag.active: pointer.drag.active
  Drag.source: root
  Drag.keys: ["omarchy-window"]
  Drag.hotSpot.x: width / 2
  Drag.hotSpot.y: height / 2
  Drag.supportedActions: Qt.MoveAction

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    drag.target: root
    onPressed: {
      root.overview.dragPosition(pointer, mouseX, mouseY)
      root.overview.draggedWindow = root.windowAddress
      root.overview.dragging = true
    }
    onPositionChanged: if (pressed) root.overview.dragPosition(pointer, mouseX, mouseY)
    onReleased: {
      if (drag.active) root.Drag.drop()
      else root.overview.focusWindow(root.windowAddress)
      root.overview.dragging = false
      root.overview.draggedWindow = ""
    }
    onCanceled: {
      root.overview.dragging = false
      root.overview.draggedWindow = ""
    }
  }

  states: State {
    when: pointer.drag.active
    ParentChange { target: root; parent: root.dragLayer }
  }
}
