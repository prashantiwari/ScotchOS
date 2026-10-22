// A number on a track: drag the handle or click the track. Snaps to `step`, clamped to min..max.
import QtQuick

Row {
    id: s
    required property var shell
    property int value: 0
    property int min: 0
    property int max: 100
    property int step: 1
    property string unit: ""
    signal edited(int value)

    spacing: 12

    // Saved on every step while dragging (setConf is an in-process write), so the widget resizes as you drag.
    function setAt(x) {
        const f = Math.max(0, Math.min(1, x / track.width));
        const v = Math.max(min, Math.min(max, min + Math.round(f * (max - min) / step) * step));
        if (v !== value) edited(v);
    }

    Item {
        id: track
        width: 220
        height: 26
        readonly property real frac: (Math.max(s.min, Math.min(s.max, s.value)) - s.min) / Math.max(1, s.max - s.min)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Qt.alpha(s.shell.fg, 0.1)
            Rectangle {
                width: track.frac * parent.width
                height: parent.height
                radius: parent.radius
                color: s.shell.accent
            }
        }
        Rectangle {
            x: track.frac * track.width - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: area.pressed || area.containsMouse ? s.shell.accent : s.shell.fg
            border.width: 1
            border.color: Qt.alpha(s.shell.accent, 0.6)
        }
        MouseArea {
            id: area
            anchors.fill: parent
            anchors.leftMargin: -7
            anchors.rightMargin: -7
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: e => s.setAt(e.x - 7)
            onPositionChanged: e => { if (pressed) s.setAt(e.x - 7) }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: s.value + " " + s.unit
        color: s.shell.fg
        font.family: s.shell.font
        font.pixelSize: 12
    }
}
