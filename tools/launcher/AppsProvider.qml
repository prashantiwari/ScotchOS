// Installed applications, from the desktop entries Quickshell already reads (no process to spawn).
import Quickshell

Provider {
    name: "Apps"
    glyph: ""
    placeholder: "Search applications"
    keywords: ["app"]
    inDefault: true

    search: q => {
        const s = q.trim().toLowerCase();
        const found = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue;
            const n = e.name.toLowerCase();
            let score = -1;
            if (!s) score = 1;
            else if (n.startsWith(s)) score = 3;
            else if (n.includes(s)) score = 2;
            else if ((e.genericName + " " + e.keywords.join(" ")).toLowerCase().includes(s)) score = 1;
            if (score >= 0) found.push({ e, score, n });
        }
        found.sort((a, b) => b.score - a.score || a.n.localeCompare(b.n));
        return found.slice(0, 8).map(f => ({
            title: f.e.name,
            subtitle: f.e.genericName || f.e.comment,
            iconName: f.e.icon,
            run: () => f.e.execute(),
        }));
    }
}
