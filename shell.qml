// ScotchOS: every desktop widget in one Quickshell process, switched on and off in ~/.config/scotchos/scotchos.conf.
// This file holds what the widgets share: the wallbash colors, the settings, and which screens show an
// empty workspace. Each widget lives in widgets/<name>/ and is only loaded while it's enabled.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "widgets/systemDashboard"
import "widgets/nowPlaying"
import "widgets/hourlyQuote"
import "widgets/claudeUsage"
import "settings"
import "tools/dailyTheoryClient"
import "tools/launcher"
import "tools/eReader"
import "common/conf.js" as Conf

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

    // ---- Settings from scotchos.conf (confPath below): [section] headers, `key = value` lines, # comments ----
    // Parsing and editing the text is in common/conf.js (tested in common/tests/); reading and writing is here.
    // conf.<section>.<key> is the raw string; widgets read theirs through DesktopWidget's str / num / flag.
    property var conf: ({})
    readonly property var positions: ["top-left", "top", "top-right", "left", "center", "right",
                                      "bottom-left", "bottom", "bottom-right"]

    function isYes(v) { return ["yes", "on", "true", "1"].includes(String(v).toLowerCase()) }
    // A widget missing from [enabled] stays off.
    function enabled(name) { return isYes(conf.enabled?.[name] ?? "no") }

    // Parsed into { section: { key: value } }, or null when there's no [enabled] section.
    function parseConf(text) { return Conf.parse(text) }

    property string confText: ""
    function applyConf(text) {
        const out = parseConf(text);
        // A read caught mid-save (or a broken file) would unload every widget and lose its state.
        if (!out) {
            console.warn("scotchos.conf: no [enabled] section - keeping the previous settings");
            return;
        }
        root.confText = text;
        root.conf = out;
    }

    // Sets `key = value` under [section] (used by the settings window), keeping the line's alignment and comment.
    function setConf(section, key, value) {
        // The file on disk isn't the text the settings came from (a half-saved hand edit): writing would lose it.
        if (confFile.text() !== confText) {
            console.warn("scotchos.conf: the file has changes that weren't applied - not saving", section + "." + key);
            return;
        }
        const text = Conf.set(confText, section, key, value);
        if (text === null) return;
        confFile.setText(text);     // atomic (temp file + rename), like bin/scotchos
        applyConf(text);
    }

    // Removes `key` from [section] (the settings window's reset), so the widget's own fallback applies.
    function removeConf(section, key) {
        if (confFile.text() !== confText) {
            console.warn("scotchos.conf: the file has changes that weren't applied - not saving", section + "." + key);
            return;
        }
        const text = Conf.remove(confText, section, key);
        if (text === null) return;
        confFile.setText(text);
        applyConf(text);
    }

    // `scotchos start` passes the path it resolved; started some other way (Hyprland's autostart running qs),
    // the same XDG path. A symlinked conf is written through (QSaveFile follows the link), not replaced.
    readonly property string confPath: Quickshell.env("SCOTCHOS_CONF")
        || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/scotchos/scotchos.conf"
    FileView {
        id: confFile
        path: root.confPath
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyConf(text())
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) copyDefaults.running = true }
    }
    // First run without `scotchos start`: copy the defaults (never over an existing file), then read them.
    Process {
        id: copyDefaults
        command: ["sh", "-c", '[ -e "$2" ] || { mkdir -p "$(dirname "$2")" && cp "$1" "$2"; }', "sh",
                  Quickshell.shellDir + "/scotchos.default.conf", root.confPath]
        // Only on success, so a conf dir that can't be written doesn't loop.
        onExited: code => { if (code === 0) confFile.reload(); else console.warn("scotchos.conf: couldn't create", root.confPath) }
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

    // The screen with the focused monitor, for windows that open there (read once; not for bindings).
    function focusedScreen() {
        return Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
    }

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
    LazyLoader {
        active: root.enabled("claudeusage")
        ClaudeUsageWidget { core: root }
    }

    // ---- dailyTheory client: `scotchos theory` / the "Daily Theory" launcher entry opens its window ----
    LazyLoader {
        active: root.enabled("dailytheory")
        DailyTheory { core: root }
    }

    // ---- E-reader: `scotchos reader` / the "E-reader" launcher entry opens its window ----
    // `reader` is null while it's off; the launcher's "Continue reading" calls it.
    readonly property var reader: readerLoader.item
    LazyLoader {
        id: readerLoader
        active: root.enabled("reader")
        Reader { core: root }
    }

    // ---- Launcher: `scotchos launcher` (the keybind) opens its window ----
    LazyLoader {
        active: root.enabled("launcher")
        Launcher { core: root }
    }

    // ---- Buttons in the settings window (type "action"): widgets react to their own section's actions ----
    signal action(string section, string name)

    // ---- Settings window: `scotchos settings` (qs ipc call settings toggle); exists only while open ----
    property bool settingsOpen: false
    IpcHandler {
        target: "settings"
        function open(): void { root.settingsOpen = true }
        function close(): void { root.settingsOpen = false }
        function toggle(): void { root.settingsOpen = !root.settingsOpen }
    }
    LazyLoader {
        active: root.settingsOpen
        SettingsWindow { core: root }
    }
}
