import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "DesktopModel.js" as Geometry
import "OverviewModel.js" as Model
import "."

BorderSurface {
  id: tile
  required property var manager
  required property var output
  required property int desktopId
  property bool capturing: false
  readonly property var desktop: DesktopState.desktops[desktopId - 1]
  readonly property var workspace: Model.selectedWorkspace(DesktopState.snapshot, desktopId, output.name)
  readonly property int workspaceId: workspace ? workspace.id : 0
  readonly property int slotNumber: workspace ? workspace.slot : 1
  readonly property bool current: desktopId === DesktopState.current
  readonly property var windowsSource: {
    if (!manager.opened) return []
    return Model.windowsFor(DesktopState.snapshot, desktopId, output.name, manager.toplevels, "")
  }
  property var windows: []
  function syncWindows() { if (!Model.sameWindows(windows, windowsSource)) windows = windowsSource }
  onWindowsSourceChanged: syncWindows()
  Component.onCompleted: syncWindows()
  readonly property real thumbHeight: Math.max(Style.space(86), Math.min(Style.space(155), (width - Style.space(20)) * output.height / Math.max(1, output.width)))
  readonly property real previewRadius: Math.max(0, Style.cornerRadius - Style.spacing.md)
  readonly property bool highlighted: current || drop.containsDrag
  property bool renaming: false
  height: thumbHeight + Style.space(60)
  radius: Style.cornerRadius
  color: drop.containsDrag ? Style.pressedFillFor(Color.menu.text, Color.menu.selectedText)
    : current ? Color.menu.selectedBackground
    : pointer.containsMouse ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText) : "transparent"
  borderSpec: highlighted ? Border.surfaceSpec("menu", "selected-border", Color.menu.selectedText, Style.selectedBorderWidth)
    : pointer.containsMouse ? Border.controlSpec("hover-cursor", Color.menu.text, Color.menu.selectedText) : Border.none()
  Behavior on color { ColorAnimation { duration: 120 } }

  Item {
    id: thumbnailArea
    anchors { top: parent.top; left: parent.left; right: parent.right; margins: Style.space(10) }
    height: tile.thumbHeight
    PreviewClip {
      id: mini
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height * tile.output.width / Math.max(1, tile.output.height))
      height: Math.min(parent.height, parent.width * tile.output.height / Math.max(1, tile.output.width))
      radius: tile.previewRadius
      Rectangle { anchors.fill: parent; color: Color.background }
      Image { anchors.fill: parent; source: tile.manager.wallpaper; fillMode: Image.PreserveAspectCrop }
      Repeater {
        model: tile.capturing ? tile.windows : []
        delegate: PreviewClip {
          required property var modelData
          readonly property var placement: Geometry.windowRect(modelData.lastIpcObject || ({}), tile.output, mini.width, mini.height)
          x: placement.x
          y: placement.y
          width: placement.width
          height: placement.height
          radius: Style.cornerRadius * mini.width / Math.max(1, tile.output.width)
          Rectangle { anchors.fill: parent; color: Color.background }
          CapturedPreview {
            anchors.fill: parent
            scheduler: tile.manager.captureScheduler
            source: modelData.wayland
            capturing: tile.capturing
            refreshInterval: 1000
          }
        }
      }
    }
    BorderSurface {
      anchors.fill: mini
      radius: mini.radius
      color: "transparent"
      borderSpec: tile.highlighted ? Border.hyprlandActiveSpec(Color.menu.selectedText, Style.focusBorderWidth)
        : Border.controlSpec("normal", Color.menu.text, Color.menu.selectedText)
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.manager.chooseDesktop(tile.desktopId, tile.output.name)
  }

  RowLayout {
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Style.space(12) }
    spacing: Style.space(6)
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(3)
      TextInput {
        id: nameInput
        Layout.fillWidth: true
        text: tile.desktop ? tile.desktop.name : "Desktop " + tile.desktopId
        readOnly: !tile.renaming
        color: tile.highlighted ? Color.menu.selectedText : Color.menu.text
        selectionColor: Style.selectionFillFor(Color.menu.text, Color.menu.selectedText)
        selectedTextColor: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        font.bold: tile.current
        clip: true
        maximumLength: 80
        selectByMouse: tile.renaming
        onEditingFinished: {
          if (tile.renaming && text.trim() && tile.desktop && text.trim() !== tile.desktop.name)
            DesktopState.rename(tile.desktopId, text.trim())
          tile.renaming = false
          tile.manager.focusOutput(tile.output.name)
        }
        Keys.onEscapePressed: {
          text = tile.desktop ? tile.desktop.name : ""
          tile.renaming = false
          tile.manager.focusOutput(tile.output.name)
        }
        MouseArea {
          anchors.fill: parent
          enabled: !tile.renaming
          cursorShape: Qt.PointingHandCursor
          onClicked: tile.manager.chooseDesktop(tile.desktopId, tile.output.name)
          onDoubleClicked: { tile.renaming = true; nameInput.forceActiveFocus(); nameInput.selectAll() }
        }
      }
      Text {
        text: "Workspace " + tile.slotNumber + "  ·  " + tile.windows.length + (tile.windows.length === 1 ? " window" : " windows")
        color: Color.menu.text
        opacity: 0.65
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      visible: tile.current
      text: "✓"
      color: Color.menu.selectedText
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }
  }

  DropArea {
    id: drop
    anchors.fill: parent
    keys: ["omarchy-window"]
    onDropped: function(event) {
      if (!tile.workspace || !event.source || !event.source.windowAddress) return
      DesktopState.move(event.source.windowAddress, tile.desktopId, tile.output.name, tile.slotNumber)
      event.acceptProposedAction()
    }
  }
}
