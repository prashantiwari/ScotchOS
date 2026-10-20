// Where on the screen the card sits: a 3 × 3 grid shaped like the screen, plus an "auto" button
// for widgets that pick their own spot.
import QtQuick

Row {
    id: g
    required property var shell
    property var positions: []      // the 9 names, row by row (core.positions)
    property bool allowAuto: false
    property string value: ""
    signal picked(string value)

    spacing: 12

    Rectangle {
        width: 3 * 30 + 2 * 4 + 12
        height: 3 * 18 + 2 * 4 + 12
        radius: 8
        color: Qt.alpha(g.shell.fg, 0.04)
        border.width: 1
        border.color: Qt.alpha(g.shell.accent, 0.35)

        Grid {
            anchors.centerIn: parent
            columns: 3
            spacing: 4

            Repeater {
                model: g.positions

                Rectangle {
                    required property string modelData
                    readonly property bool current: modelData === g.value
                    width: 30
                    height: 18
                    radius: 4
                    color: current ? g.shell.accent : (area.containsMouse ? Qt.alpha(g.shell.fg, 0.2) : Qt.alpha(g.shell.fg, 0.08))
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: g.picked(modelData)
                    }
                }
            }
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            text: g.value
            color: g.shell.fg
            font.family: g.shell.font
            font.pixelSize: 12
        }
        Choice {
            visible: g.allowAuto
            shell: g.shell
            options: ["auto"]
            value: g.value
            onPicked: v => g.picked(v)
        }
    }
}
