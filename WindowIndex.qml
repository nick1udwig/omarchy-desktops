import QtQuick
import QtQml.Models
import "OverviewModel.js" as Model
import "vendor/expose/WindowModel.js" as WindowModel

// Observe primitive membership fields, not entire IPC objects. A clients
// refresh can replace hundreds of metadata objects without changing a list.
Item {
  id: root
  property var snapshot: ({})
  property var toplevels: []
  property var value: ({})
  property bool dirty: true
  function schedule() { dirty = true; Qt.callLater(rebuild) }
  function rebuild() {
    if (!dirty) return
    dirty = false
    value = Model.indexWindows(snapshot, toplevels)
  }
  onSnapshotChanged: schedule()
  onToplevelsChanged: schedule()
  Component.onCompleted: schedule()

  Instantiator {
    model: root.toplevels
    delegate: QtObject {
      required property var modelData
      readonly property bool eligible: WindowModel.isEligible(modelData)
      readonly property string output: modelData && modelData.monitor ? String(modelData.monitor.name || "") : ""
      readonly property int workspace: modelData && modelData.workspace ? modelData.workspace.id : 0
      readonly property bool hasWorkspace: Boolean(modelData && modelData.workspace)
      readonly property bool pinned: WindowModel.ipcFor(modelData).pinned === true
      onEligibleChanged: root.schedule()
      onOutputChanged: root.schedule()
      onWorkspaceChanged: root.schedule()
      onHasWorkspaceChanged: root.schedule()
      onPinnedChanged: root.schedule()
    }
  }
}
