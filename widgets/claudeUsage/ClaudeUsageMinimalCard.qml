// The minimal card (size = minimal): the full card's title bar, then just the two percentages in large type.
import QtQuick

Rectangle {
    id: card
    required property var shell
    readonly property var u: shell.usage
    // Narrower than the other cards: just enough for the title and the time, so the numbers sit close together.
    readonly property real contentWidth: 240

    width: content.width + 40
    height: content.implicitHeight + 40
    radius: 18
    color: Qt.alpha(shell.bg, 0.78)
    border { width: 1; color: Qt.alpha(shell.accent, 0.35) }

    Column {
        id: content
        x: 20; y: 20
        width: card.contentWidth
        spacing: 14

        // Title bar: title on the left, when the numbers were fetched on the right (amber when stale or failing)
        Item {
            width: parent.width
            height: 22
            Text {
                text: "󰚩  CLAUDE USAGE"
                color: card.shell.accent
                font { family: card.shell.font; pixelSize: 14; bold: true; letterSpacing: 2 }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: card.shell.loading ? "  …" : card.shell.fetchedAt
                      ? (card.shell.stale ? "stale " : "") + "  " + Qt.formatDateTime(new Date(card.shell.fetchedAt), "HH:mm") : ""
                color: card.shell.stale || card.shell.error ? "#f0b429" : card.shell.dim
                font { family: card.shell.font; pixelSize: 11 }
            }
        }

        // The two percentages, side by side, each with its name under it
        Row {
            width: parent.width

            Repeater {
                model: [{ name: "5-hour", key: "fiveHour" }, { name: "7-day", key: "sevenDay" }]

                Column {
                    id: item
                    required property var modelData
                    readonly property var l: card.u ? card.u[modelData.key] : null
                    width: content.width / 2
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: item.l ? Math.round(item.l.pct) + "%" : "–"
                        color: item.l && item.l.pct >= card.shell.warn ? "#ff6b6b" : card.shell.fg
                        font { family: card.shell.font; pixelSize: 36; bold: true }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: item.modelData.name
                        color: card.shell.dim
                        font { family: card.shell.font; pixelSize: 11; letterSpacing: 1 }
                    }
                }
            }
        }
    }
}
