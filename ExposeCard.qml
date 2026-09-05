import QtQuick
import qs.Commons
import "vendor/expose" as Expose

Expose.WindowCard {
  id: card
  required property Item dragLayer
  readonly property string windowAddress: String(modelData.address || "")
  readonly property var client: modelData.lastIpcObject || ({})
  readonly property int workspaceId: modelData.workspace ? modelData.workspace.id : 0
  interactionsEnabled: false

  Drag.active: pointer.drag.active
  Drag.source: card
  Drag.keys: ["omarchy-window"]
  Drag.hotSpot.x: width / 2
  Drag.hotSpot.y: height / 2
  Drag.supportedActions: Qt.MoveAction

  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: card.inLayout && (card.controller.previewIndex < 0 || card.previewed)
    hoverEnabled: true
    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    drag.target: card
    onEntered: {
      card.hovered = true
      card.controller.takeKeyboard()
      card.controller.hoveredIndex = card.slot
      card.controller.selectedIndex = card.slot
    }
    onExited: {
      card.hovered = false
      if (card.controller.hoveredIndex === card.slot) card.controller.hoveredIndex = -1
    }
    onPressed: {
      card.controller.takeKeyboard()
      card.controller.manager.draggedWindow = card.windowAddress
    }
    onPositionChanged: if (pressed) card.controller.trackDrag(pointer, mouseX, mouseY)
    onReleased: {
      var moved = drag.active
      if (moved && card.controller.manager.draggedWindow === card.windowAddress) card.Drag.drop()
      card.controller.manager.draggedWindow = ""
      card.x = Qt.binding(function() { return card.layoutRect.x })
      card.y = Qt.binding(function() { return card.layoutRect.y })
      if (!moved) card.controller.activate(card.modelData)
    }
    onCanceled: {
      card.controller.manager.draggedWindow = ""
      card.x = Qt.binding(function() { return card.layoutRect.x })
      card.y = Qt.binding(function() { return card.layoutRect.y })
    }
  }

  states: State {
    when: pointer.drag.active
    ParentChange { target: card; parent: card.dragLayer }
    PropertyChanges { card.z: 100; card.opacity: 0.85; card.scale: Math.min(1, Style.space(190) / Math.max(1, card.width)) }
  }
}
