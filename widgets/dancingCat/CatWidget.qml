// ScotchOS Dancing Cat: a 3D ASCII cat dancing on the desktop layer of every screen.
import QtQuick
import Quickshell
import "../../common"
import "frames.js" as Frames

DesktopWidget {
    id: w
    section: "dancingcat"

    // ---- Settings ----
    readonly property string place: placeSetting("bottom")
    readonly property int bpm: Math.min(240, Math.max(30, num("bpm", 120)))

    // ---- The dance ----
    // The frames are baked by make_frames.py: stepping through strings costs far less than ray marching in QML.
    property int frame: 0
    readonly property var frames: Frames.frames

    // Only while shown, and it picks up where it stopped.
    Timer {
        interval: Math.round(60000 / (w.bpm * Frames.perBeat))
        repeat: true
        running: w.anyEmpty
        onTriggered: w.frame = (w.frame + 1) % Frames.frames.length
    }

    // ---- One panel per screen, only where the workspace is empty ----
    Variants {
        model: Quickshell.screens

        DesktopPanel {
            layerName: "scotchos-dancingcat"
            visible: w.workspaceEmpty(modelData)
            place: w.place
            marginX: w.marginX
            marginY: w.marginY
            implicitWidth: card.width
            implicitHeight: card.height

            CatCard {
                id: card
                shell: w
            }
        }
    }
}
