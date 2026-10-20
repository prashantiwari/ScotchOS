// Table of contents: a panel over the left of the book. Enter or a click jumps; T or Esc closes it.
import QtQuick

Rectangle {
    id: toc
    required property var reader
    readonly property var core: reader.core
    readonly property var entries: reader.book?.toc ?? []
    readonly property int here: reader.tocIndex

    color: Qt.alpha(core.bg, 0.97)
    border.width: 1
    border.color: Qt.alpha(core.accent, 0.35)
    radius: 18

    function key(event) {
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) list.incrementCurrentIndex();
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) list.decrementCurrentIndex();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) jump(list.currentIndex);
        else return false;
        return true;
    }
    function jump(i) {
        const e = entries[i];
        if (!e) return;
        reader.tocOpen = false;
        reader.goTo(e.chapter, e.anchor, 0);
    }
    Component.onCompleted: { list.currentIndex = Math.max(0, here); list.positionViewAtIndex(list.currentIndex, ListView.Center); }

    Text {
        id: title
        anchors { left: parent.left; top: parent.top; margins: 18 }
        text: "\u{F0279}  CONTENTS"
        color: toc.core.accent
        font.family: toc.core.font
        font.pixelSize: 11
        font.letterSpacing: 1
    }
    Text {
        visible: !toc.entries.length
        anchors { left: parent.left; top: title.bottom; margins: 18 }
        text: "This book has no contents."
        color: toc.core.dim
        font.family: toc.core.font
        font.pixelSize: 12
    }
    ListView {
        id: list
        anchors { fill: parent; topMargin: 44; bottomMargin: 12; leftMargin: 8; rightMargin: 8 }
        clip: true
        model: toc.entries
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: label.implicitHeight + 12
            radius: 8
            color: ListView.isCurrentItem || rowArea.containsMouse ? Qt.alpha(toc.core.accent, 0.14) : "transparent"
            Text {
                id: label
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: 10 + (row.modelData.level - 1) * 14; rightMargin: 10 }
                text: row.modelData.title
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: row.index === toc.here ? toc.core.accent : toc.core.fg
                font.family: toc.core.font
                font.pixelSize: row.modelData.level > 1 ? 11 : 12
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: toc.jump(row.index)
            }
        }
    }
}
