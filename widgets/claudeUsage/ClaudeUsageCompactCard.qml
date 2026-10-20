// The compact card (size = compact): one line with the two percentages, no bars or countdowns.
import QtQuick

Rectangle {
    id: card
    required property var shell
    readonly property var u: shell.usage

    width: line.implicitWidth + 32
    height: line.implicitHeight + 20
    radius: 18
    color: Qt.alpha(shell.bg, 0.78)
    border { width: 1; color: Qt.alpha(shell.accent, 0.35) }

    function pct(l) { return l ? Math.round(l.pct) + "%" : "–" }
    function tint(l) { return l && l.pct >= shell.warn ? "#ff6b6b" : shell.fg }

    Row {
        id: line
        anchors.centerIn: parent
        spacing: 10

        // The icon turns amber while the reading is stale or the last fetch failed, as the full card's status line would.
        Text {
            text: "󰚩"
            color: card.shell.error || card.shell.stale ? "#f0b429" : card.shell.accent
            font { family: card.shell.font; pixelSize: 14; bold: true }
        }
        Repeater {
            model: [{ name: "5h", key: "fiveHour" }, { name: "7d", key: "sevenDay" }]

            Row {
                id: item
                required property var modelData
                readonly property var l: card.u ? card.u[modelData.key] : null
                spacing: 5
                Text {
                    text: item.modelData.name
                    color: card.shell.dim
                    font { family: card.shell.font; pixelSize: 12 }
                }
                Text {
                    text: card.pct(item.l)
                    color: card.tint(item.l)
                    font { family: card.shell.font; pixelSize: 12; bold: true }
                }
            }
        }
    }
}
