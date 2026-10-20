// The side panel over the left of the book: the contents (T) or the bookmarks (M), Tab switches.
// Enter or a click jumps; in bookmarks, Delete (or the ×) removes one. Esc closes it.
import QtQuick

Rectangle {
    id: panel
    required property var reader
    readonly property var core: reader.core
    readonly property string mode: reader.panel
    readonly property var tabs: [
        { mode: "contents", label: "\u{F0279}  CONTENTS" },
        { mode: "bookmarks", label: "\u{F00C0}  BOOKMARKS" }
    ]

    // Every mode is shown as rows of { title, sub, level }; `here` is the row being read.
    readonly property var entries: mode === "bookmarks"
        ? reader.bookmarks.map(b => ({ title: b.text || "(page without text)", level: 1,
                                       sub: (b.where || "Chapter " + (b.chapter + 1)) + "  ·  " + Math.round(b.percent) + "%" }))
        : (reader.book?.toc ?? []).map(e => ({ title: e.title, level: e.level, sub: "" }))
    readonly property int here: mode === "bookmarks" ? reader.markHere : reader.tocIndex
    readonly property string empty: mode === "bookmarks" ? "No bookmarks yet. B marks the page you're on."
                                                         : "This book has no contents."

    color: Qt.alpha(core.bg, 0.97)
    border.width: 1
    border.color: Qt.alpha(core.accent, 0.35)
    radius: 18

    function key(event) {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) reader.panel = mode === "contents" ? "bookmarks" : "contents";
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) list.incrementCurrentIndex();
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) list.decrementCurrentIndex();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) jump(list.currentIndex);
        else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_D) && mode === "bookmarks") remove(list.currentIndex);
        else return false;
        return true;
    }
    function jump(i) {
        if (i < 0 || i >= entries.length) return;
        if (mode === "bookmarks") {
            const b = reader.bookmarks[i];
            reader.panel = "";
            reader.goTo(b.chapter, -1, b.pos);
        } else {
            const e = reader.book.toc[i];
            reader.panel = "";
            reader.goTo(e.chapter, e.anchor, 0);
        }
    }
    function remove(i) {
        if (i < 0 || i >= reader.bookmarks.length) return;
        reader.removeBookmark(i);
        list.currentIndex = Math.min(i, entries.length - 1);
    }
    function reset() { list.currentIndex = Math.max(0, here); list.positionViewAtIndex(list.currentIndex, ListView.Center); }
    Component.onCompleted: reset()
    onModeChanged: Qt.callLater(reset)      // after the list has its new model

    Row {
        id: title
        anchors { left: parent.left; top: parent.top; margins: 18 }
        spacing: 16
        Repeater {
            model: panel.tabs
            Text {
                required property var modelData
                text: modelData.label
                color: modelData.mode === panel.mode ? panel.core.accent : panel.core.dim
                font.family: panel.core.font
                font.pixelSize: 11
                font.letterSpacing: 1
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.reader.panel = parent.modelData.mode
                }
            }
        }
    }
    Text {
        visible: !panel.entries.length
        anchors { left: parent.left; right: parent.right; top: title.bottom; margins: 18 }
        wrapMode: Text.WordWrap
        text: panel.empty
        color: panel.core.dim
        font.family: panel.core.font
        font.pixelSize: 12
    }
    ListView {
        id: list
        anchors { fill: parent; topMargin: 44; bottomMargin: 12; leftMargin: 8; rightMargin: 8 }
        clip: true
        model: panel.entries
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: label.implicitHeight + (sub.visible ? sub.implicitHeight + 2 : 0) + 12
            radius: 8
            color: ListView.isCurrentItem || rowArea.containsMouse ? Qt.alpha(panel.core.accent, 0.14) : "transparent"
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.jump(row.index)
            }
            Text {
                id: label
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 6
                          leftMargin: 10 + (row.modelData.level - 1) * 14; rightMargin: panel.mode === "bookmarks" ? 28 : 10 }
                text: row.modelData.title
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: row.index === panel.here ? panel.core.accent : panel.core.fg
                font.family: panel.core.font
                font.pixelSize: row.modelData.level > 1 ? 11 : 12
            }
            Text {
                id: sub
                visible: row.modelData.sub !== ""
                anchors { left: label.left; right: label.right; top: label.bottom; topMargin: 2 }
                text: row.modelData.sub
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: panel.core.dim
                font.family: panel.core.font
                font.pixelSize: 10
            }
            // Bookmarks: remove.
            Text {
                visible: panel.mode === "bookmarks" && (rowArea.containsMouse || removeArea.containsMouse || row.ListView.isCurrentItem)
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: "\u{F0156}"
                color: removeArea.containsMouse ? panel.core.accent : panel.core.dim
                font.family: panel.core.font
                font.pixelSize: 13
                MouseArea {
                    id: removeArea
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.remove(row.index)
                }
            }
        }
    }
}
