// ScotchOS: every desktop widget in one Quickshell process, switched on and off in scotchos.conf.
// This file holds what the widgets share: the wallbash colors, the settings, and which screens show an
// empty workspace. Each widget lives in widgets/<name>/ and is only loaded while it's enabled.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "widgets/systemDashboard"
import "widgets/nowPlaying"
import "widgets/hourlyQuote"

ShellRoot {
    id: root

    // ---- Wallbash colors (follow HyDE theme / wallpaper changes) ----
    property var dcol: ({})
    function hex(key, fallback) { return dcol[key] ? "#" + dcol[key] : fallback }
    readonly property color bg: hex("dcol_pry1", "#1e1e2e")
    readonly property color fg: hex("dcol_txt1", "#ffffff")
    readonly property color accent: hex("dcol_1xa7", "#cba6f7")
    readonly property color accentDim: hex("dcol_1xa3", "#585b70")
    readonly property color dim: Qt.alpha(fg, 0.6)
    readonly property string font: "JetBrainsMono Nerd Font"

    FileView {
        path: Quickshell.env("HOME") + "/.cache/hyde/wallbash/scotchos.dcol"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const out = {};
            for (const line of text().split("\n")) {
                const m = line.match(/^(dcol_\w+)="([0-9A-Fa-f]{6})"$/);
                if (m) out[m[1]] = m[2];
            }
            root.dcol = out;
        }
    }

    // ---- Settings from scotchos.conf: [section] headers, `key = value` lines, # comments ----
    // conf.<section>.<key> is the raw string; widgets read theirs through DesktopWidget's str / num / flag.
    property var conf: ({})
    readonly property var positions: ["top-left", "top", "top-right", "left", "center", "right",
                                      "bottom-left", "bottom", "bottom-right"]

    function isYes(v) { return ["yes", "on", "true", "1"].includes(String(v).toLowerCase()) }
    // A widget missing from [enabled] stays off.
    function enabled(name) { return isYes(conf.enabled?.[name] ?? "no") }

    FileView {
        path: Quickshell.shellDir + "/scotchos.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const out = {};
            let section = out[""] = {};
            for (const line of text().split("\n")) {
                const l = line.replace(/#.*/, "").trim();
                const s = l.match(/^\[([\w-]+)\]$/);
                if (s) { section = out[s[1]] = out[s[1]] ?? {}; continue; }
                const m = l.match(/^(\w+)\s*=\s*(.*)$/);
                if (m) section[m[1]] = m[2];
            }
            // A read caught mid-save (or a broken file) would unload every widget and lose its state.
            if (!out.enabled) {
                console.warn("scotchos.conf: no [enabled] section - keeping the previous settings");
                return;
            }
            root.conf = out;
        }
    }

    // ---- Which screens show a workspace with no tiled windows (widgets are only drawn there) ----
    // Floating windows don't count, unless they're fullscreen.
    function workspaceEmpty(screen) {
        const ws = Hyprland.monitorFor(screen)?.activeWorkspace;
        return !ws || !ws.toplevels.values.some(t => !t.lastIpcObject.floating || t.lastIpcObject.fullscreen > 0);
    }
    // `floating` and `fullscreen` live in lastIpcObject, which only a refresh fills in, so redo one whenever windows change.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindowv2", "changefloatingmode", "fullscreen"].includes(event.name))
                Hyprland.refreshToplevels();
        }
    }
    Component.onCompleted: Hyprland.refreshToplevels()
    readonly property bool anyEmpty: Quickshell.screens.some(s => workspaceEmpty(s))

    // ---- The widgets, each loaded only while enabled ----
    LazyLoader {
        active: root.enabled("dashboard")
        DashboardWidget { core: root }
    }
    LazyLoader {
        active: root.enabled("nowplaying")
        NowPlayingWidget { core: root }
    }
    LazyLoader {
        active: root.enabled("quote")
        QuoteWidget { core: root }
    }
}
