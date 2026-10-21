// The reader window, tiled on its own workspace (Reader picks an empty one). Created only while open and not fullscreen.
import QtQuick
import Quickshell

FloatingWindow {
    id: win
    required property var reader
    readonly property var scr: reader.screen

    // No fixed size, so Hyprland tiles it: alone on its workspace, it fills the screen.
    implicitWidth: Math.round(scr.width * 0.7)
    implicitHeight: Math.round(scr.height * 0.85)
    title: "E-reader"
    color: reader.core.bg
    onClosed: if (!reader.fullscreen) reader.open = false

    ReaderContent {
        anchors.fill: parent
        reader: win.reader
    }
}
