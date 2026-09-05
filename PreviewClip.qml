import QtQuick
import QtQuick.Effects
import qs.Commons

// Rectangle.clip alone does not clip its children to rounded corners.
// Skip the offscreen mask altogether for a square-corner configuration.
Item {
  id: root
  default property alias contentData: content.data
  property real radius: Style.cornerRadius
  clip: true
  // The mask must be a sibling of the captured content, not part of the
  // layer it masks. Otherwise the texture dependency hides the preview.
  data: [
    Item {
      id: content
      anchors.fill: parent
      layer.enabled: root.radius > 0
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
        maskSource: mask
      }
    },
    Rectangle {
      id: mask
      anchors.fill: parent
      radius: root.radius
      color: "black"
      visible: false
      layer.enabled: root.radius > 0
      layer.smooth: true
    }
  ]
}
