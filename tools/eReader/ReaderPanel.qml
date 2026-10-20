// The side panel over the left of the book: the contents (T), the bookmarks (M) or a search (/), Tab switches.
// Enter or a click jumps; in bookmarks, Delete (or the ×) removes one; in search, typing edits the query and
// Enter runs it. Esc closes it.
import QtQuick

Rectangle {
    id: panel
    required property var reader
    readonly property var core: reader.core
    readonly property string mode: reader.panel
    readonly property var tabs: [
        { mode: "contents", label: "\u{F0279}  CONTENTS" },
        { mode: "bookmarks", label: "\u{F00C0}  BOOKMARKS" },
        { mode: "search", label: "\u{F0349}  SEARCH" }
    ]
    readonly property bool searchMode: mode === "search"

    // Every mode is shown as rows of { title, sub, level, rich }; `here` is the row being read.
    readonly property var entries: mode === "bookmarks"
        ? reader.bookmarks.map(b => ({ title: b.text || "(page without text)", level: 1, rich: false,
                                       sub: (b.where || "Chapter " + (b.chapter + 1)) + "  ·  " + Math.round(b.percent) + "%" }))
        : searchMode
        ? reader.results.map(m => ({ title: esc(m.before) + `<font color="${core.accent}">` + esc(m.match) + "</font>" + esc(m.after),
                                     level: 1, rich: true, sub: m.where || "Chapter " + (m.chapter + 1) }))
        : (reader.book?.toc ?? []).map(e => ({ title: e.title, level: e.level, rich: false, sub: "" }))
    readonly property int here: mode === "bookmarks" ? reader.markHere : searchMode ? reader.result : reader.tocIndex
    readonly property string empty: mode === "bookmarks" ? "No bookmarks yet. B marks the page you're on."
        : !searchMode ? "This book has no contents."
        : reader.searching ? "Searching…"
        : reader.query.trim() && reader.query.trim() !== reader.searched ? "Enter searches the book."
        : reader.searched ? "No matches."
        : "Type words to find, then Enter. Later, n and N go to the next and previous match."
    function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    color: Qt.alpha(core.bg, 0.97)
    border.width: 1
    border.color: Qt.alpha(core.accent, 0.35)
    radius: 18

    function key(event) {
        const k = event.key;
        const i = tabs.findIndex(t => t.mode === mode);
        if (k === Qt.Key_Tab) reader.panel = tabs[(i + 1) % tabs.length].mode;
        else if (k === Qt.Key_Backtab) reader.panel = tabs[(i + tabs.length - 1) % tabs.length].mode;
        else if (searchMode) return searchKey(event);
        else if (k === Qt.Key_Down || k === Qt.Key_J) list.incrementCurrentIndex();
        else if (k === Qt.Key_Up || k === Qt.Key_K) list.decrementCurrentIndex();
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) jump(list.currentIndex);
        else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_D) && mode === "bookmarks") remove(list.currentIndex);
        else return false;
        return true;
    }
    // Letters go to the query (so j, k, T, M… can be searched for); Enter searches, or jumps once it has.
    function searchKey(event) {
        const k = event.key;
        if (k === Qt.Key_Down) list.incrementCurrentIndex();
        else if (k === Qt.Key_Up) list.decrementCurrentIndex();
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (reader.query.trim() !== reader.searched) reader.search();
            else jump(list.currentIndex);
        }
        else if (k === Qt.Key_Backspace) reader.query = reader.query.slice(0, -1);
        else if (event.text && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) reader.query += event.text;
        else return false;
        return true;
    }
    function jump(i) {
        if (i < 0 || i >= entries.length) return;
        if (mode === "bookmarks") {
            const b = reader.bookmarks[i];
            reader.panel = "";
            reader.jump(b.chapter, -1, b.pos);
        } else if (searchMode) {
            reader.panel = "";
            reader.showResult(i);
        } else {
            const e = reader.book.toc[i];
            reader.panel = "";
            reader.jump(e.chapter, e.anchor, 0);
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
    // Search: the query being typed, and how many matches it had.
    Text {
        id: queryLine
        visible: panel.searchMode
        anchors { left: parent.left; right: count.left; top: title.bottom; leftMargin: 18; rightMargin: 8; topMargin: 12 }
        text: "\u{F0349}  " + panel.reader.query + "\u258F"
        elide: Text.ElideLeft
        textFormat: Text.PlainText
        color: panel.core.fg
        font.family: panel.core.font
        font.pixelSize: 12
    }
    Text {
        id: count
        visible: panel.searchMode && panel.reader.searched !== ""
        anchors { right: parent.right; baseline: queryLine.baseline; rightMargin: 18 }
        text: panel.reader.total > panel.reader.results.length ? panel.reader.results.length + " of " + panel.reader.total
            : panel.reader.total + (panel.reader.total === 1 ? " match" : " matches")
        color: panel.core.dim
        font.family: panel.core.font
        font.pixelSize: 10
    }
    Text {
        visible: !panel.entries.length
        anchors { left: parent.left; right: parent.right; top: panel.searchMode ? queryLine.bottom : title.bottom; margins: 18 }
        wrapMode: Text.WordWrap
        text: panel.empty
        color: panel.core.dim
        font.family: panel.core.font
        font.pixelSize: 12
    }
    ListView {
        id: list
        anchors { fill: parent; topMargin: panel.searchMode ? 76 : 44; bottomMargin: 12; leftMargin: 8; rightMargin: 8 }
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
                maximumLineCount: row.modelData.rich ? 3 : 2
                elide: Text.ElideRight
                textFormat: row.modelData.rich ? Text.StyledText : Text.PlainText
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
