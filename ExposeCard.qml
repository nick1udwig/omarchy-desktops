import QtQuick
import qs.Commons
import "vendor/expose" as Expose

Expose.WindowCard {
  id: card
  readonly property string windowAddress: String(modelData.address || "")
  readonly property int workspaceId: modelData.workspace ? modelData.workspace.id : 0
  readonly property bool interactive: inLayout && (controller.previewIndex < 0 || previewed)
  readonly property size dragSize: Qt.size(Style.space(190), Math.max(1, Math.round(Style.space(190) * height / Math.max(1, width))))
  property var dragImage: null

  function beginDrag() {
    controller.manager.beginDrag(windowAddress)
    // Native drag images cross Wayland surfaces; moving a QML item cannot.
    // Read back a small, single snapshot, never a full-size live texture.
    var started = grabToImage(function(result) {
      if (!pointer.active || card.controller.manager.draggedWindow !== card.windowAddress) return
      card.dragImage = result
      card.Drag.imageSource = result.url
      card.Drag.active = true
    }, dragSize)
    if (!started) controller.manager.finishDrag(windowAddress, false)
  }

  Drag.dragType: Drag.Automatic
  Drag.source: card
  Drag.mimeData: { var data = ({}); data[controller.manager.dragMimeType] = windowAddress; return data }
  Drag.hotSpot: Qt.point(dragSize.width / 2, dragSize.height / 2)
  Drag.supportedActions: Qt.MoveAction
  Drag.proposedAction: Qt.MoveAction
  Drag.onDragFinished: function(action) {
    card.controller.manager.finishDrag(card.windowAddress, action === Qt.MoveAction)
    card.dragImage = null
  }
  Component.onDestruction: controller.manager.finishDrag(windowAddress, false)

  HoverHandler {
    enabled: card.interactive
    cursorShape: Qt.OpenHandCursor
    onHoveredChanged: {
      card.hovered = hovered
      if (hovered && !card.controller.manager.draggedWindow) {
        card.controller.takeKeyboard()
        card.controller.selectedIndex = card.slot
      }
    }
  }
  TapHandler {
    enabled: card.interactive
    onPressedChanged: if (pressed) card.controller.takeKeyboard()
    onTapped: card.controller.activate(card.modelData)
  }
  DragHandler {
    id: pointer
    target: null
    enabled: card.interactive
    onActiveChanged: {
      if (active) card.beginDrag()
      else {
        card.Drag.active = false
        if (!card.dragImage) card.controller.manager.finishDrag(card.windowAddress, false)
      }
    }
  }
}
