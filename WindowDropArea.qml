import QtQuick

DropArea {
  id: root
  required property var manager
  required property int desktopId
  required property string outputName
  keys: [manager.dragMimeType]
  function track(event) {
    var panel = manager.panels[outputName]
    if (panel) panel.trackDrag(root, event.x, event.y)
  }
  onEntered: function(event) {
    event.accepted = manager.dropTarget(desktopId, outputName) !== null
    if (event.accepted) track(event)
  }
  onPositionChanged: function(event) { track(event) }
  onExited: { var panel = manager.panels[outputName]; if (panel) panel.dragY = -1 }
  onDropped: function(event) { manager.stageDrop(event, desktopId, outputName) }
}
