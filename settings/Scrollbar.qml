// A thin scrollbar for a Flickable: shown only when the content is taller than the view, and draggable.
import QtQuick

Rectangle {
    id: bar
    required property var shell
    required property Flickable flick

    width: 4
    radius: 2
    visible: flick.contentHeight > flick.height
    color: Qt.alpha(shell.fg, 0.06)

    Rectangle {
        width: parent.width
        radius: parent.radius
        y: bar.flick.visibleArea.yPosition * bar.height
        height: Math.max(20, bar.flick.visibleArea.heightRatio * bar.height)
        color: drag.pressed || drag.containsMouse ? bar.shell.accent : Qt.alpha(bar.shell.accent, 0.45)
    }

    // Wider than the bar so it's easy to grab; maps the pointer straight to a scroll position.
    MouseArea {
        id: drag
        anchors.fill: parent
        anchors.leftMargin: -4
        anchors.rightMargin: -4
        hoverEnabled: true
        function scrollTo(y) {
            const f = bar.flick;
            f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, y / bar.height * f.contentHeight - f.height / 2));
        }
        onPressed: e => scrollTo(e.y)
        onPositionChanged: e => { if (pressed) scrollTo(e.y) }
    }
}
