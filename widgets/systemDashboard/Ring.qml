// Circular gauge: a faint full track with a colored arc for `value` (0..1).
import QtQuick
import QtQuick.Shapes

Item {
    id: ring
    property real value: 0
    property color color: "white"
    property color trackColor: "#33ffffff"
    property string valueText: ""
    property string label: ""
    property string subText: ""
    property color textColor: "white"
    property color dimColor: "#aaffffff"
    property string font: "JetBrainsMono Nerd Font"
    property real size: 76
    property real thickness: 7

    implicitWidth: size
    implicitHeight: size + 34

    // No animation on `value`: easing it after every 1 s update kept the panel redrawing at
    // 60 fps most of the time, about 7x the CPU of the rest of the dashboard combined.

    Shape {
        width: ring.size
        height: ring.size
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.trackColor
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.size / 2; centerY: ring.size / 2
                radiusX: (ring.size - ring.thickness) / 2; radiusY: radiusX
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.color
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.size / 2; centerY: ring.size / 2
                radiusX: (ring.size - ring.thickness) / 2; radiusY: radiusX
                startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(1, ring.value))
            }
        }
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -17
        text: ring.valueText
        color: ring.textColor
        font { family: ring.font; pixelSize: 15; bold: true }
    }

    Column {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        spacing: 1
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ring.label
            color: ring.textColor
            font { family: ring.font; pixelSize: 11; bold: true; letterSpacing: 1.5 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ring.subText
            color: ring.dimColor
            font { family: ring.font; pixelSize: 10 }
        }
    }
}
