import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
  id: root
  property var probes: []
  property string saved: ""
  readonly property var candidates: Hyprland.toplevels.values.filter(function(top) { return top.title.indexOf("Capture probe ") === 0 })
  PanelWindow {
    id: panel
    implicitWidth: 2560
    implicitHeight: 1440
    color: "black"
    exclusionMode: ExclusionMode.Ignore
    Item { id: overview; anchors.fill: parent }
  }
  Component {
    id: probeComponent
    ScreencopyView {
      property int frames: 0
      property int drops: 0
      width: 320
      height: 180
      live: false
      onFrameCaptured: frames++
      onHasContentChanged: if (frames && !hasContent) drops++
    }
  }
  IpcHandler {
    target: "capture-benchmark"
    function begin(): void {
      var sizes = [[0, 0], [320, 180], [640, 360], [0, 128], [128, 0], [1, 1], [9000, 9000], [319, 173], [-1, -1]]
      var created = []
      for (var i = 0; i < sizes.length; i++) {
        var probe = probeComponent.createObject(overview, {
          x: (i % 8) * 320, y: Math.floor(i / 8) * 180,
          captureSize: Qt.size(sizes[i][0], sizes[i][1])
        })
        probe.captureSource = root.candidates[0].wayland
        created.push(probe)
      }
      root.probes = created
    }
    function status(): string {
      return JSON.stringify({ candidates: root.candidates.length, saved: root.saved, probes: root.probes.map(function(p) {
        return { size: [p.sourceSize.width, p.sourceSize.height], frames: p.frames, drops: p.drops }
      }) })
    }
    function resize(index: int, width: int, height: int): void {
      var p = root.probes[index]
      p.captureSize = Qt.size(width, height)
      if (!p.hasContent) throw new Error("Size change discarded existing content")
      p.captureFrame()
    }
    function race(index: int): void {
      var p = root.probes[index]
      p.captureSize = Qt.size(160, 90)
      p.captureFrame()
      p.captureSize = Qt.size(800, 450)
      p.captureFrame() // An in-flight request is coalesced, not mutated.
      if (!p.hasContent) throw new Error("In-flight size change discarded content")
    }
    function refresh(index: int): void { root.probes[index].captureFrame() }
    function save(path: string): void {
      overview.grabToImage(function(result) {
        if (result.saveToFile(path)) root.saved = path
      })
    }
    function cancel(): void {
      var p = probeComponent.createObject(overview, { captureSize: Qt.size(64, 64) })
      p.captureSource = root.candidates[0].wayland
      p.destroy()
    }
  }
  Timer { interval: 240000; running: true; onTriggered: Qt.quit() }
}
