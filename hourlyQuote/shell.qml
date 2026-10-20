// ScotchOS Hourly Quote: a new quote from the web every hour, on the desktop layer of every screen.
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

    // ---- Settings from quote.conf (`key = value` lines, # comments) ----
    property string place: "bottom-right"
    property int marginX: 20
    property int marginY: 20
    property int intervalMin: 60

    readonly property var positions: ["top-left", "top", "top-right", "left", "center", "right",
                                      "bottom-left", "bottom", "bottom-right"]

    FileView {
        path: Quickshell.shellDir + "/quote.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const conf = {};
            for (const line of text().split("\n")) {
                const m = line.replace(/#.*/, "").match(/^\s*(\w+)\s*=\s*(\S+)\s*$/);
                if (m) conf[m[1]] = m[2];
            }

            let place = conf.position ?? "bottom-right";
            if (!root.positions.includes(place)) {
                console.warn("quote.conf: unknown position", place, "- using bottom-right");
                place = "bottom-right";
            }
            function num(key, fallback) {
                const n = parseInt(conf[key] ?? fallback);
                return isNaN(n) ? fallback : n;
            }

            root.place = place;
            root.marginX = num("margin_x", 20);
            root.marginY = num("margin_y", 20);
            root.intervalMin = Math.max(1, num("interval", 60));
        }
    }

    // ---- The quote ----
    // { text, author }, kept in quote.json in the cache so a restart shows the last one right away
    // and doesn't fetch again before the hour is up.
    property var quote: null
    property real fetchedAt: 0      // ms since epoch, 0 = never
    property real lastTry: 0
    property bool loading: false
    readonly property int retryMs: 5 * 60 * 1000

    // Tried in order; each turns the response body into { text, author }.
    readonly property var sources: [
        { url: "https://zenquotes.io/api/random", parse: d => ({ text: d[0].q, author: d[0].a }) },
        { url: "https://dummyjson.com/quotes/random", parse: d => ({ text: d.quote, author: d.author }) },
    ]

    function fetchQuote(i) {
        i = i ?? 0;
        if (i === 0) { lastTry = Date.now(); loading = true; }
        if (i >= sources.length) {
            console.warn("hourlyQuote: every source failed, retrying in", retryMs / 60000, "min");
            loading = false;
            return;
        }
        const src = sources[i];
        const xhr = new XMLHttpRequest();
        xhr.timeout = 15000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            try {
                if (xhr.status !== 200) throw "HTTP " + xhr.status;
                const q = src.parse(JSON.parse(xhr.responseText));
                if (!q.text) throw "empty quote";
                root.quote = { text: q.text.trim(), author: (q.author ?? "").trim() };
                root.fetchedAt = Date.now();
                root.loading = false;
                cache.setText(JSON.stringify({ quote: root.quote, fetchedAt: root.fetchedAt }));
            } catch (e) {
                console.warn("hourlyQuote:", src.url, e);
                root.fetchQuote(i + 1);
            }
        };
        xhr.open("GET", src.url);
        xhr.send();
    }

    function tick() {
        const now = Date.now();
        if (!loading && now - fetchedAt >= intervalMin * 60000 && now - lastTry >= retryMs)
            fetchQuote();
    }

    FileView {
        id: cache
        path: Quickshell.cacheDir + "/quote.json"
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.quote = c.quote;
                root.fetchedAt = c.fetchedAt;
            } catch (e) {}
            root.tick();
        }
        onLoadFailed: root.tick()
    }

    // Checks once a minute instead of one long timer, so it also catches up right after a suspend.
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.tick()
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
            visible: root.workspaceEmpty(modelData)

            WlrLayershell.layer: WlrLayer.Bottom          // above wallpaper, below windows
            WlrLayershell.namespace: "scotchos-quote"
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

            QuoteCard {
                id: card
                shell: root
            }
        }
    }
}
