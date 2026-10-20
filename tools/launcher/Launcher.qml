// Launcher: one input over several providers (apps, YouTube, ScotchOS commands). Loaded while `launcher` is on;
// it runs nothing until the window opens, and the window exists only while open.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: l
    required property var core

    property bool open: false

    // `scotchos launcher` (qs ipc call launcher toggle), which the keybind runs.
    IpcHandler {
        target: "launcher"
        function open(): void { l.open = true }
        function close(): void { l.open = false }
        function toggle(): void { l.open = !l.open }
    }

    // ---- Providers: the order is the order Tab cycles through them ----
    CommandsProvider { id: commands; core: l.core }
    YouTubeProvider { id: youtube; core: l.core }
    AppsProvider { id: apps; core: l.core }
    readonly property var providers: [commands, youtube, apps]

    LazyLoader {
        active: l.open
        LauncherWindow { launcher: l }
    }
}
