// ScotchOS system dashboard: a desktop-layer panel on every screen, placed per dashboard.conf.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

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

    function tempColor(t) {
        if (t === null || t === undefined) return dim;
        return t < 60 ? "#7ee787" : t < 80 ? "#f0b429" : "#ff6b6b";
    }

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

    // ---- Settings from dashboard.conf (`key = value` lines, # comments) ----
    property string layout: "vertical"
    readonly property bool horizontal: layout === "horizontal"
    // Where the card sits: one of the nine spots below, or "auto" (left edge, or bottom edge for horizontal).
    property string position: "auto"
    readonly property string place: position !== "auto" ? position : horizontal ? "bottom" : "left"
    // Distance in px from the screen edge(s) the card touches.
    property int marginX: 20
    property int marginY: 20

    readonly property var positions: ["top-left", "top", "top-right", "left", "center", "right",
                                      "bottom-left", "bottom", "bottom-right"]

    FileView {
        path: Quickshell.shellDir + "/dashboard.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const conf = {};
            for (const line of text().split("\n")) {
                const m = line.replace(/#.*/, "").match(/^\s*(\w+)\s*=\s*(\S+)\s*$/);
                if (m) conf[m[1]] = m[2];
            }

            let layout = conf.layout ?? "vertical";
            if (!["vertical", "horizontal", "square"].includes(layout)) {
                console.warn("dashboard.conf: unknown layout", layout, "- using vertical");
                layout = "vertical";
            }
            let position = conf.position ?? "auto";
            if (position !== "auto" && !root.positions.includes(position)) {
                console.warn("dashboard.conf: unknown position", position, "- using auto");
                position = "auto";
            }
            function px(key) {
                const n = parseInt(conf[key] ?? "20");
                return isNaN(n) ? 20 : n;
            }

            root.layout = layout;
            root.position = position;
            root.marginX = px("margin_x");
            root.marginY = px("margin_y");
        }
    }

    // ---- Stats from stats.py (one JSON line per second) ----
    property var stats: null
    property var cpuHistory: []
    property var tempHistory: []
    property var rxHistory: []
    property var txHistory: []

    function fmtRate(b) {
        const units = ["B/s", "K/s", "M/s", "G/s"];
        let i = 0;
        while (b >= 1000 && i < units.length - 1) { b /= 1024; i++; }
        return (i && b < 10 ? b.toFixed(1) : Math.round(b)) + " " + units[i];
    }

    function push(list, v) {
        const out = list.concat([v]);
        return out.length > 60 ? out.slice(out.length - 60) : out;
    }

    // Only while the card is shown on some screen; collectorAlive drops for 2s to restart it if it dies.
    property bool collectorAlive: true

    Process {
        command: ["python3", Quickshell.shellDir + "/stats.py"]
        running: root.anyEmpty && root.collectorAlive
        stdout: SplitParser {
            onRead: line => {
                try {
                    const s = JSON.parse(line);
                    root.stats = s;
                    root.cpuHistory = root.push(root.cpuHistory, s.cpu);
                    root.rxHistory = root.push(root.rxHistory, s.net.rx);
                    root.txHistory = root.push(root.txHistory, s.net.tx);
                    if (s.temps.cpu !== null)
                        root.tempHistory = root.push(root.tempHistory, s.temps.cpu);
                } catch (e) {
                    console.warn("stats.py:", e);
                }
            }
        }
        // Restart the collector if it ever dies.
        onExited: { root.collectorAlive = false; restartTimer.start(); }
    }
    Timer { id: restartTimer; interval: 2000; onTriggered: root.collectorAlive = true }

    // ---- Only on screens whose workspace has no tiled windows (hidden panels aren't drawn) ----
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

    // ---- One panel per screen ----
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.workspaceEmpty(modelData)

            WlrLayershell.layer: WlrLayer.Bottom          // above wallpaper, below windows
            WlrLayershell.namespace: "scotchos-dashboard"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Normal          // stay clear of waybar, reserve nothing
            exclusiveZone: 0
            mask: Region {}                              // clicks pass through to the desktop

            // Anchor to the edges named in `place`; on an axis with no anchor the compositor centers the card.
            anchors.left: root.place.includes("left")
            anchors.right: root.place.includes("right")
            anchors.top: root.place.startsWith("top")
            anchors.bottom: root.place.startsWith("bottom")
            margins.left: root.marginX
            margins.right: root.marginX
            margins.top: root.marginY
            margins.bottom: root.marginY
            color: "transparent"
            implicitWidth: card.width
            implicitHeight: card.height

            Dashboard {
                id: card
                shell: root
            }
        }
    }
}
