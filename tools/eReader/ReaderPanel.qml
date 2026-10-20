// The side panel over the left of the book: the contents (T), the bookmarks (M), a search (/) or the text look (A),
// Tab switches. Enter or a click jumps; in bookmarks, Delete (or the ×) removes one; in search, typing edits the
// query and Enter runs it; in text, typing filters the fonts and Enter picks one. Esc closes it.
import QtQuick

Rectangle {
    id: panel
    required property var reader
    readonly property var core: reader.core
    readonly property string mode: reader.panel
    readonly property var tabs: [
        { mode: "contents", label: "\u{F0279}  CONTENTS" },
        { mode: "bookmarks", label: "\u{F00C0}  BOOKMARKS" },
        { mode: "search", label: "\u{F0349}  SEARCH" },
        { mode: "text", label: "Aa" }
    ]
    readonly property bool searchMode: mode === "search"
    readonly property bool textMode: mode === "text"

    // ---- Text: fonts (typing filters them), size, spacing and layout ----
    // The generic serif and sans-serif, then the installed families, without icon, symbol, monospace and
    // single-script fonts (Noto has one per script). Listed only while the tab is open.
    readonly property var fonts: !textMode ? [] : ["serif", "sans-serif"].concat(Qt.fontFamilies().filter(f =>
        !/nerd|\bNF[MP]?$|emoji|symbol|icon|icomoon|awesome|material|mono|code|math|music|notation|^noto (?!(sans|serif)( display)?$)/i.test(f)))
    property string filter: ""
    readonly property var shownFonts: fonts.filter(f => f.toLowerCase().includes(filter.toLowerCase()))

    // Every mode is shown as rows of { title, sub, level, rich }; `here` is the row being read.
    readonly property var entries: mode === "bookmarks"
        ? reader.bookmarks.map(b => ({ title: b.text || "(page without text)", level: 1, rich: false,
                                       sub: (b.where || "Chapter " + (b.chapter + 1)) + "  ·  " + Math.round(b.percent) + "%" }))
        : searchMode
        ? reader.results.map(m => ({ title: esc(m.before) + `<font color="${core.accent}">` + esc(m.match) + "</font>" + esc(m.after),
                                     level: 1, rich: true, sub: m.where || "Chapter " + (m.chapter + 1) }))
        : textMode
        ? shownFonts.map(f => ({ title: f, level: 1, rich: false, sub: "", family: f }))
        : (reader.book?.toc ?? []).map(e => ({ title: e.title, level: e.level, rich: false, sub: "" }))
    readonly property int here: mode === "bookmarks" ? reader.markHere : searchMode ? reader.result
        : textMode ? shownFonts.indexOf(reader.bookFont) : reader.tocIndex
    readonly property string empty: mode === "bookmarks" ? "No bookmarks yet. B marks the page you're on."
        : textMode ? "No font matches."
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
        else if (textMode) return textKey(event);
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
    // Letters filter the fonts; + - change the size and ← → the page layout, as in the book.
    function textKey(event) {
        const k = event.key;
        if (k === Qt.Key_Down) list.incrementCurrentIndex();
        else if (k === Qt.Key_Up) list.decrementCurrentIndex();
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) jump(list.currentIndex);
        else if (k === Qt.Key_Right || k === Qt.Key_Left) reader.cyclePageLayout(k === Qt.Key_Right ? 1 : -1);
        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) reader.step("font_size", 16, 10, 32, 1);
        else if (k === Qt.Key_Minus || k === Qt.Key_Underscore) reader.step("font_size", 16, 10, 32, -1);
        else if (k === Qt.Key_Backspace) filter = filter.slice(0, -1);
        else if (/^[\w ]$/.test(event.text) && !(event.modifiers & Qt.ControlModifier)) filter += event.text;
        else return false;
        return true;
    }
    function jump(i) {
        if (i < 0 || i >= entries.length) return;
        if (textMode) {
            // Stays open, so fonts can be tried one after another.
            reader.set("font", shownFonts[i]);
            list.currentIndex = i;
        } else if (mode === "bookmarks") {
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
    onModeChanged: { filter = ""; Qt.callLater(reset) }     // after the list has its new model
    onFilterChanged: list.currentIndex = Math.max(0, here)

    // A setting in the text tab: accent when it's the current one, a click picks it.
    component Chip: Text {
        id: chip
        property bool current: false
        signal picked()
        color: current ? panel.core.accent : chipArea.containsMouse ? panel.core.fg : panel.core.dim
        font.family: panel.core.font
        font.pixelSize: 11
        MouseArea {
            id: chipArea
            anchors { fill: parent; margins: -4 }
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }
    component Caption: Text {
        width: 64
        color: panel.core.dim
        font.family: panel.core.font
        font.pixelSize: 10
        font.letterSpacing: 1
    }

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
    Column {
        id: textHead
        visible: panel.textMode
        anchors { left: parent.left; right: parent.right; top: title.bottom; leftMargin: 18; rightMargin: 18; topMargin: 14 }
        spacing: 10
        Row {
            spacing: 12
            Caption { text: "SIZE" }
            Chip { text: "\u2212"; onPicked: panel.reader.step("font_size", 16, 10, 32, -1) }
            Text { text: panel.reader.fontSize + " px"; color: panel.core.fg; font.family: panel.core.font; font.pixelSize: 11 }
            Chip { text: "+"; onPicked: panel.reader.step("font_size", 16, 10, 32, 1) }
        }
        Row {
            spacing: 12
            Caption { text: "SPACING" }
            Chip { text: "\u2212"; onPicked: panel.reader.step("line_height", 150, 100, 220, -10) }
            Text { text: panel.reader.lineHeight + " %"; color: panel.core.fg; font.family: panel.core.font; font.pixelSize: 11 }
            Chip { text: "+"; onPicked: panel.reader.step("line_height", 150, 100, 220, 10) }
            Chip { text: "Justify"; current: panel.reader.justify; onPicked: panel.reader.set("justify", panel.reader.justify ? "no" : "yes") }
        }
        Row {
            spacing: 14
            Caption { text: "MODE" }
            Chip { text: "Pages"; current: panel.reader.layout === "pages"; onPicked: panel.reader.set("layout", "pages") }
            Chip { text: "Scroll"; current: panel.reader.layout === "scroll"; onPicked: panel.reader.set("layout", "scroll") }
        }
        Row {
            spacing: 14
            Caption { text: "LAYOUT" }
            Repeater {
                model: [{ v: "column", label: "Column" }, { v: "full", label: "Full width" }, { v: "two", label: "Two pages" }]
                Chip {
                    required property var modelData
                    text: modelData.label
                    current: panel.reader.pageLayout === modelData.v
                    onPicked: panel.reader.set("page_layout", modelData.v)
                }
            }
        }
        Text {
            width: parent.width
            text: "\u{F0349}  " + (panel.filter || "type to filter fonts") + (panel.filter ? "\u258F" : "")
            elide: Text.ElideLeft
            textFormat: Text.PlainText
            color: panel.filter ? panel.core.fg : panel.core.dim
            font.family: panel.core.font
            font.pixelSize: 12
        }
    }
    Text {
        visible: !panel.entries.length
        anchors { left: parent.left; right: parent.right; top: panel.searchMode ? queryLine.bottom : panel.textMode ? textHead.bottom : title.bottom; margins: 18 }
        wrapMode: Text.WordWrap
        text: panel.empty
        color: panel.core.dim
        font.family: panel.core.font
        font.pixelSize: 12
    }
    ListView {
        id: list
        anchors { fill: parent; topMargin: panel.textMode ? textHead.y + textHead.height + 8 : panel.searchMode ? 76 : 44
                  bottomMargin: 12; leftMargin: 8; rightMargin: 8 }
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
                // Fonts are each shown in their own face.
                font.family: row.modelData.family ?? panel.core.font
                font.pixelSize: row.modelData.family ? 15 : row.modelData.level > 1 ? 11 : 12
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
