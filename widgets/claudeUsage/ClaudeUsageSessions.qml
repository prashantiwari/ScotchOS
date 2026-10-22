// The Claude Code sessions open in terminals, under the usage on the full and minimal cards: a header with
// the busy/open counts, then a dot, the name and the folder per session.
import QtQuick

Column {
    id: list
    required property var shell
    spacing: 6
    visible: shell.showSessions && shell.sessions.length > 0

    Rectangle { width: parent.width; height: 1; color: Qt.alpha(list.shell.accent, 0.2) }
    Item {
        width: parent.width
        height: 18
        Text {
            text: "SESSIONS"
            color: list.shell.dim
            font { family: list.shell.font; pixelSize: 11; bold: true; letterSpacing: 2 }
        }
        Text {
            anchors.right: parent.right
            text: list.shell.busyCount + " busy · " + list.shell.sessions.length
            color: list.shell.dim
            font { family: list.shell.font; pixelSize: 11 }
        }
    }
    // A count as the model, so the rows are reused when a session's status changes.
    Repeater {
        model: list.shell.sessions.length

        Item {
            id: srow
            required property int index
            readonly property var s: list.shell.sessions[index] ?? {}
            readonly property bool busy: s.status === "busy"
            width: list.width
            height: 18

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7; radius: 3.5
                color: srow.busy ? list.shell.accent : srow.s.status === "idle" ? list.shell.dim : "#f0b429"
            }
            Text {
                x: 15
                width: parent.width * 0.45 - 15
                anchors.verticalCenter: parent.verticalCenter
                text: srow.s.name ?? ""
                color: srow.busy ? list.shell.fg : list.shell.dim
                elide: Text.ElideRight
                font { family: list.shell.font; pixelSize: 12; bold: srow.busy }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.55 - 8
                horizontalAlignment: Text.AlignRight
                text: (srow.s.cwd ?? "").replace(list.shell.home, "~") + "  " + (srow.s.status ?? "")
                color: list.shell.dim
                elide: Text.ElideLeft
                font { family: list.shell.font; pixelSize: 10 }
            }
        }
    }
}
