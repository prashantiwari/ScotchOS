// ScotchOS Claude Usage: the Claude plan's 5-hour and 7-day limits, as /usage shows them, on every screen.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../common"

DesktopWidget {
    id: w
    section: "claudeusage"

    // ---- Settings ----
    readonly property string place: placeSetting("top-right")
    readonly property string size: str("size", "full", ["full", "compact", "minimal"])
    readonly property int intervalMin: Math.max(5, num("interval", 30))
    readonly property int warn: Math.min(100, Math.max(1, num("warn", 80)))

    // ---- Usage ----
    // { fiveHour: { pct, resetsAt }, sevenDay: { pct, resetsAt } }, resetsAt in ms since epoch. Kept in
    // claude-usage.json in the cache (numbers only, never the token) so a restart shows the last reading.
    property var usage: null
    property real fetchedAt: 0      // ms since epoch, 0 = never
    property real lastTry: 0
    property bool loading: false
    property string error: ""       // why the last fetch failed, "" when it worked
    property real now: Date.now()   // for the countdowns, moved once a minute
    readonly property int retryMs: 10 * 60 * 1000
    readonly property bool stale: fetchedAt > 0 && now - fetchedAt > 2 * intervalMin * 60000

    readonly property string endpoint: "https://api.anthropic.com/api/oauth/usage"
    property var creds: null        // claudeAiOauth from Claude Code's credentials file
    property bool startedUp: false

    function limit(d) {
        if (!d || typeof d.utilization !== "number") throw "no utilization in the response";
        return { pct: d.utilization, resetsAt: Date.parse(d.resets_at) || 0 };
    }

    function fetchUsage() {
        lastTry = Date.now();
        // Only reads the token: refreshing it would race Claude Code, which owns the file.
        if (!creds?.accessToken) { error = "not logged in to Claude Code"; return; }
        if (creds.expiresAt && creds.expiresAt < Date.now()) { error = "token expired - open Claude Code"; return; }
        loading = true;
        const xhr = new XMLHttpRequest();
        xhr.timeout = 15000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            w.loading = false;
            try {
                if (xhr.status === 401) throw "token rejected - open Claude Code";
                if (xhr.status === 429) throw "rate-limited, retrying later";
                if (xhr.status !== 200) throw "HTTP " + xhr.status;
                const d = JSON.parse(xhr.responseText);
                w.usage = { fiveHour: w.limit(d.five_hour), sevenDay: w.limit(d.seven_day) };
                w.fetchedAt = Date.now();
                w.error = "";
                cache.setText(JSON.stringify({ usage: w.usage, fetchedAt: w.fetchedAt }));
            } catch (e) {
                console.warn("claudeUsage:", e);
                w.error = String(e);
            }
        };
        xhr.open("GET", endpoint);
        xhr.setRequestHeader("Authorization", "Bearer " + creds.accessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.send();
    }

    function tick() {
        now = Date.now();
        // Before the credentials are read, the startup fetch hasn't happened yet.
        if (!startedUp || loading) return;
        const since = now - lastTry;
        if (error && since < retryMs) return;
        // Also refetch once a window has reset, so the card doesn't keep showing the old percentage.
        const reset = usage && [usage.fiveHour, usage.sevenDay].some(l => l.resetsAt && l.resetsAt < now);
        if (now - fetchedAt >= intervalMin * 60000 || (reset && since >= retryMs))
            fetchUsage();
    }

    // ---- Refresh on demand: `scotchos claude refresh` and the settings window's button ----
    // The cooldown keeps repeated presses from getting the (undocumented) endpoint to rate-limit us.
    readonly property int cooldownMs: 30000
    function refresh() {
        if (loading) return "already fetching";
        const ago = Date.now() - lastTry;
        if (ago < cooldownMs) return "skipped: last fetch " + Math.round(ago / 1000) + " s ago (30 s cooldown)";
        fetchUsage();
        return error && !loading ? error : "fetching";
    }
    IpcHandler {
        target: "claudeusage"
        function refresh(): string { return w.refresh() }
    }
    Connections {
        target: w.core
        function onAction(section, name) { if (section === w.section && name === "refresh") w.refresh() }
    }

    // The first read of the credentials is the shell starting, i.e. a login: always fetch then.
    FileView {
        path: Quickshell.env("HOME") + "/.claude/.credentials.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { w.creds = JSON.parse(text()).claudeAiOauth ?? null; } catch (e) { w.creds = null; }
            if (!w.startedUp) { w.startedUp = true; w.fetchUsage(); }
        }
        onLoadFailed: {
            w.creds = null;
            if (!w.startedUp) { w.startedUp = true; w.fetchUsage(); }
        }
    }

    FileView {
        id: cache
        path: Quickshell.cacheDir + "/claude-usage.json"
        onLoaded: {
            try {
                const c = JSON.parse(text());
                // The startup fetch may already have answered.
                if (c.fetchedAt > w.fetchedAt) { w.usage = c.usage; w.fetchedAt = c.fetchedAt; }
            } catch (e) {}
        }
    }

    // Checks once a minute instead of one long timer, so it also catches up right after a suspend.
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
            layerName: "scotchos-claudeusage"
            visible: w.workspaceEmpty(modelData)
            place: w.place
            marginX: w.marginX
            marginY: w.marginY
            implicitWidth: card.width
            implicitHeight: card.height

            // The card for the current `size`; the other one isn't created.
            Loader {
                id: card
                sourceComponent: w.size === "compact" ? compactCard : w.size === "minimal" ? minimalCard : fullCard
                Component { id: fullCard; ClaudeUsageCard { shell: w } }
                Component { id: compactCard; ClaudeUsageCompactCard { shell: w } }
                Component { id: minimalCard; ClaudeUsageMinimalCard { shell: w } }
            }
        }
    }
}
