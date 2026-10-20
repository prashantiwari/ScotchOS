// A row of buttons, one per option; the current one is filled with the accent color.
import QtQuick

Row {
    id: c
    required property var shell
    property var options: []
    property string value: ""
    signal picked(string value)

    spacing: 6

    Repeater {
        model: c.options

        Rectangle {
            required property string modelData
            readonly property bool current: modelData === c.value
            width: label.implicitWidth + 20
            height: 26
            radius: 8
            color: current ? c.shell.accent : (area.containsMouse ? Qt.alpha(c.shell.fg, 0.12) : Qt.alpha(c.shell.fg, 0.06))
            border.width: 1
            border.color: current ? c.shell.accent : Qt.alpha(c.shell.accent, 0.35)

            Text {
                id: label
                anchors.centerIn: parent
                text: modelData
                color: current ? c.shell.bg : c.shell.fg
                font.family: c.shell.font
                font.pixelSize: 12
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: c.picked(modelData)
            }
        }
    }
}
