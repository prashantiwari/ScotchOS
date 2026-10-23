// Keybinds: see and change Hyprland's binds. Loaded while `keybinds` is on; it runs nothing until the window
// opens (keybinds.py reads the binds then), and the window exists only while open.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: k
    required property var core

    property bool open: false

    // `scotchos keybinds` (qs ipc call keybinds toggle), which Super + Ctrl + / runs.
    IpcHandler {
        target: "keybinds"
        function open(): void { k.open = true }
        function close(): void { k.open = false }
        function toggle(): void { k.open = !k.open }
    }

    LazyLoader {
        active: k.open
        KeybindsWindow { kb: k }
    }
}
