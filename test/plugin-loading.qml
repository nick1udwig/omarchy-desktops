import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

ShellRoot {
  id: test
  Timer {
    interval: 0
    running: true
    onTriggered: {
      var failed = false
      var files = ["DesktopBar.qml", "DesktopThumbnail.qml", "ExposeCard.qml", "CaptureCache.qml", "WindowIndex.qml"]
      for (var name of files) {
        var component = Qt.createComponent("qs://" + Quickshell.env("OMARCHY_DESKTOPS_PATH") + "/" + name, Component.PreferSynchronous)
        if (component.status !== Component.Ready) {
          console.error("not ok - external plugin component " + name + ": " + component.errorString())
          failed = true
        } else console.log("ok - external plugin component loads: " + name)
      }
      var thumbnailType = Qt.createComponent("qs://" + Quickshell.env("OMARCHY_DESKTOPS_PATH") + "/DesktopThumbnail.qml", Component.PreferSynchronous)
      if (thumbnailType.status === Component.Ready) {
        var thumbnail = thumbnailType.createObject(test, {
          manager: {wallpaper: "", dragMimeType: "application/x-omarchy-window", panels: {}},
          output: {name: "test", width: 1280, height: 720},
          captureCache: null, desktopId: 1, width: 220
        })
        if (!thumbnail || String(thumbnail.color) !== String(Commons.Color.menu.selectedBackground)) {
          console.error("not ok - desktop thumbnail uses the Omarchy menu palette")
          failed = true
        } else console.log("ok - desktop thumbnail uses the Omarchy menu palette")
        if (thumbnail) thumbnail.destroy()
      }
      Qt.exit(failed ? 1 : 0)
    }
  }
}
