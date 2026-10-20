// Ranking the launcher's applications: pure functions (no Quickshell), so tools/launcher/tests/score.test.mjs
// runs this same code under node; AppsProvider.qml feeds it the desktop entries and the launch counts.
.pragma library

// Gaps between the match kinds are bigger than the largest launch bonus, so a bad match never beats a good one.
const TIER = { prefix: 4000, contains: 3000, initials: 2000, command: 1500, other: 1000 };
const MAX_BONUS = 400;

// The program an Exec line runs: skips `env`, VAR=value and flags before it, the path, and any %U field codes.
function execBasename(exec) {
    const words = (exec || "").trim().split(/\s+/);
    let i = 0;
    while (i < words.length && (words[i] === "env" || words[i].includes("=") || words[i].startsWith("-"))) i++;
    const cmd = (words[i] || "").replace(/^["']|["']$/g, "");
    return cmd.split("/").pop().toLowerCase();
}

// First letter of each word, also at camelCase breaks: "Visual Studio Code" -> "vsc", "LibreOffice" -> "lo".
function initials(name) {
    return (name.match(/[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+/g) || []).map(w => w[0].toLowerCase()).join("");
}

// Launches rise quickly then flatten (3 launches = 200, 15 or more = the cap).
function bonus(count) { return Math.min(MAX_BONUS, Math.round(100 * Math.log2(1 + (count || 0)))) }

// How well an app matches `query` (already trimmed and lower-cased), or -1 for no match.
// app = { name, exec, genericName, keywords: [string] }
function score(query, app, count) {
    const name = app.name.toLowerCase();
    let tier = -1;
    if (name.startsWith(query)) tier = TIER.prefix;
    else if (name.includes(query)) tier = TIER.contains;
    else if (query.length >= 2 && initials(app.name).startsWith(query)) tier = TIER.initials;
    else if (execBasename(app.exec).includes(query)) tier = TIER.command;
    else if (((app.genericName || "") + " " + (app.keywords || []).join(" ")).toLowerCase().includes(query)) tier = TIER.other;
    return tier < 0 ? -1 : tier + bonus(count);
}

// The best `limit` apps for the query, best first. No query: most launched first, then by name.
// counts = { desktop id: launches }; each app also has an `id`.
function rank(query, apps, counts, limit) {
    const q = query.trim().toLowerCase();
    const found = [];
    for (const app of apps) {
        const n = counts[app.id] || 0;
        const s = q ? score(q, app, n) : n;
        if (s >= 0) found.push({ app, s, name: app.name.toLowerCase() });
    }
    found.sort((a, b) => b.s - a.s || a.name.localeCompare(b.name));
    return found.slice(0, limit).map(f => f.app);
}
