// Every key of the reader on one card (? or F1), grouped like the README's key table: keep the two the same.
// Created only while shown; any key or a click closes it (ReaderContent).
import QtQuick

Rectangle {
    id: card
    required property var core

    readonly property var sections: [
        { title: "TURNING PAGES", rows: [
            { k: "→  PgDn  Space  l", d: "Next page" },
            { k: "←  PgUp  h  Shift+Space", d: "Previous page" },
            { k: "click left / right", d: "Previous / next page (outer thirds)" },
            { k: "↓ j  /  ↑ k", d: "Scroll one line (pages too)" },
            { k: "wheel", d: "Scroll three lines" },
            { k: "Home", d: "Start of the chapter" },
            { k: "Backspace", d: "Back to where the last jump left from" },
            { k: "n  /  N", d: "Next / previous search match" } ] },
        { title: "PANELS", rows: [
            { k: "T", d: "Contents (or rest the mouse on the left edge)" },
            { k: "M", d: "Bookmarks" },
            { k: "Shift+H", d: "Highlights" },
            { k: "/", d: "Search the book" },
            { k: "A", d: "Settings: fonts and text" },
            { k: "Tab  /  Shift+Tab", d: "Next / previous tab" },
            { k: "Enter", d: "Jump to the entry" },
            { k: "Delete  /  E", d: "Remove one / export (bookmarks, highlights)" },
            { k: "Esc", d: "Close the panel" } ] },
        { title: "MARKS AND NOTES", rows: [
            { k: "B", d: "Bookmark this page, or remove it" },
            { k: "drag", d: "Select text (a click or Esc lets go)" },
            { k: "H  (selected)", d: "Highlight the selection" },
            { k: "N  (selected)", d: "Note on the highlight" } ] },
        { title: "TEXT AND LAYOUT", rows: [
            { k: "+  /  -", d: "Font size" },
            { k: "]  /  [", d: "Column width" },
            { k: ".  /  ,", d: "Line spacing" },
            { k: "Shift+J", d: "Justified ↔ ragged" },
            { k: "S", d: "Pages ↔ scroll" },
            { k: "W  /  Shift+W", d: "Column → full width → two pages" } ] },
        { title: "WINDOW", rows: [
            { k: "F  /  F11", d: "Fullscreen ↔ window" },
            { k: "Esc", d: "Let go of the selection, leave fullscreen, else the library" },
            { k: "Q", d: "Close" },
            { k: "?  /  F1", d: "This list" } ] },
        { title: "LIBRARY", rows: [
            { k: "type", d: "Filter the books" },
            { k: "arrows  /  Enter", d: "Move / open" },
            { k: "Esc", d: "Clear the filter, else close" } ] }
    ]

    // ---- Columns: as many as fit, each section going to the shortest one ----
    readonly property int columnWidth: 300
    readonly property int count: Math.max(1, Math.min(3, Math.floor((width - 48 + 28) / (columnWidth + 28))))
    readonly property var columns: {
        const cols = Array.from({ length: count }, () => ({ sections: [], size: 0 }));
        for (const s of sections) {
            const c = cols.reduce((a, b) => b.size < a.size ? b : a);
            c.sections.push(s);
            c.size += s.rows.length + 2;
        }
        return cols.map(c => c.sections);
    }

    color: Qt.alpha(core.bg, 0.97)
    border.width: 1
    border.color: Qt.alpha(core.accent, 0.35)
    radius: 18
    implicitHeight: head.height + flick.contentHeight + 24 + 18 + 14

    Text {
        id: head
        anchors { left: parent.left; top: parent.top; margins: 24; topMargin: 18 }
        text: "\u{F030C}  KEYS"
        color: card.core.accent
        font.family: card.core.font
        font.pixelSize: 11
        font.letterSpacing: 1
    }
    Text {
        anchors { right: parent.right; baseline: head.baseline; rightMargin: 24 }
        text: "any key or a click closes"
        color: card.core.dim
        font.family: card.core.font
        font.pixelSize: 10
    }

    // Scrolls (wheel) when the window is too short for the whole list.
    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom
                  leftMargin: 24; rightMargin: 24; topMargin: 14; bottomMargin: 18 }
        clip: true
        contentHeight: cols.height
        boundsBehavior: Flickable.StopAtBounds
        Row {
            id: cols
            spacing: 28
            Repeater {
                model: card.columns
                Column {
                    required property var modelData
                    width: card.columnWidth
                    spacing: 16
                    Repeater {
                        model: parent.modelData
                        Column {
                            id: section
                            required property var modelData
                            width: card.columnWidth
                            spacing: 5
                            Text {
                                text: section.modelData.title
                                color: card.core.dim
                                font.family: card.core.font
                                font.pixelSize: 10
                                font.letterSpacing: 1
                            }
                            Repeater {
                                model: section.modelData.rows
                                Row {
                                    required property var modelData
                                    spacing: 10
                                    Text {
                                        width: 116
                                        text: parent.modelData.k
                                        wrapMode: Text.WordWrap
                                        textFormat: Text.PlainText
                                        color: card.core.accent
                                        font.family: card.core.font
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        width: card.columnWidth - 126
                                        text: parent.modelData.d
                                        wrapMode: Text.WordWrap
                                        textFormat: Text.PlainText
                                        color: card.core.fg
                                        font.family: card.core.font
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
