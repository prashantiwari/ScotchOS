// The quote card: header with the time of the last fetch, the quote, and its author.
import QtQuick

Rectangle {
    id: card
    required property var shell
    readonly property var q: shell.quote
    readonly property real contentWidth: 340

    width: content.width + 40
    height: content.implicitHeight + 40
    radius: 18
    color: Qt.alpha(shell.bg, 0.78)
    border { width: 1; color: Qt.alpha(shell.accent, 0.35) }

    Column {
        id: content
        x: 20; y: 20
        width: card.contentWidth
        spacing: 12

        // Header: title on the left, when the quote was fetched on the right
        Item {
            width: parent.width
            height: 22
            Text {
                text: "  QUOTE"
                color: card.shell.accent
                font { family: card.shell.font; pixelSize: 14; bold: true; letterSpacing: 2 }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: card.shell.fetchedAt ? "  " + Qt.formatDateTime(new Date(card.shell.fetchedAt), "HH:mm") : ""
                color: card.shell.dim
                font { family: card.shell.font; pixelSize: 11 }
            }
        }

        // The quote, or a placeholder until the first one arrives
        Text {
            width: parent.width
            text: card.q ? card.q.text : card.shell.loading ? "Fetching a quote…" : "No quote yet. Retrying in a few minutes."
            color: card.q ? card.shell.fg : card.shell.dim
            wrapMode: Text.Wrap
            maximumLineCount: 5
            elide: Text.ElideRight
            lineHeight: 1.15
            font { family: card.shell.font; pixelSize: 13; italic: card.q !== null }
        }

        // Author, right-aligned
        Text {
            width: parent.width
            visible: card.q !== null && card.q.author !== ""
            horizontalAlignment: Text.AlignRight
            text: card.q ? "— " + card.q.author : ""
            color: card.shell.accent
            elide: Text.ElideLeft
            font { family: card.shell.font; pixelSize: 11; bold: true }
        }
    }
}
