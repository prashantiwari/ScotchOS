// The usage card: header with the time the 5-hour window resets, then a bar and reset countdown per limit.
import QtQuick

Rectangle {
    id: card
    required property var shell
    readonly property var u: shell.usage
    readonly property real contentWidth: 340

    width: content.width + 40
    height: content.implicitHeight + 40
    radius: 18
    color: Qt.alpha(shell.bg, 0.78)
    border { width: 1; color: Qt.alpha(shell.accent, 0.35) }

    // "2h 13m", "3d 4h", from the shared once-a-minute `now`.
    function resetsIn(t) {
        if (!t) return "";
        const m = Math.ceil((t - shell.now) / 60000);
        if (m <= 0) return "reset, refreshing…";
        const d = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60);
        return "resets in " + (d ? d + "d " + h + "h" : h ? h + "h " + m % 60 + "m" : m + "m");
    }

    Column {
        id: content
        x: 20; y: 20
        width: card.contentWidth
        spacing: 12

        // Header: title on the left, when the 5-hour window resets on the right
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
                      ? (card.shell.stale ? "stale " : "") + "  " + card.shell.resetClock : ""
                color: card.shell.stale ? "#f0b429" : card.shell.dim
                font { family: card.shell.font; pixelSize: 11 }
            }
        }

        // One row per limit: name and percentage, a bar, the reset countdown
        Repeater {
            model: [{ name: "5-hour", key: "fiveHour" }, { name: "7-day", key: "sevenDay" }]

            Column {
                id: row
                required property var modelData
                readonly property var l: card.u ? card.u[modelData.key] : null
                readonly property color tint: l && l.pct >= card.shell.warn ? "#ff6b6b" : card.shell.accent
                width: content.width
                spacing: 5
                visible: l !== null

                Item {
                    width: parent.width
                    height: 18
                    Text {
                        text: row.modelData.name
                        color: card.shell.fg
                        font { family: card.shell.font; pixelSize: 12; bold: true }
                    }
                    Text {
                        anchors.right: parent.right
                        text: row.l ? Math.round(row.l.pct) + " %" : ""
                        color: row.tint
                        font { family: card.shell.font; pixelSize: 12; bold: true }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: Qt.alpha(card.shell.accentDim, 0.5)
                    Rectangle {
                        width: row.l ? parent.width * Math.min(1, Math.max(0, row.l.pct / 100)) : 0
                        height: parent.height
                        radius: 4
                        color: row.tint
                    }
                }
                Text {
                    text: row.l ? card.resetsIn(row.l.resetsAt) : ""
                    color: card.shell.dim
                    font { family: card.shell.font; pixelSize: 10 }
                }
            }
        }

        // Placeholder before the first reading, or why the last fetch failed
        Text {
            width: parent.width
            visible: text !== ""
            text: card.shell.error ? (card.u ? "Last fetch failed: " : "") + card.shell.error
                  : card.u ? "" : "Fetching usage…"
            color: card.shell.error ? "#f0b429" : card.shell.dim
            wrapMode: Text.Wrap
            font { family: card.shell.font; pixelSize: 11 }
        }
    }
}
