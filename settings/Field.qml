// A line of text (a URL, a key). Saved on Enter or when it loses focus, not on every keystroke.
import QtQuick

Rectangle {
    id: f
    required property var shell
    property string value: ""
    property string placeholder: ""
    property bool secret: false
    signal edited(string value)

    width: 360
    height: 30
    radius: 8
    color: Qt.alpha(shell.fg, 0.06)
    border.width: 1
    border.color: input.activeFocus ? shell.accent : Qt.alpha(shell.accent, 0.35)

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        text: f.value
        echoMode: f.secret && !activeFocus ? TextInput.Password : TextInput.Normal
        color: f.shell.fg
        selectionColor: f.shell.accentDim
        font.family: f.shell.font
        font.pixelSize: 12
        // "#" at the start or after a space starts a comment in scotchos.conf, and a newline would end the line.
        validator: RegularExpressionValidator { regularExpression: /(?!#)(?![^\n]*\s#)[^\n]*/ }
        onEditingFinished: {
            const v = text.trim();
            if (v !== f.value) f.edited(v);
            text = Qt.binding(() => f.value);
        }
    }
    Text {
        anchors.fill: input
        visible: !input.text && !input.activeFocus
        verticalAlignment: Text.AlignVCenter
        text: f.placeholder
        color: f.shell.dim
        font.family: f.shell.font
        font.pixelSize: 12
    }
}
