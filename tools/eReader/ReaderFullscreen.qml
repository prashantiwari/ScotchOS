// Fullscreen (F): an overlay layer over the whole focused monitor, waybar included, holding the keyboard.
// Created only while open and fullscreen; F or Esc goes back to the floating window.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win
    required property var reader

    screen: reader.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "scotchos-reader"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    color: reader.core.bg

    ReaderContent {
        anchors.fill: parent
        reader: win.reader
    }
}
