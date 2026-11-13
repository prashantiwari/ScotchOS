// Launcher: one input over several providers (apps, YouTube, private search, ScotchOS commands). Loaded while `launcher` is on;
// it runs nothing until the window opens, and the window exists only while open.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: l
    required property var core

    property bool open: false
    // Picked once on open: a binding to the focused monitor would move the window when focus follows the mouse.
    // `shown` follows `open` but only after `screen` is set, so the window never starts on the old one.
    property var screen: null
    property bool shown: false
    onOpenChanged: { if (open) screen = core.focusedScreen(); shown = open; }

    // The chip the window starts with (read once when it's created); null opens it plain.
    property var startMode: null

    // `scotchos launcher` (qs ipc call launcher toggle), which the keybind runs; `scotchos launcher private` opens it on the Private chip.
    IpcHandler {
        target: "launcher"
        function open(): void { l.startMode = null; l.open = true }
        function close(): void { l.open = false }
        function toggle(): void { l.startMode = null; l.open = !l.open }
        function privateSearch(): void { l.startMode = priv; l.open = !l.open }
    }

    // ---- Providers: the order is the order Tab cycles through them ----
    CommandsProvider { id: commands; core: l.core }
    YouTubeProvider { id: youtube; core: l.core }
    PrivateProvider { id: priv; core: l.core }
    AppsProvider { id: apps; core: l.core }
    readonly property var providers: [commands, youtube, priv, apps]

    LazyLoader {
        active: l.shown
        LauncherWindow { launcher: l }
    }
}
