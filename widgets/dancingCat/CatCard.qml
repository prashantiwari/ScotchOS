// The cat card: header with the tempo, and the current frame of ASCII.
import QtQuick

Rectangle {
    id: card
    required property var shell
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

        // Header: title on the left, tempo on the right
        Item {
            width: parent.width
            height: 22
            Text {
                text: "\u{F011B}  DANCING CAT"
                color: card.shell.accent
                font { family: card.shell.font; pixelSize: 14; bold: true; letterSpacing: 2 }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "\u{F075A}  " + card.shell.bpm + " BPM"
                color: card.shell.dim
                font { family: card.shell.font; pixelSize: 11 }
            }
        }

        // 62 x 26 characters at 5.4 x 11 px, the cell make_frames.py renders for (a different one stretches the cat)
        Item {
            width: parent.width
            height: 286

            // One laid-out Text per frame, only the current one shown: re-laying out 1600 glyphs each tick is the costly part.
            Repeater {
                model: card.shell.frames
                Text {
                    required property string modelData
                    required property int index
                    visible: index === card.shell.frame
                    text: modelData
                    textFormat: Text.PlainText
                    color: card.shell.fg
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 11
                    font { family: card.shell.font; pixelSize: 9 }
                }
            }
        }
    }
}
