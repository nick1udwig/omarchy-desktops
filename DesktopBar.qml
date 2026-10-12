import qs.Ui
import "."

BarWidget {
  id: root
  moduleName: "nick1udwig.desktops"
  implicitWidth: desktopButton.implicitWidth
  implicitHeight: desktopButton.implicitHeight

  WidgetButton {
    id: desktopButton
    bar: root.bar
    text: "D" + DesktopState.current
    tooltipText: DesktopState.desktops[DesktopState.current - 1] ? DesktopState.desktops[DesktopState.current - 1].name + " · Overview" : "Desktop overview"
    fixedHeight: root.barSize
    onPressed: if (root.bar && root.bar.shell) root.bar.shell.toggle(root.moduleName, "{}")
  }
}
