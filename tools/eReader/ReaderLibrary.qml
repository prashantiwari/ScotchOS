// The library: a grid of covers, filtered by what's typed (ReaderContent sends the keys here).
import QtQuick

Item {
    id: lib
    required property var reader
    readonly property var core: reader.core
    property string filter: ""

    // Last opened first, then never-opened books by title.
    readonly property var shown: {
        const q = filter.toLowerCase();
        const p = reader.progress;
        return reader.books
            .filter(b => !q || b.title.toLowerCase().includes(q) || b.author.toLowerCase().includes(q))
            .sort((a, b) => (p[b.id]?.opened ?? 0) - (p[a.id]?.opened ?? 0));
    }
    onShownChanged: grid.currentIndex = 0

    function key(event) {
        if (event.key === Qt.Key_Right) grid.moveCurrentIndexRight();
        else if (event.key === Qt.Key_Left) grid.moveCurrentIndexLeft();
        else if (event.key === Qt.Key_Down) grid.moveCurrentIndexDown();
        else if (event.key === Qt.Key_Up) grid.moveCurrentIndexUp();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (shown[grid.currentIndex]) reader.openBook(shown[grid.currentIndex]); }
        else if (event.key === Qt.Key_Backspace) filter = filter.slice(0, -1);
        else if (event.key === Qt.Key_Escape && filter) filter = "";
        else if (event.text && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) filter += event.text;
        else return false;
        return true;
    }

    // ---- Header: count, filter, errors ----
    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 6
        Row {
            spacing: 12
            Text {
                text: "\u{F00BA}  LIBRARY"
                color: lib.core.accent
                font.family: lib.core.font
                font.pixelSize: 11
                font.letterSpacing: 1
            }
            Text {
                text: lib.reader.scanning && !lib.reader.books.length ? "scanning…"
                    : lib.shown.length + (lib.filter ? " of " + lib.reader.books.length : "") + " books"
                color: lib.core.dim
                font.family: lib.core.font
                font.pixelSize: 11
            }
        }
        Text {
            text: lib.filter ? "\u{F0349}  " + lib.filter : "Type to filter · Enter opens · Esc closes"
            color: lib.filter ? lib.core.fg : lib.core.dim
            font.family: lib.core.font
            font.pixelSize: 12
        }
        Text {
            visible: lib.reader.error !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: lib.reader.error
            color: lib.core.accent
            font.family: lib.core.font
            font.pixelSize: 12
        }
    }

    Text {
        visible: !lib.reader.scanning && !lib.reader.books.length
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "No books in " + lib.reader.libraryDir + ".\n\nPut .epub, .mobi, .azw3, .fb2, .txt or .md files there "
              + "(subfolders work), or change library_dir in ScotchOS settings › E-reader."
        color: lib.core.dim
        font.family: lib.core.font
        font.pixelSize: 12
    }

    // ---- Grid ----
    GridView {
        id: grid
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; margins: 24; topMargin: 16 }
        clip: true
        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 150)))
        cellHeight: 250
        model: lib.shown
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property var saved: lib.reader.progress[modelData.id]
            readonly property bool current: GridView.isCurrentItem
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors { fill: parent; margins: 5 }
                radius: 12
                color: cell.current || area.containsMouse ? Qt.alpha(lib.core.accent, 0.14) : "transparent"
                border.width: cell.current ? 1 : 0
                border.color: Qt.alpha(lib.core.accent, 0.35)
            }

            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 6
                Rectangle {
                    width: parent.width
                    height: Math.round(width * 1.45)
                    radius: 6
                    clip: true
                    color: Qt.alpha(lib.core.accent, 0.18)
                    border.width: 1
                    border.color: Qt.alpha(lib.core.accent, 0.35)
                    // No cover: the title on a tinted card.
                    Text {
                        visible: cover.status !== Image.Ready
                        anchors { fill: parent; margins: 10 }
                        text: cell.modelData.title
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: lib.core.accent
                        font.family: lib.core.font
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: cell.modelData.cover ? "file://" + cell.modelData.cover : ""
                        sourceSize: Qt.size(width, height)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    // Progress along the cover's bottom edge.
                    Rectangle {
                        visible: !!cell.saved
                        anchors { left: parent.left; bottom: parent.bottom }
                        height: 4
                        width: parent.width * Math.min(1, (cell.saved?.percent ?? 0) / 100)
                        color: lib.core.accent
                    }
                }
                Text {
                    width: parent.width
                    text: cell.modelData.title
                    elide: Text.ElideRight
                    color: lib.core.fg
                    font.family: lib.core.font
                    font.pixelSize: 11
                }
                Text {
                    width: parent.width
                    text: (cell.saved ? Math.round(cell.saved.percent) + "% · " : "") + (cell.modelData.author || cell.modelData.format)
                    elide: Text.ElideRight
                    color: lib.core.dim
                    font.family: lib.core.font
                    font.pixelSize: 10
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lib.reader.openBook(cell.modelData)
            }
        }
    }
}
