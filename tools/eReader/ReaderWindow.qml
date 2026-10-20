// The floating reader window: ~70 % × 85 % of the focused screen. Created only while open and not fullscreen.
import QtQuick
import Quickshell
import Quickshell.Hyprland

FloatingWindow {
    id: win
    required property var reader
    readonly property var scr: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    // A fixed size makes Hyprland float the window, like the settings window.
    implicitWidth: Math.round(Math.max(760, scr.width * 0.7))
    implicitHeight: Math.round(Math.max(540, scr.height * 0.85))
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)
    title: "E-reader"
    color: reader.core.bg
    onClosed: if (!reader.fullscreen) reader.open = false

    ReaderContent {
        anchors.fill: parent
        reader: win.reader
    }
}
