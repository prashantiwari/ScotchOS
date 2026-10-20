// ScotchOS system dashboard: a desktop-layer panel on every screen, placed per [dashboard] in scotchos.conf.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../common"

DesktopWidget {
    id: w
    section: "dashboard"

    function tempColor(t) {
        if (t === null || t === undefined) return dim;
        return t < 60 ? "#7ee787" : t < 80 ? "#f0b429" : "#ff6b6b";
    }

    // ---- Settings ----
    readonly property string layout: str("layout", "vertical", ["vertical", "horizontal", "square"])
    readonly property bool horizontal: layout === "horizontal"
    // Where the card sits: one of the nine spots, or "auto" (left edge, or bottom edge for horizontal).
    readonly property string position: str("position", "auto", ["auto"].concat(core.positions))
    readonly property string place: position !== "auto" ? position : horizontal ? "bottom" : "left"

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
        command: ["python3", Quickshell.shellDir + "/widgets/systemDashboard/stats.py"]
        running: w.anyEmpty && w.collectorAlive
        stdout: SplitParser {
            onRead: line => {
                try {
                    const s = JSON.parse(line);
                    w.stats = s;
                    w.cpuHistory = w.push(w.cpuHistory, s.cpu);
                    w.rxHistory = w.push(w.rxHistory, s.net.rx);
                    w.txHistory = w.push(w.txHistory, s.net.tx);
                    if (s.temps.cpu !== null)
                        w.tempHistory = w.push(w.tempHistory, s.temps.cpu);
                } catch (e) {
                    console.warn("stats.py:", e);
                }
            }
        }
        // Restart the collector if it ever dies.
        onExited: { w.collectorAlive = false; restartTimer.start(); }
    }
    Timer { id: restartTimer; interval: 2000; onTriggered: w.collectorAlive = true }

    // ---- One panel per screen, only where the workspace is empty ----
    Variants {
        model: Quickshell.screens

        DesktopPanel {
            layerName: "scotchos-dashboard"
            visible: w.workspaceEmpty(modelData)
            place: w.place
            marginX: w.marginX
            marginY: w.marginY
            implicitWidth: card.width
            implicitHeight: card.height

            Dashboard {
                id: card
                shell: w
            }
        }
    }
}
