import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "vendor/expose/WindowModel.js" as WindowModel
import "vendor/expose/Layout.js" as ExposeLayout
import "OverviewModel.js" as Model
import "."

PanelWindow { // qmllint disable uncreatable-type
  id: surface
  required property var manager
  readonly property string outputName: screen ? screen.name : ""
  readonly property var output: DesktopState.monitors.find(function(m) { return m.name === surface.outputName })
    || ({name: outputName, x: screen ? screen.x : 0, y: screen ? screen.y : 0, width: width, height: height})
  readonly property bool opened: manager.opened
  readonly property bool acceptsKeyboard: manager.keyboardOutput === outputName
  readonly property var workspace: Model.selectedWorkspace(DesktopState.snapshot, DesktopState.current, outputName)
  readonly property var desktop: DesktopState.desktops[DesktopState.current - 1]
  readonly property var screenToplevelsSource: {
    var needle = String(manager.filterText || "").trim().toLowerCase()
    return needle ? candidates.filter(function(top) { return WindowModel.searchTextFor(top).indexOf(needle) !== -1 }) : candidates
  }
  property var screenToplevels: []
  readonly property var candidates: {
    if (!visible) return []
    return Model.windowsFor(DesktopState.snapshot, DesktopState.current, outputName, manager.toplevels, "")
  }
  property var cardToplevels: []
  property int selectedIndex: 0
  property int previewIndex: -1
  property int previewExitIndex: -1
  property real progress: opened ? 1 : 0
  property real dragY: -1
  readonly property bool motionSettled: progress > 0.99 && manager.draggedWindow === ""
  readonly property int windowFooterHeight: Style.space(40)
  readonly property int previewAnimationDuration: 220
  readonly property int previewAnimationEasing: Easing.OutCubic
  readonly property int previewFadeDuration: 150
  readonly property real sidebarWidth: Math.min(Style.space(238), width * 0.23)
  property bool registered: false
  property bool focusPrimed: false
  readonly property alias captureCache: captureCache
  property real contentOpacity: opened && manager.captureScheduler.ready ? 1 : 0
  Behavior on contentOpacity {
    enabled: !surface.manager.captureScheduler.preparing
    NumberAnimation { duration: Math.max(60, Math.min(100, 190 - surface.manager.captureScheduler.preparationMs)) }
  }

  screen: null
  visible: opened || progress > 0
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.namespace: "omarchy-desktop-overview"
  WlrLayershell.layer: WlrLayer.Overlay
  // Persistent Exclusive focus also grabs pointer input from other monitors.
  // Prime keyboard focus briefly, then let each output receive its own input.
  WlrLayershell.keyboardFocus: !opened || !acceptsKeyboard ? WlrKeyboardFocus.None
    : focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
  onBackingWindowVisibleChanged: if (backingWindowVisible && opened && acceptsKeyboard) focusSearch()

  function syncCards() {
    if (!Model.sameWindows(cardToplevels, candidates)) cardToplevels = candidates
  }
  function syncFiltered() {
    if (Model.sameWindows(screenToplevels, screenToplevelsSource)) return
    var selected = screenToplevels[selectedIndex]
    screenToplevels = screenToplevelsSource
    selectedIndex = Math.max(0, screenToplevels.indexOf(selected))
    previewIndex = -1
    previewExitIndex = -1
  }
  onCandidatesChanged: syncCards()
  onScreenToplevelsSourceChanged: syncFiltered()
  onOpenedChanged: {
    if (opened) {
      selectedIndex = Math.max(0, screenToplevels.indexOf(Hyprland.activeToplevel))
      previewIndex = -1
      previewExitIndex = -1
      sidebar.positionViewAtIndex(DesktopState.current - 1, ListView.Contain)
      sidebar.forceLayout()
      if (acceptsKeyboard) Qt.callLater(focusSearch)
    }
  }
  onAcceptsKeyboardChanged: if (opened && acceptsKeyboard) Qt.callLater(focusSearch)
  Component.onCompleted: {
    syncCards()
    syncFiltered()
    manager.registerPanel(outputName, surface)
    registered = true
  }
  Component.onDestruction: if (registered) manager.registerPanel(outputName, null)

  Behavior on progress { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }

  function focusSearch() {
    if (!opened) return
    search.forceActiveFocus()
    if (acceptsKeyboard) {
      focusPrimed = false
      if (backingWindowVisible) focusPrime.restart()
    }
  }
  function takeKeyboard() { if (manager.keyboardOutput !== outputName) manager.focusOutput(outputName) }
  function activate(top) { if (top) manager.focusWindow(top.address) }
  function trackDrag(item, x, y) {
    var point = item.mapToItem(sidebar, x, y)
    dragY = point.x >= 0 && point.x <= sidebar.width ? point.y : -1
  }
  function togglePreview() {
    if (previewIndex >= 0) { previewExitIndex = previewIndex; previewIndex = -1; previewExit.restart() }
    else if (screenToplevels.length) { previewExitIndex = -1; previewIndex = selectedIndex }
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (manager.draggedWindow) manager.finishDrag(manager.draggedWindow, false)
      else if (previewIndex >= 0) togglePreview()
      else if (manager.filterText) manager.filterText = ""
      else manager.close()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activate(screenToplevels[selectedIndex])
    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) manager.nextOutput(event.modifiers & Qt.ShiftModifier ? -1 : 1)
    else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) DesktopState.add()
    else if (event.key === Qt.Key_Space && !manager.filterText) togglePreview()
    else if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].indexOf(event.key) >= 0) {
      var dx = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : 0
      var dy = event.key === Qt.Key_Up ? -1 : event.key === Qt.Key_Down ? 1 : 0
      selectedIndex = Model.directionalIndex(grid.windowLayout, selectedIndex, dx, dy)
      if (previewIndex >= 0) previewIndex = selectedIndex
    } else { event.accepted = false; return }
    event.accepted = true
  }

  function status() {
    return { output: outputName, visible: visible, desktop: DesktopState.current, workspace: workspace ? workspace.id : 0,
      slot: workspace ? workspace.slot : 0, windows: screenToplevels.map(function(w) { return w.address }),
      desktops: DesktopState.desktops.length, preview: previewIndex, keyboard: acceptsKeyboard,
      appearance: { radius: Style.cornerRadius, panel: String(Color.menu.background), text: String(Color.menu.text),
        selectedText: String(Color.menu.selectedText), railRadius: rail.radius, searchRadius: searchBox.radius } }
  }
  function geometry() {
    var result = []
    function visit(item) {
      if (!item.visible) return
      if (item.objectName === "desktop-thumbnail" || item.objectName === "expose-card" || item.objectName === "desktop-search") {
        var point = item.mapToItem(content, 0, 0)
        result.push({ kind: item.objectName, output: surface.outputName,
          x: point.x + surface.output.x, y: point.y + surface.output.y, width: item.width, height: item.height,
          window: item.windowAddress || "", preview: item.hasPreview || false,
          thumbnail: typeof item.previewStatus === "function" ? item.previewStatus() : null,
          workspace: item.workspaceId || 0, desktop: item.desktopId || DesktopState.current, slot: item.slotNumber || (surface.workspace ? surface.workspace.slot : 0),
          radius: item.previewRadius !== undefined ? item.previewRadius : item.radius || 0 })
      }
      for (var i = 0; i < item.children.length; i++) visit(item.children[i])
    }
    visit(content)
    return result
  }

  Timer { id: focusPrime; interval: 75; onTriggered: surface.focusPrimed = true }
  Timer { id: previewExit; interval: 240; onTriggered: surface.previewExitIndex = -1 }
  Timer {
    interval: 30
    repeat: true
    running: surface.opened && surface.manager.draggedWindow !== "" && surface.dragY >= 0
    onTriggered: {
      var direction = surface.dragY < Style.space(45) ? -1 : surface.dragY > sidebar.height - Style.space(45) ? 1 : 0
      sidebar.contentY = Math.max(sidebar.originY, Math.min(Math.max(sidebar.originY, sidebar.contentHeight - sidebar.height), sidebar.contentY + direction * Style.space(9)))
    }
  }
  Connections {
    target: DesktopState
    function onCurrentChanged() { sidebar.positionViewAtIndex(DesktopState.current - 1, ListView.Contain) }
  }

  // Producers sit outside the viewport and must not inherit the UI's fade.
  CaptureCache {
    id: captureCache
    scheduler: surface.manager.captureScheduler
    pixelRatio: surface.screen ? surface.screen.devicePixelRatio : 1
  }

  Item {
    id: content
    anchors.fill: parent
    opacity: surface.progress
    enabled: surface.opened
    Rectangle { anchors.fill: parent; color: Color.background }
    Image {
      id: wallpaper
      anchors.fill: parent
      source: surface.manager.wallpaper
      // The background is blurred; decoding a full-resolution wallpaper only
      // delays the first frame without adding visible detail.
      sourceSize: Qt.size(1280, 1280)
      fillMode: Image.PreserveAspectCrop
      visible: false
    }
    MultiEffect {
      anchors.fill: parent
      source: wallpaper
      blurEnabled: true
      blurMax: 32
      blur: 0.8
      saturation: -0.1
    }
    Rectangle { anchors.fill: parent; color: Color.menu.scrim }

    BorderSurface {
      id: rail
      opacity: surface.contentOpacity
      enabled: surface.manager.captureScheduler.ready
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: Style.space(18) }
      width: surface.sidebarWidth
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
      transform: Translate { x: -Style.space(24) * (1 - surface.progress) }

      ColumnLayout {
        anchors { fill: parent; margins: Style.space(14) }
        spacing: Style.space(16)
        ColumnLayout {
          Layout.fillWidth: true
          Layout.margins: Style.space(6)
          spacing: Style.space(6)
          Text { text: "Desktops"; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.heading; font.bold: true }
          Text { text: surface.outputName; color: Color.menu.text; opacity: 0.6; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
        }
        ListView {
          id: sidebar
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(12)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: DesktopState.desktops.length
          delegate: DesktopThumbnail {
            required property int index
            objectName: "desktop-thumbnail"
            width: sidebar.width
            desktopId: index + 1
            manager: surface.manager
            captureCache: surface.captureCache
            output: surface.output
            presented: surface.visible && y + height >= sidebar.contentY && y <= sidebar.contentY + sidebar.height
            capturing: surface.opened && presented
          }
        }
        BorderSurface {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(42)
          radius: Style.cornerRadius
          color: addPointer.pressed ? Style.pressedFillFor(Color.menu.text, Color.menu.selectedText) : Style.controlFill(false, addPointer.containsMouse, Color.menu.text, Color.menu.selectedText)
          borderSpec: Border.controlSpec(addPointer.containsMouse ? "hover-cursor" : "normal", Color.menu.text, Color.menu.selectedText)
          Text { anchors.centerIn: parent; text: "+  New desktop"; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
          MouseArea { id: addPointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: DesktopState.add() }
        }
      }
    }

    ColumnLayout {
      opacity: surface.contentOpacity
      enabled: surface.manager.captureScheduler.ready
      anchors { top: parent.top; bottom: parent.bottom; left: rail.right; right: parent.right; topMargin: Style.space(36); bottomMargin: Style.space(25); leftMargin: Style.space(30); rightMargin: Style.space(36) }
      spacing: Style.space(20)

      BorderSurface {
        id: searchBox
        objectName: "desktop-search"
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(760)
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredHeight: Math.max(Style.space(48), Style.font.heading + Style.spacing.panelPadding)
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: surface.acceptsKeyboard && surface.manager.filterText
          ? Border.hyprlandActiveSpec(Color.menu.selectedText, Style.focusBorderWidth)
          : Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
        RowLayout {
          anchors { fill: parent; leftMargin: Style.space(20); rightMargin: Style.space(18) }
          spacing: Style.space(14)
          Item {
            Layout.preferredWidth: Style.space(17)
            Layout.preferredHeight: Style.space(17)
            Rectangle { width: parent.width * 0.7; height: width; radius: width / 2; color: "transparent"; border.width: 1.8; border.color: Color.menu.text; opacity: 0.7 }
            Rectangle { x: parent.width * 0.64; y: parent.height * 0.62; width: parent.width * 0.5; height: 1.8; rotation: 45; transformOrigin: Item.Left; color: Color.menu.text; opacity: 0.7 }
          }
          TextInput {
            id: search
            Layout.fillWidth: true
            text: surface.manager.filterText
            color: Color.menu.text
            selectionColor: Style.selectionFillFor(Color.menu.text, Color.menu.selectedText)
            selectedTextColor: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            selectByMouse: true
            clip: true
            maximumLength: 200
            onTextEdited: surface.manager.filterText = text
            TapHandler { onPressedChanged: if (pressed) surface.takeKeyboard() }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) { surface.handleKey(event) }
            Text {
              anchors.fill: parent
              visible: !search.text
              text: "Filter windows…"
              color: Color.menu.text
              opacity: 0.6
              font: search.font
            }
          }
          Text {
            text: surface.screenToplevels.length + (surface.screenToplevels.length === 1 ? " window" : " windows")
            color: Color.menu.text
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Style.space(16)
        Layout.rightMargin: Style.space(16)
        spacing: Style.space(12)
        Text {
          Layout.fillWidth: true
          text: surface.desktop ? surface.desktop.name : "Desktops"
          textFormat: Text.PlainText
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          text: "Workspace " + (surface.workspace ? surface.workspace.slot : "—") + "  /  " + surface.outputName
          color: Color.menu.text
          opacity: 0.65
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        Layout.fillWidth: true
        visible: DesktopState.error !== "" || !DesktopState.enabled
        text: DesktopState.error || "Desktop management is not active in this session."
        color: Color.urgent
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Item {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        // IPC replaces the whole metadata object even for a title change.
        // Only changed aspect ratios should invalidate the costly composition.
        readonly property string layoutRatios: surface.screenToplevels.map(function(top) { return WindowModel.aspectRatioFor(top) }).join(",")
        readonly property var windowLayout: ExposeLayout.computeLayoutForRatios(layoutRatios ? layoutRatios.split(",").map(Number) : [], width, height, Style.space(64), Style.spacing.sm, surface.windowFooterHeight, width / Math.max(1, height))
        scale: 0.96 + surface.progress * 0.04
        MouseArea {
          anchors.fill: parent
          onClicked: {
            if (surface.previewIndex >= 0) surface.togglePreview()
            else surface.manager.close()
          }
        }
        WindowDropArea {
          id: gridDrop
          anchors.fill: parent
          manager: surface.manager
          desktopId: DesktopState.current
          outputName: surface.outputName
        }
        Repeater {
          model: surface.visible ? surface.cardToplevels : []
          delegate: ExposeCard {
            objectName: "expose-card"
            controller: surface
            screenToplevels: surface.screenToplevels
            acceptsKeyboard: surface.acceptsKeyboard
            windowLayout: grid.windowLayout
            layoutAreaWidth: grid.width
            layoutAreaHeight: grid.height
          }
        }
        BorderSurface {
          anchors.fill: parent
          visible: gridDrop.containsDrag
          z: 20
          radius: Style.cornerRadius
          color: "transparent"
          borderSpec: Border.hyprlandActiveSpec(Color.menu.selectedText, Style.focusBorderWidth)
        }
        Column {
          anchors.centerIn: parent
          width: parent.width * 0.8
          spacing: Style.space(12)
          visible: surface.screenToplevels.length === 0
          Text { width: parent.width; text: surface.manager.filterText ? "No matching windows" : "A little room to think."; color: Color.menu.text; opacity: 0.85; font.family: Style.font.menuFamily; font.pixelSize: Style.font.heading; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: surface.manager.filterText ? "Try another title or application." : "This workspace is empty. Drag a window here from another desktop."; color: Color.menu.text; opacity: 0.6; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
        }
      }

      Text {
        Layout.fillWidth: true
        text: "↑ ↓ ← →  Select     Space  Preview     Enter  Open     Tab  Monitor     Esc  Close\nDrag to another monitor’s window area or to a desktop in its sidebar."
        color: Color.menu.text
        opacity: 0.65
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 1.65
        wrapMode: Text.WordWrap
      }
    }
  }
}
