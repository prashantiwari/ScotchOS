// The Now Playing card: album art, title / artist / album, a progress bar, and the cava visualizer.
import QtQuick
import Quickshell.Widgets

Rectangle {
    id: card
    required property var shell
    readonly property var p: shell.player
    readonly property bool playing: shell.isPlaying
    readonly property real contentWidth: 340

    width: content.width + 40
    height: content.implicitHeight + 40
    radius: 18
    color: Qt.alpha(shell.bg, 0.78)
    border { width: 1; color: Qt.alpha(shell.accent, 0.35) }

    // Visualizer: cava's bars behind the art and text, so it adds no height: mirrored around the middle of
    // the art row (`middle`), or rising from the top of the progress bar (`bar`).
    // Flat and faded while paused.
    Row {
        id: viz
        readonly property bool middle: card.shell.visualizer === "middle"
        readonly property real barWidth: (width - spacing * (card.shell.barCount - 1)) / card.shell.barCount
        x: content.x
        y: middle ? content.y + track.y + (track.height - height) / 2
                  : content.y + (progress.visible ? progress.y : content.implicitHeight) - height
        width: content.width
        height: middle ? 88 : 56
        spacing: 3
        opacity: card.playing ? 0.45 : 0.2

        // A fixed model, so the bars are reused and only their heights change each frame.
        Repeater {
            model: card.shell.barCount
            Rectangle {
                required property int index
                readonly property real level: (card.shell.bars[index] ?? 0) / 100
                y: viz.middle ? (viz.height - height) / 2 : viz.height - height
                width: viz.barWidth
                height: Math.max(3, viz.height * level)
                radius: Math.min(2, width / 2)
                color: Qt.alpha(card.shell.accent, 0.45 + 0.55 * level)
            }
        }
    }

    Column {
        id: content
        x: 20; y: 20
        width: card.contentWidth
        spacing: 14

        // Header: title on the left, the player and its state on the right
        Item {
            width: parent.width
            height: 22
            Text {
                text: "  NOW PLAYING"
                color: card.shell.accent
                font { family: card.shell.font; pixelSize: 14; bold: true; letterSpacing: 2 }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: (card.playing ? "  " : "  ") + (card.p ? card.p.identity : "")
                color: card.shell.dim
                font { family: card.shell.font; pixelSize: 11 }
            }
        }

        // Album art and track details
        Row {
            id: track
            width: parent.width
            spacing: 14

            ClippingRectangle {
                width: 88; height: 88
                radius: 12
                color: Qt.alpha(card.shell.accentDim, 0.5)

                Text {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: ""
                    color: card.shell.dim
                    font { family: card.shell.font; pixelSize: 32 }
                }
                Image {
                    id: art
                    anchors.fill: parent
                    source: card.p ? card.p.trackArtUrl : ""
                    sourceSize { width: 176; height: 176 }   // 2x, sharp on scaled screens without holding a full-size cover
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }

            Column {
                width: parent.width - 88 - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    width: parent.width
                    text: card.p ? card.p.trackTitle : ""
                    color: card.shell.fg
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font { family: card.shell.font; pixelSize: 14; bold: true }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: card.p ? card.p.trackArtist : ""
                    color: card.shell.accent
                    elide: Text.ElideRight
                    font { family: card.shell.font; pixelSize: 11; bold: true }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: card.p ? card.p.trackAlbum : ""
                    color: card.shell.dim
                    elide: Text.ElideRight
                    font { family: card.shell.font; pixelSize: 10 }
                }
            }
        }

        // Progress: hidden for players that don't report a length (some live streams)
        Column {
            id: progress
            readonly property bool known: card.p !== null && card.p.lengthSupported && card.p.length > 0
            visible: known
            width: parent.width
            spacing: 4
            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Qt.alpha(card.shell.accentDim, 0.5)
                Rectangle {
                    width: parent.width * (parent.parent.known ? Math.max(0, Math.min(1, card.p.position / card.p.length)) : 0)
                    height: parent.height
                    radius: 2
                    color: card.shell.accent
                }
            }
            Item {
                width: parent.width
                height: 12
                Text {
                    text: parent.parent.known ? card.shell.fmtTime(card.p.position) : ""
                    color: card.shell.dim
                    font { family: card.shell.font; pixelSize: 10 }
                }
                Text {
                    anchors.right: parent.right
                    text: parent.parent.known ? card.shell.fmtTime(card.p.length) : ""
                    color: card.shell.dim
                    font { family: card.shell.font; pixelSize: 10 }
                }
            }
        }

    }
}
