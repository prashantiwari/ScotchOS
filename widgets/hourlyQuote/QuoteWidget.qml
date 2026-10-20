// ScotchOS Hourly Quote: a new quote from the web every hour, on the desktop layer of every screen.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../common"
import "../../common/http.js" as Http

DesktopWidget {
    id: w
    section: "quote"

    // ---- Settings ----
    readonly property string place: placeSetting("bottom-right")
    readonly property int intervalMin: Math.max(1, num("interval", 60))

    // ---- The quote ----
    // { text, author }, kept in quote.json in the cache so a restart shows the last one right away
    // and doesn't fetch again before the hour is up.
    property var quote: null
    property real fetchedAt: 0      // ms since epoch, 0 = never
    property real lastTry: 0
    property bool loading: false
    property bool cacheRead: false  // the cached quote may make a fetch unnecessary, so wait for it
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
        Http.get(src.url, {}, r => {
            try {
                if (!r.ok) throw "HTTP " + r.status;
                if (!r.data) throw "not JSON";
                const q = src.parse(r.data);
                if (!q.text) throw "empty quote";
                w.quote = { text: q.text.trim(), author: (q.author ?? "").trim() };
                w.fetchedAt = Date.now();
                w.loading = false;
                cache.setText(JSON.stringify({ quote: w.quote, fetchedAt: w.fetchedAt }));
            } catch (e) {
                console.warn("hourlyQuote:", src.url, e);
                w.fetchQuote(i + 1);
            }
        });
    }

    function tick() {
        const now = Date.now();
        if (cacheRead && !loading && now - fetchedAt >= intervalMin * 60000 && now - lastTry >= retryMs)
            fetchQuote();
    }

    FileView {
        id: cache
        path: Quickshell.cacheDir + "/quote.json"
        onLoaded: {
            try {
                const c = JSON.parse(text());
                w.quote = c.quote;
                w.fetchedAt = c.fetchedAt;
            } catch (e) {}
            w.cacheRead = true;
            if (w.anyEmpty) w.tick();
        }
        onLoadFailed: { w.cacheRead = true; if (w.anyEmpty) w.tick(); }
    }

    // Checks once a minute instead of one long timer, so it also catches up right after a suspend.
    // Only while shown: a quote nobody sees isn't worth fetching.
    Timer {
        interval: 60000
        repeat: true
        running: w.anyEmpty
        triggeredOnStart: true
        onTriggered: w.tick()
    }

    // ---- One panel per screen, only where the workspace is empty ----
    Variants {
        model: Quickshell.screens

        DesktopPanel {
            layerName: "scotchos-quote"
            visible: w.workspaceEmpty(modelData)
            place: w.place
            marginX: w.marginX
            marginY: w.marginY
            implicitWidth: card.width
            implicitHeight: card.height

            QuoteCard {
                id: card
                shell: w
            }
        }
    }
}
