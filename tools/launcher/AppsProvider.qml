// Installed applications, from the desktop entries Quickshell already reads (no process to spawn).
// Ranked by score.js: how well the name/initials/command match, plus a bonus for apps launched often.
import Quickshell
import Quickshell.Io
import "score.js" as Score

Provider {
    id: p
    name: "Apps"
    glyph: ""
    placeholder: "Search applications"
    keywords: ["app"]
    inDefault: true

    // { desktop id: launches }, in the cache folder (outside git). Written only when something is launched.
    property var counts: ({})
    property FileView store: FileView {
        path: Quickshell.cacheDir + "/launcher-counts.json"
        atomicWrites: true
        printErrors: false          // no file until the first launch
        onLoaded: { try { p.counts = JSON.parse(text()) } catch (e) {} }
    }

    function record(entry) {
        const next = {};
        // Ids that are no longer installed are dropped here, so the file doesn't grow forever.
        for (const e of DesktopEntries.applications.values) if (p.counts[e.id]) next[e.id] = p.counts[e.id];
        next[entry.id] = (next[entry.id] || 0) + 1;
        p.counts = next;
        store.setText(JSON.stringify(next));
    }

    search: q => {
        const apps = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue;
            apps.push({ id: e.id, name: e.name, exec: e.execString, genericName: e.genericName, keywords: e.keywords, entry: e });
        }
        return Score.rank(q, apps, p.counts, 8).map(a => ({
            title: a.name,
            subtitle: a.genericName || a.entry.comment,
            iconName: a.entry.icon,
            run: () => { p.record(a.entry); a.entry.execute(); },
        }));
    }
}
