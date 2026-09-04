import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "."

Item {
  id: root
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property bool opened: false
  property int selectedDesktop: 1
  property int selectedMonitor: 0
  property int selectedSlot: 1
  property bool dragging: false
  property string draggedWindow: ""
  property real dragY: 0
  property string overviewOutput: ""

  function open(payloadJson) {
    overviewOutput = DesktopState.focusedMonitor
    selectedDesktop = DesktopState.current
    selectedSlot = 1
    selectedMonitor = Math.max(0, DesktopState.monitors.findIndex(function(m) { return m.name === DesktopState.focusedMonitor }))
    var desktop = DesktopState.desktops[selectedDesktop - 1]
    var output = DesktopState.monitors[selectedMonitor]
    if (desktop && output && desktop.outputs[output.name]) selectedSlot = desktop.outputs[output.name].selected
    DesktopState.error = ""
    Hyprland.refreshToplevels()
    opened = true
    Qt.callLater(function() { keyboard.forceActiveFocus(); root.revealSelection() })
  }

  function close() { opened = false; dragging = false; draggedWindow = "" }

  function dragPosition(item, x, y) {
    dragY = item.mapToItem(keyboard, x, y).y
  }

  function activate(desktop, output, slot) {
    DesktopState.switchTo(desktop, output, slot)
    close()
  }

  function focusWindow(address) {
    DesktopState.focusWindow(address)
    close()
  }

  function geometry() {
    var result = []
    function visit(item) {
      if (item.visible && ("windowAddress" in item || "workspaceId" in item)) {
        var point = item.mapToItem(keyboard, 0, 0)
        result.push({
          x: point.x + (panel.screen ? panel.screen.x : 0), y: point.y + (panel.screen ? panel.screen.y : 0),
          width: item.width, height: item.height,
          window: item.windowAddress || "", preview: item.hasPreview || false,
          workspace: item.workspaceId || 0, desktop: item.desktopId || 0, slot: item.slotNumber || 0,
          output: item.output ? item.output.name : "", client: item.client || null
        })
      }
      if (item.children) for (var i = 0; i < item.children.length; i++) visit(item.children[i])
    }
    visit(keyboard)
    return JSON.stringify(result)
  }

  function revealSelection() {
    var item = rows.itemAt(selectedDesktop - 1)
    if (!item) return
    if (item.y < scroll.contentY) scroll.contentY = item.y
    else if (item.y + item.height > scroll.contentY + scroll.height)
      scroll.contentY = Math.max(0, item.y + item.height - scroll.height)
  }

  Timer {
    interval: 500
    running: root.opened && !root.dragging
    repeat: true
    onTriggered: Hyprland.refreshToplevels()
  }

  Timer {
    interval: 16
    running: root.opened && root.dragging
    repeat: true
    onTriggered: {
      var edge = Style.space(50)
      var direction = root.dragY < scroll.y + edge ? -1 : (root.dragY > scroll.y + scroll.height - edge ? 1 : 0)
      scroll.contentY = Math.max(0, Math.min(Math.max(0, scroll.contentHeight - scroll.height), scroll.contentY + direction * Style.space(10)))
    }
  }

  Connections {
    target: DesktopState
    function onCurrentChanged() {
      if (root.opened) {
        root.selectedDesktop = DesktopState.current
        Qt.callLater(root.revealSelection)
      }
    }
  }

  IpcHandler {
    target: "desktops-overview"
    function status(): string {
      return JSON.stringify({ opened: root.opened, desktop: root.selectedDesktop, monitor: root.selectedMonitor, slot: root.selectedSlot })
    }
    function close(): void { root.close() }
    function geometry(): string { return root.geometry() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: Quickshell.screens.find(function(s) { return s.name === root.overviewOutput }) || null
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Color.background
    WlrLayershell.namespace: "omarchy-desktop-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Item {
      id: keyboard
      anchors.fill: parent
      focus: root.opened
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) root.close()
        else if (event.key === Qt.Key_Up) root.selectedDesktop = Math.max(1, root.selectedDesktop - 1)
        else if (event.key === Qt.Key_Down) root.selectedDesktop = Math.min(DesktopState.desktops.length, root.selectedDesktop + 1)
        else if (event.key === Qt.Key_Left) root.selectedSlot = Math.max(1, root.selectedSlot - 1)
        else if (event.key === Qt.Key_Right) {
          var desktop = DesktopState.desktops[root.selectedDesktop - 1]
          var monitor = DesktopState.monitors[root.selectedMonitor]
          var entry = desktop && monitor ? desktop.outputs[monitor.name] : null
          root.selectedSlot = Math.min(entry ? entry.slots.length : 10, root.selectedSlot + 1)
        }
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
          root.selectedMonitor = (root.selectedMonitor + (event.modifiers & Qt.ShiftModifier ? -1 : 1) + DesktopState.monitors.length) % Math.max(1, DesktopState.monitors.length)
        else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
          root.selectedSlot = event.key === Qt.Key_0 ? 10 : event.key - Qt.Key_0
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          var output = DesktopState.monitors[root.selectedMonitor]
          if (output) root.activate(root.selectedDesktop, output.name, root.selectedSlot)
        } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) DesktopState.add()
        else { event.accepted = false; return }
        event.accepted = true
        root.revealSelection()
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(28)
        spacing: Style.space(18)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(16)
          Text {
            text: "Desktops"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
          }
          Text {
            Layout.fillWidth: true
            text: "↑ ↓  Desktop     ← →  Workspace     Tab  Monitor     Enter  Open     Esc  Close"
            color: Color.foreground
            opacity: 0.55
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          Rectangle {
            implicitWidth: Style.space(135)
            implicitHeight: Style.space(36)
            radius: Style.space(6)
            color: addMouse.containsMouse ? Qt.alpha(Color.accent, 0.3) : Qt.alpha(Color.accent, 0.15)
            Text { anchors.centerIn: parent; text: "+ New desktop"; color: Color.foreground; font.pixelSize: Style.font.body }
            MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: DesktopState.add() }
          }
        }

        Text {
          visible: !DesktopState.enabled || DesktopState.error !== ""
          text: DesktopState.error || "Desktop management is not active in this session."
          color: Color.foreground
          font.pixelSize: Style.font.body
        }

        Flickable {
          id: scroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: content.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: content
            width: scroll.width
            spacing: Style.space(20)

            Repeater {
              id: rows
              model: DesktopState.desktops.length

              Rectangle {
                id: desktopRow
                required property int index
                readonly property int desktopId: index + 1
                readonly property var desktop: DesktopState.desktops[index]
                width: content.width
                height: rowContents.implicitHeight + Style.space(28)
                radius: Style.space(8)
                color: Qt.alpha(Color.foreground, desktopId === DesktopState.current ? 0.055 : 0.025)
                border.width: 1
                border.color: desktopId === root.selectedDesktop ? Qt.alpha(Color.accent, 0.65) : Qt.alpha(Color.foreground, 0.08)

                ColumnLayout {
                  id: rowContents
                  anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(14) }
                  spacing: Style.space(12)

                  RowLayout {
                    TextInput {
                      id: desktopName
                      Layout.preferredWidth: Math.min(Style.space(300), desktopRow.width / 2)
                      text: desktopRow.desktop ? desktopRow.desktop.name : ""
                      color: Color.foreground
                      font.pixelSize: Style.font.subtitle
                      font.bold: true
                      selectByMouse: true
                      maximumLength: 80
                      clip: true
                      onEditingFinished: {
                        if (text.trim() && desktopRow.desktop && text !== desktopRow.desktop.name)
                          DesktopState.rename(desktopRow.desktopId, text.trim())
                        keyboard.forceActiveFocus()
                      }
                      Keys.onEscapePressed: { text = desktopRow.desktop.name; keyboard.forceActiveFocus() }
                    }
                    Text {
                      text: desktopRow.desktopId === DesktopState.current ? "CURRENT" : ""
                      color: Color.accent
                      font.pixelSize: Style.font.caption
                    }
                    Item { Layout.fillWidth: true }
                    Text { text: "Drag windows to move them"; color: Color.foreground; opacity: 0.4; font.pixelSize: Style.font.caption }
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(16)
                    Repeater {
                      model: DesktopState.monitors.length
                      ColumnLayout {
                        id: monitorColumn
                        required property int index
                        readonly property var monitor: DesktopState.monitors[index]
                        readonly property var slots: DesktopState.workspaceSlots(desktopRow.desktopId, monitor.name,
                          root.selectedDesktop === desktopRow.desktopId && root.selectedMonitor === index ? root.selectedSlot : 0)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: Style.space(8)
                        Text {
                          text: monitorColumn.monitor.name
                          color: Color.foreground
                          opacity: root.selectedMonitor === monitorColumn.index ? 0.9 : 0.5
                          font.pixelSize: Style.font.caption
                        }
                        GridLayout {
                          Layout.fillWidth: true
                          columns: monitorColumn.width >= Style.space(470) ? 3 : 2
                          columnSpacing: Style.space(8)
                          rowSpacing: Style.space(8)
                          Repeater {
                            model: monitorColumn.slots.length
                            WorkspaceTile {
                              required property int index
                              readonly property var slot: monitorColumn.slots[index]
                              Layout.fillWidth: true
                              Layout.preferredWidth: 1
                              Layout.preferredHeight: Math.max(Style.space(100), Math.min(Style.space(165), width * 0.72))
                              overview: root
                              dragLayer: dragSurface
                              desktopId: desktopRow.desktopId
                              output: monitorColumn.monitor
                              workspaceId: slot.id
                              slotNumber: slot.slot
                              current: desktopRow.desktopId === DesktopState.current && slot.selected
                              selected: desktopRow.desktopId === root.selectedDesktop && monitorColumn.index === root.selectedMonitor && slot.slot === root.selectedSlot
                              capturing: root.opened && desktopRow.y + desktopRow.height >= scroll.contentY && desktopRow.y <= scroll.contentY + scroll.height
                              onActivated: root.activate(desktopId, output.name, slotNumber)
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      Item { id: dragSurface; anchors.fill: parent; z: 100 }
    }
  }
}
