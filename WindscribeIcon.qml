import QtQuick
import QtQuick.Shapes
import qs.Commons

// Theme-colored shield mark. Filled geometry (no SVG) so it stays crisp in
// the tiny bar slot the same way TailscaleIcon and DropboxIcon do.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool crossed: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      startX: root.width * 0.50
      startY: root.height * 0.06
      PathLine { x: root.width * 0.90; y: root.height * 0.22 }
      PathLine { x: root.width * 0.86; y: root.height * 0.55 }
      PathQuad {
        x: root.width * 0.50
        y: root.height * 0.94
        controlX: root.width * 0.84
        controlY: root.height * 0.78
      }
      PathQuad {
        x: root.width * 0.14
        y: root.height * 0.55
        controlX: root.width * 0.16
        controlY: root.height * 0.78
      }
      PathLine { x: root.width * 0.10; y: root.height * 0.22 }
      PathLine { x: root.width * 0.50; y: root.height * 0.06 }
    }
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.18
    height: Math.max(2, parent.height * 0.13)
    radius: height / 2
    color: root.color
    rotation: -45
  }
}
