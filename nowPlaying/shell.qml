// ScotchOS Now Playing: the current MPRIS track with a cava visualizer, on the desktop layer of every screen.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
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

    // ---- Settings from nowplaying.conf (`key = value` lines, # comments) ----
    property string place: "right"
    property int marginX: 20
    property int marginY: 20
    property bool showPaused: true

    readonly property var positions: ["top-left", "top", "top-right", "left", "center", "right",
                                      "bottom-left", "bottom", "bottom-right"]

    FileView {
        path: Quickshell.shellDir + "/nowplaying.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const conf = {};
            for (const line of text().split("\n")) {
                const m = line.replace(/#.*/, "").match(/^\s*(\w+)\s*=\s*(\S+)\s*$/);
                if (m) conf[m[1]] = m[2];
            }

            let place = conf.position ?? "right";
            if (!root.positions.includes(place)) {
                console.warn("nowplaying.conf: unknown position", place, "- using right");
                place = "right";
            }
            function px(key) {
                const n = parseInt(conf[key] ?? "20");
                return isNaN(n) ? 20 : n;
            }

            root.place = place;
            root.marginX = px("margin_x");
            root.marginY = px("margin_y");
            root.showPaused = (conf.show_paused ?? "yes") !== "no";
        }
    }

    // ---- The player to show ----
    // The one playing right now; when it pauses, it stays the choice until another one plays
    // or it goes away. Brave, Spotify, VLC... each tab or app is its own MPRIS player.
    readonly property var players: Mpris.players.values
    readonly property var playing: players.find(p => p.isPlaying) ?? null
    property var player: null

    function pick() {
        if (playing) player = playing;
        else if (!players.includes(player)) player = players[0] ?? null;
    }
    onPlayingChanged: pick()
    onPlayersChanged: pick()

    readonly property bool isPlaying: player !== null && player.isPlaying
    readonly property bool shown: player !== null && player.trackTitle !== "" && (isPlaying || showPaused)

    // MPRIS doesn't push the playback position, so ask for it once a second while playing.
    Timer {
        interval: 1000
        repeat: true
        running: root.isPlaying && root.anyEmpty && root.player.positionSupported
        onTriggered: root.player.positionChanged()
    }

    function fmtTime(sec) {
        sec = Math.max(0, Math.floor(sec));
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(s).padStart(2, "0");
    }

    // ---- Visualizer from cava (one line of `barCount` values 0..100 per frame) ----
    readonly property int barCount: 32   // must match `bars` in cava.conf
    readonly property var silence: Array(barCount).fill(0)
    property var bars: silence

    Process {
        id: cava
        command: ["cava", "-p", Quickshell.shellDir + "/cava.conf"]
        // Only while something plays and the card is shown on some screen, so a paused or hidden widget costs nothing.
        running: root.isPlaying && root.shown && root.anyEmpty
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";", root.barCount).map(Number);
                if (v.length === root.barCount) root.bars = v;
            }
        }
        onRunningChanged: if (!running) root.bars = root.silence
    }

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
            visible: root.shown && root.workspaceEmpty(modelData)

            WlrLayershell.layer: WlrLayer.Bottom          // above wallpaper, below windows
            WlrLayershell.namespace: "scotchos-nowplaying"
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

            MediaCard {
                id: card
                shell: root
            }
        }
    }
}
