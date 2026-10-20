// An on/off switch. Emits toggled(); the owner writes the setting, and `on` follows the conf.
import QtQuick

Rectangle {
    id: t
    required property var shell
    property bool on: false
    signal toggled()

    width: 38
    height: 20
    radius: 10
    color: on ? shell.accent : Qt.alpha(shell.fg, 0.15)

    Rectangle {
        width: 14
        height: 14
        radius: 7
        y: 3
        x: t.on ? t.width - width - 3 : 3
        color: t.on ? t.shell.bg : t.shell.fg
        Behavior on x { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: t.toggled()
    }
}
