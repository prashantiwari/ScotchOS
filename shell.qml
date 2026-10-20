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
import "settings"
import "tools/dailyTheoryClient"

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

    // Parsed into { section: { key: value } }, or null when there's no [enabled] section.
    function parseConf(text) {
        const out = {};
        let section = out[""] = {};
        for (const line of text.split("\n")) {
            const l = line.replace(/#.*/, "").trim();
            const s = l.match(/^\[([\w-]+)\]$/);
            if (s) { section = out[s[1]] = out[s[1]] ?? {}; continue; }
            const m = l.match(/^(\w+)\s*=\s*(.*)$/);
            if (m) section[m[1]] = m[2];
        }
        return out.enabled ? out : null;
    }

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

    // Sets `key = value` under [section] (used by the settings window). Only the value changes, so the
    // line's alignment and comment stay; a missing key goes after the section's last setting.
    function setConf(section, key, value) {
        const lines = confText.split("\n");
        let cur = "", at = -1;
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i].replace(/#.*/, "").trim();
            const s = l.match(/^\[([\w-]+)\]$/);
            if (s) { cur = s[1]; if (cur === section) at = i; continue; }
            if (cur !== section || !l) continue;
            const m = lines[i].match(/^(\s*(\w+)\s*=\s*)(.*?)(\s*#.*)?$/);
            if (m && m[2] === key) {
                if (m[3] === String(value)) return;
                // Pad or trim the gap before a comment so it stays in its column.
                const gap = String(value).length - m[3].length;
                let rest = m[4] ?? "";
                if (rest && gap < 0) rest = " ".repeat(-gap) + rest;
                else if (rest && gap > 0) rest = rest.replace(new RegExp("^ {0," + gap + "}( )"), "$1");
                // An empty `key =` has no space after the "=" to keep.
                lines[i] = m[1] + (/\s$/.test(m[1]) || value === "" ? "" : " ") + value + rest;
                at = -2;
                break;
            }
            at = i;
        }
        if (at === -1) lines.push("", "[" + section + "]", key + " = " + value);
        else if (at >= 0) lines.splice(at + 1, 0, key + " = " + value);
        const text = lines.join("\n");
        confFile.setText(text);     // atomic (temp file + rename), like bin/scotchos
        applyConf(text);
    }

    FileView {
        id: confFile
        path: Quickshell.shellDir + "/scotchos.conf"
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyConf(text())
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

    // ---- dailyTheory client: `scotchos theory` / the "Daily Theory" launcher entry opens its window ----
    LazyLoader {
        active: root.enabled("dailytheory")
        DailyTheory { core: root }
    }

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
