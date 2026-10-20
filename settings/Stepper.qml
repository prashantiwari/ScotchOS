// A number: − / + buttons, or type it and press Enter (or click away). Clamped to min..max.
import QtQuick

Row {
    id: s
    required property var shell
    property int value: 0
    property int min: 0
    property int max: 1000
    property int step: 1
    property string unit: ""
    signal edited(int value)

    spacing: 6

    function set(v) {
        v = Math.max(min, Math.min(max, v));
        if (v !== value) edited(v);
        input.text = Qt.binding(() => String(s.value));
    }

    component Button: Rectangle {
        id: b
        property string label
        signal clicked()
        width: 26
        height: 26
        radius: 8
        color: area.containsMouse ? Qt.alpha(s.shell.fg, 0.12) : Qt.alpha(s.shell.fg, 0.06)
        border.width: 1
        border.color: Qt.alpha(s.shell.accent, 0.35)
        Text {
            anchors.centerIn: parent
            text: b.label
            color: s.shell.fg
            font.family: s.shell.font
            font.pixelSize: 14
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }

    Button { label: "−"; onClicked: s.set(s.value - s.step) }

    Rectangle {
        width: 56
        height: 26
        radius: 8
        color: Qt.alpha(s.shell.fg, 0.06)
        border.width: 1
        border.color: input.activeFocus ? s.shell.accent : Qt.alpha(s.shell.accent, 0.35)

        TextInput {
            id: input
            anchors.fill: parent
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            text: String(s.value)
            color: s.shell.fg
            selectionColor: s.shell.accentDim
            font.family: s.shell.font
            font.pixelSize: 12
            validator: IntValidator { bottom: 0 }
            onEditingFinished: s.set(parseInt(text) || 0)
        }
    }

    Button { label: "+"; onClicked: s.set(s.value + s.step) }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: s.unit
        color: s.shell.dim
        font.family: s.shell.font
        font.pixelSize: 12
    }
}
