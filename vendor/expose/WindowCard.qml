import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../.." as Desktops
import "WindowModel.js" as WindowModel
import "Layout.js" as ExposeLayout
import qs.Commons
import qs.Ui

// Floating-caption presentation adapted from omarchy-expose. See UPSTREAM.md.
// Pointer handling and drag-and-drop belong to ExposeCard.qml.
Item {
    id: card

    required property var modelData
    required property var controller
    required property var screenToplevels
    required property bool acceptsKeyboard
    required property var windowLayout
    required property real layoutAreaWidth
    required property real layoutAreaHeight
    readonly property bool hasPreview: livePreview.hasContent
    readonly property real previewRadius: Style.cornerRadius
    // Position in the filtered list; -1 hides the card.
    readonly property int slot: screenToplevels.indexOf(modelData)
    readonly property bool inLayout: slot >= 0
    property bool hovered: false
    readonly property bool selected: acceptsKeyboard && inLayout && slot === controller.selectedIndex
    readonly property bool focusedWindow: modelData === Hyprland.activeToplevel
    readonly property bool previewed: acceptsKeyboard && inLayout && slot === controller.previewIndex
    readonly property bool exitingPreview: acceptsKeyboard && inLayout && slot === controller.previewExitIndex
    readonly property string applicationName: WindowModel.appIdFor(modelData) || "Application"
    readonly property var outlineSpec: focusedWindow || selected || hovered
        ? Border.hyprlandActiveSpec(Color.menu.selectedText, hovered ? Style.hoverBorderWidth : Style.focusBorderWidth)
        : Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
    // Retain the last rectangle while filtered out, rather than moving to the origin.
    readonly property var packedRectSource: inLayout ? windowLayout[slot] : null
    property var packedRect: Qt.rect(0, 0, 1, 1)
    readonly property var layoutRect: previewed
        ? ExposeLayout.previewRectFor(modelData, layoutAreaWidth, layoutAreaHeight, Style.spacing.sm, controller.windowFooterHeight)
        : packedRect

    onPackedRectSourceChanged: if (packedRectSource) packedRect = packedRectSource
    Component.onCompleted: if (packedRectSource) packedRect = packedRectSource
    visible: inLayout
    x: layoutRect.x
    y: layoutRect.y
    width: layoutRect.width
    height: layoutRect.height
    z: previewed ? 11 : (exitingPreview ? 10 : 0)
    opacity: controller.previewIndex < 0 || previewed ? 1 : 0.28

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        spacing: Style.spacing.sm

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Desktops.PreviewClip {
                id: previewFrame
                readonly property real windowAspectRatio: WindowModel.aspectRatioFor(card.modelData)
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height * windowAspectRatio)
                height: Math.min(parent.height, parent.width / windowAspectRatio)
                radius: card.previewRadius

                Rectangle { anchors.fill: parent; color: Color.background }
                Image {
                    anchors.centerIn: parent
                    width: Math.min(Style.space(64), parent.width * 0.3)
                    height: width
                    source: card.controller.manager.iconFor(card.modelData)
                    sourceSize: Qt.size(64, 64)
                    asynchronous: true
                    opacity: 1 - livePreview.opacity
                }
                Desktops.CapturedPreview {
                    id: livePreview
                    anchors.fill: parent
                    cache: card.controller.captureCache
                    toplevel: card.modelData
                    capturing: card.controller.opened && card.inLayout
                    refreshInterval: card.previewed ? 66 : 200
                }
            }

            BorderSurface {
                anchors.fill: previewFrame
                radius: previewFrame.radius
                color: "transparent"
                borderSpec: card.outlineSpec
            }
        }

        // The plugin always uses floating captions outside the preview frame.
        RowLayout {
            objectName: "window-caption"
            Layout.fillWidth: true
            Layout.preferredHeight: card.controller.windowFooterHeight
            spacing: Style.spacing.md

            Image {
                Layout.preferredWidth: Style.space(30)
                Layout.preferredHeight: Style.space(30)
                source: card.controller.manager.iconFor(card.modelData)
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CardText {
                    Layout.fillWidth: true
                    text: String(card.modelData.title || WindowModel.appIdFor(card.modelData) || "Untitled window")
                    font.bold: card.selected
                }
                CardText {
                    Layout.fillWidth: true
                    text: card.applicationName
                    opacity: 0.62
                    font.pixelSize: Style.font.caption
                }
            }
            ColumnLayout {
                spacing: 0
                CardText {
                    Layout.alignment: Qt.AlignRight
                    text: String(card.controller.workspace ? card.controller.workspace.slot : 1)
                    color: card.focusedWindow ? Color.accent : Color.menu.text
                    font.pixelSize: Style.font.heading
                    font.bold: true
                }
                CardText {
                    Layout.alignment: Qt.AlignRight
                    text: "Workspace"
                    opacity: 0.55
                    font.pixelSize: Style.font.caption
                }
            }
        }
    }

    component CardText: Text {
        textFormat: Text.PlainText
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
    }
    component CardAnimation: NumberAnimation {
        duration: card.controller.previewAnimationDuration
        easing.type: card.controller.previewAnimationEasing
    }

    Behavior on x { enabled: card.controller.motionSettled; CardAnimation {} }
    Behavior on y { enabled: card.controller.motionSettled; CardAnimation {} }
    Behavior on width { enabled: card.controller.motionSettled; CardAnimation {} }
    Behavior on height { enabled: card.controller.motionSettled; CardAnimation {} }
    Behavior on opacity {
        enabled: card.controller.motionSettled
        NumberAnimation { duration: card.controller.previewFadeDuration }
    }
}
