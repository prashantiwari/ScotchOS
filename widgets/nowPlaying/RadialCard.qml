// The radial Now Playing look: just the album art in a wavy circle, with cava's bars as rays around it.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

Item {
    id: card
    required property var shell
    readonly property var p: shell.player
    readonly property bool playing: shell.isPlaying

    // ---- Geometry (base sizes times the radial_size setting) ----
    readonly property real k: shell.radialScale
    readonly property real artRadius: 90 * k
    readonly property real waveDepth: 5 * k     // how far the edge bumps in and out
    readonly property int waves: 10             // bumps around the edge
    readonly property real rayGap: 10 * k       // between the edge's outermost bump and the rays
    readonly property real rayMin: 6 * k
    readonly property real rayMax: 46 * k
    readonly property real rayWidth: Math.max(2, 3 * k)
    readonly property int rays: shell.barCount * 2   // cava's bars on the right, mirrored on the left
    readonly property real center: artRadius + waveDepth + rayGap + rayMax + 4 * k

    width: center * 2
    height: center * 2

    // The wavy outline, computed once.
    readonly property var outline: {
        const pts = [], n = 240;
        for (let i = 0; i <= n; i++) {
            const a = i / n * 2 * Math.PI;
            const r = artRadius + waveDepth * Math.sin(waves * a);
            pts.push(Qt.point(artRadius + waveDepth + r * Math.cos(a), artRadius + waveDepth + r * Math.sin(a)));
        }
        return pts;
    }

    // ---- Rays: one per bar, each a fixed delegate turned to its angle; only the length changes per frame ----
    Repeater {
        model: card.rays
        Item {
            required property int index
            readonly property real level: (card.shell.bars[index < card.shell.barCount ? index : card.rays - 1 - index] ?? 0) / 100
            anchors.fill: parent
            rotation: index * 360 / card.rays
            opacity: card.playing ? 1 : 0.35

            Rectangle {
                width: card.rayWidth
                height: card.rayMin + (card.rayMax - card.rayMin) * parent.level
                radius: width / 2
                x: card.center - width / 2
                y: card.center - card.artRadius - card.waveDepth - card.rayGap - height
                color: Qt.alpha(card.shell.accent, 0.55 + 0.45 * parent.level)
            }
        }
    }

    // ---- Album art in the wavy shape ----
    Item {
        id: blob
        width: (card.artRadius + card.waveDepth) * 2
        height: width
        anchors.centerIn: parent

        // Shown when there's no cover, and under it while it loads.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Qt.alpha(card.shell.accentDim, 0.5)
                strokeWidth: -1
                PathPolyline { path: card.outline }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: ""
            color: card.shell.dim
            font { family: card.shell.font; pixelSize: Math.round(48 * card.k) }
        }

        Image {
            id: art
            anchors.fill: parent
            visible: false   // drawn through the mask below
            source: card.p ? card.p.trackArtUrl : ""
            // 2x, sharp on scaled screens without holding a full-size cover.
            sourceSize { width: Math.round(blob.width * 2); height: Math.round(blob.width * 2) }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Shape {
            id: mask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "white"
                strokeWidth: -1
                PathPolyline { path: card.outline }
            }
        }
        MultiEffect {
            anchors.fill: parent
            visible: art.status === Image.Ready
            source: art
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
}
