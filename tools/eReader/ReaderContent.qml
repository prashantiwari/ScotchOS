// What both windows show: the library or the open book (title line, text, status line, contents panel),
// and every key. The floating window and the fullscreen overlay each hold one.
import QtQuick

Item {
    id: c
    required property var reader
    readonly property var core: reader.core
    focus: true

    // ---- Keys ----
    Keys.onPressed: event => event.accepted = handle(event)
    // event: { key, modifiers, text }; true when the key did something.
    function handle(event) {
        const r = reader;
        const k = event.key;
        if (k === Qt.Key_Q && r.view === "book" && !r.panel) { r.open = false; return true; }
        if (r.view === "library") {
            if (k === Qt.Key_Escape && !library.filter) r.open = false;
            else if (k === Qt.Key_F11) r.fullscreen = !r.fullscreen;
            else if (!library.key(event)) return false;
            return true;
        }
        if (r.panel) {
            // T, M and A open their tab, or close the panel when it's already showing (in search and text they're typed).
            const typing = r.panel === "search" || r.panel === "text";
            const tab = typing ? "" : k === Qt.Key_T ? "contents" : k === Qt.Key_M ? "bookmarks" : k === Qt.Key_A ? "text" : "";
            if (k === Qt.Key_Escape || tab === r.panel) r.panel = "";
            else if (tab) r.panel = tab;
            else if (!panelLoader.item?.key(event)) return false;
            return true;
        }
        const shift = event.modifiers & Qt.ShiftModifier;
        if (k === Qt.Key_Escape) {
            if (r.fullscreen) r.fullscreen = false;
            else r.view = "library";
        }
        else if (k === Qt.Key_Right || k === Qt.Key_PageDown || k === Qt.Key_L || (k === Qt.Key_Space && !shift)) bookView.next();
        else if (k === Qt.Key_Left || k === Qt.Key_PageUp || k === Qt.Key_H || (k === Qt.Key_Space && shift)) bookView.prev();
        else if (k === Qt.Key_J && shift) r.set("justify", r.justify ? "no" : "yes");
        else if (k === Qt.Key_Down || k === Qt.Key_J) bookView.scrollBy(bookView.lineStep());
        else if (k === Qt.Key_Up || k === Qt.Key_K) bookView.scrollBy(-bookView.lineStep());
        else if (k === Qt.Key_Home) r.goTo(r.chapter, -1, 0);
        else if (k === Qt.Key_T) r.panel = "contents";
        else if (k === Qt.Key_M) r.panel = "bookmarks";
        else if (k === Qt.Key_B) r.toggleBookmark(bookView.snippet());
        else if (k === Qt.Key_Slash) r.panel = "search";
        else if (k === Qt.Key_A) r.panel = "text";
        else if (k === Qt.Key_W) r.cyclePageLayout(shift ? -1 : 1);
        else if (k === Qt.Key_N) r.nextResult(shift ? -1 : 1);
        else if (k === Qt.Key_Backspace) r.back();
        else if (k === Qt.Key_F || k === Qt.Key_F11) r.fullscreen = !r.fullscreen;
        else if (k === Qt.Key_S) r.set("layout", r.layout === "pages" ? "scroll" : "pages");
        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) r.step("font_size", 16, 10, 32, 1);
        else if (k === Qt.Key_Minus || k === Qt.Key_Underscore) r.step("font_size", 16, 10, 32, -1);
        else if (k === Qt.Key_BracketRight) r.step("width", 720, 400, 1600, 40);
        else if (k === Qt.Key_BracketLeft) r.step("width", 720, 400, 1600, -40);
        else if (k === Qt.Key_Period) r.step("line_height", 150, 100, 220, 10);
        else if (k === Qt.Key_Comma) r.step("line_height", 150, 100, 220, -10);
        else return false;
        return true;
    }

    // ---- Library ----
    ReaderLibrary {
        id: library
        anchors.fill: parent
        visible: c.reader.view === "library"
        reader: c.reader
    }

    // ---- Book ----
    Item {
        anchors.fill: parent
        visible: c.reader.view === "book"

        // Book · the contents entry being read.
        Text {
            id: top
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 48; topMargin: 12 }
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: !c.reader.book ? "" : c.reader.book.title + (chapterTitle ? "  ·  " + chapterTitle : "")
            readonly property string chapterTitle: c.reader.book?.toc[c.reader.tocIndex]?.title
                                                   ?? c.reader.book?.chapters[c.reader.chapter]?.title ?? ""
            color: c.core.dim
            font.family: c.core.font
            font.pixelSize: 11
        }

        // A ribbon in the corner while the page has a bookmark (a click removes it).
        Text {
            visible: c.reader.markHere >= 0 && !c.reader.loading
            anchors { right: parent.right; top: parent.top; rightMargin: 22 }
            text: "\u{F00C0}"
            color: c.core.accent
            font.family: c.core.font
            font.pixelSize: 22
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: c.reader.toggleBookmark("")
            }
        }

        ReaderBook {
            id: bookView
            anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: status.top; margins: 24; topMargin: 14; bottomMargin: 10 }
            reader: c.reader
        }

        Text {
            visible: c.reader.loading || c.reader.error !== ""
            anchors.centerIn: parent
            text: c.reader.loading ? "Opening…" : c.reader.error
            color: c.reader.loading ? c.core.dim : c.core.accent
            font.family: c.core.font
            font.pixelSize: 12
        }

        // Page (or place in the chapter) · chapter · whole book · time left in the chapter and the book.
        Text {
            id: status
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18; bottomMargin: 10 }
            horizontalAlignment: Text.AlignHCenter
            readonly property var b: c.reader.book
            text: !b ? "" : (bookView.paged ? bookView.page + 1 + (bookView.hasRight ? "–" + (bookView.page + 2) : "") + " / " + bookView.pageCount : Math.round(bookView.frac * 100) + "%")
                  + "   ·   chapter " + (c.reader.chapter + 1) + " / " + b.chapters.length
                  + "   ·   " + Math.round(c.reader.percentAt(c.reader.chapter, bookView.frac)) + "% of the book"
                  + (c.reader.timeLeft ? "   ·   " + c.reader.duration(c.reader.minutesLeft(bookView.frac, false)) + " left in chapter, "
                                         + c.reader.duration(c.reader.minutesLeft(bookView.frac, true)) + " in book" : "")
            color: c.core.dim
            font.family: c.core.font
            font.pixelSize: 10
        }

        // Click outside closes it; the panel itself sits over the left of the text.
        MouseArea {
            anchors.fill: parent
            visible: c.reader.panel !== ""
            onClicked: c.reader.panel = ""
            onWheel: wheel => wheel.accepted = true
        }
        Loader {
            id: panelLoader
            active: c.reader.panel !== ""
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 12 }
            width: Math.min(360, parent.width - 24)
            sourceComponent: ReaderPanel { reader: c.reader }
        }
    }
}
