import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "."

BarWidget {
  id: root
  moduleName: "nick.desktops"
  readonly property string output: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : DesktopState.focusedMonitor
  readonly property var slots: DesktopState.workspaceSlots(DesktopState.current, output)
  implicitWidth: grid.implicitWidth
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    columns: root.vertical ? 1 : root.slots.length + 1
    columnSpacing: Style.space(1)
    rowSpacing: Style.space(2)

    WidgetButton {
      bar: root.bar
      text: "D" + DesktopState.current
      tooltipText: DesktopState.desktops[DesktopState.current - 1] ? DesktopState.desktops[DesktopState.current - 1].name + " · Overview" : "Desktop overview"
      fixedHeight: root.barSize
      onPressed: if (root.bar && root.bar.shell) root.bar.shell.toggle(root.moduleName, "{}")
    }

    Repeater {
      model: root.slots
      WidgetButton {
        required property var modelData
        bar: root.bar
        text: String(modelData.slot === 10 ? 0 : modelData.slot)
        opacity: modelData.selected || modelData.occupied ? 1 : 0.45
        active: modelData.selected
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: DesktopState.switchTo(DesktopState.current, root.output, modelData.slot)
      }
    }
  }
}
