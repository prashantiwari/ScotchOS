// ScotchOS Now Playing: the current MPRIS track with a cava visualizer, on the desktop layer of every screen.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../../common"

DesktopWidget {
    id: w
    section: "nowplaying"

    // ---- Settings ----
    readonly property string place: placeSetting("right")
    readonly property bool showPaused: flag("show_paused", true)
    // card: art, details, progress and bars; radial: only the art in a wavy circle with rays around it.
    readonly property string layout: str("layout", "card", ["card", "radial"])
    // middle: bars mirrored around the art row; bar: bars rising from the progress bar.
    readonly property string visualizer: str("visualizer", "middle", ["middle", "bar"])
    // Radial layout's scale in percent of its base size (art 180 px across), kept to what fits a 720 px screen.
    readonly property real radialScale: Math.max(50, Math.min(160, num("radial_size", 100))) / 100

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
    Component.onCompleted: pick()

    readonly property bool isPlaying: player !== null && player.isPlaying
    readonly property bool shown: player !== null && player.trackTitle !== "" && (isPlaying || showPaused)

    // MPRIS doesn't push the playback position, so ask for it once a second while playing.
    Timer {
        interval: 1000
        repeat: true
        running: w.isPlaying && w.anyEmpty && w.player.positionSupported
        onTriggered: w.player.positionChanged()
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
        command: ["cava", "-p", Quickshell.shellDir + "/widgets/nowPlaying/cava.conf"]
        // Only while something plays and the card is shown on some screen, so a paused or hidden widget costs nothing.
        running: w.isPlaying && w.shown && w.anyEmpty
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";", w.barCount).map(Number);
                if (v.length === w.barCount) w.bars = v;
            }
        }
        onRunningChanged: if (!running) w.bars = w.silence
    }

    // ---- One panel per screen, only where the workspace is empty and there's a track ----
    Variants {
        model: Quickshell.screens

        DesktopPanel {
            layerName: "scotchos-nowplaying"
            visible: w.shown && w.workspaceEmpty(modelData)
            place: w.place
            marginX: w.marginX
            marginY: w.marginY
            implicitWidth: card.width
            implicitHeight: card.height

            // The card for the current `layout`; the other one isn't created.
            Loader {
                id: card
                sourceComponent: w.layout === "radial" ? radialCard : mediaCard
                Component { id: mediaCard; MediaCard { shell: w } }
                Component { id: radialCard; RadialCard { shell: w } }
            }
        }
    }
}
