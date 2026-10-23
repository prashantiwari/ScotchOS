// Saved theories as Markdown notes: pure functions (no Quickshell), so tests/notes.test.mjs runs this same code under
// node. DailyTheory.qml writes one file per theory that's saved or has highlights, and reads the folder back with these.
.pragma library

// The marks NFKD splits off accented letters, so "Café" becomes "cafe" rather than "caf-".
const combining = new RegExp("[" + String.fromCharCode(0x300) + "-" + String.fromCharCode(0x36f) + "]", "g");
const sep = " · ";

function slug(s) {
    return String(s ?? "").normalize("NFKD").replace(combining, "").toLowerCase()
        .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80).replace(/-+$/, "");
}

// "Existence Precedes Essence" → "existence-precedes-essence.md"; the id is added only when that name is taken
// (by another theory, or by a file of your own), so nothing is overwritten.
function fileName(th, taken) {
    const base = slug(th.title) || th.id;
    return (taken ?? []).includes(base + ".md") ? base + "-" + th.id + ".md" : base + ".md";
}

// Local time, minutes only: what a person reads in the note, and what fromMarkdown() turns back into a date.
function stamp(iso) {
    const d = new Date(iso);
    const p = n => String(n).padStart(2, "0");
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + " " + p(d.getHours()) + ":" + p(d.getMinutes());
}
function unstamp(s) {
    const m = String(s).match(/^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d)$/);
    return m ? new Date(+m[1], m[2] - 1, +m[3], +m[4], +m[5]).toISOString() : "";
}

// [title](<url>): the angle brackets let a url hold spaces or parentheses; ] and \ in the title are escaped.
function link(title, url) {
    const t = String(title ?? "").replace(/([\\\[\]])/g, "\\$1");
    return url ? "[" + t + "](<" + String(url).replace(/>/g, "%3E") + ">)" : t;
}
function quote(text) { return String(text).split("\n").map(l => l ? "> " + l : ">").join("\n") }

// note: { saved, saved_at, highlights: [{ text, saved_at }] }. Highlights are listed in the order they appear in the
// theory, which reads better in a document than the order they were saved in.
function toMarkdown(th, note) {
    const tags = ["dailytheory", slug(th.topic), slug(th.subtopic)].filter((t, i, all) => t && all.indexOf(t) === i);
    const front = [
        ["id", th.id], ["title", th.title], ["originator", th.originator], ["topic", th.topic], ["subtopic", th.subtopic],
        ["tags", tags], ["saved", !!note.saved], ["saved_at", note.saved ? note.saved_at : undefined],
        ["generated_at", th.generated_at], ["model", th.model], ["disclaimer", th.disclaimer],
    ].filter(kv => kv[1] !== undefined && kv[1] !== null && kv[1] !== "")
     .map(kv => kv[0] + ": " + JSON.stringify(kv[1]));     // JSON strings and arrays are valid YAML

    const out = ["---"].concat(front, ["---", "", "# " + (th.title ?? "")]);
    const meta = [];
    if (th.originator) meta.push("**Originator:** " + th.originator);
    if (th.topic) meta.push("**Topic:** " + th.topic + (th.subtopic ? " › " + th.subtopic : ""));
    if (meta.length) out.push("", meta.join("  \n"));
    out.push("", String(th.theory ?? "").trim());
    if (th.key_takeaway) out.push("", quote("**Key takeaway:** " + th.key_takeaway));

    const body = String(th.theory ?? "");
    const hls = (note.highlights ?? []).slice().sort((a, b) => {
        const pa = body.indexOf(a.text.split("\n")[0]), pb = body.indexOf(b.text.split("\n")[0]);
        return (pa < 0 ? Infinity : pa) - (pb < 0 ? Infinity : pb) || (a.saved_at < b.saved_at ? -1 : 1);
    });
    if (hls.length) {
        out.push("", "## Highlights");
        for (const h of hls) out.push("", quote(h.text + "\n\n— saved " + stamp(h.saved_at)));
    }
    if ((th.sources ?? []).length) {
        out.push("", "## Sources", "");
        for (const s of th.sources) {
            const rest = [s.author ?? "", s.year ?? "", s.type ?? ""];
            while (rest.length && !rest[rest.length - 1]) rest.pop();
            out.push("- " + link(s.title, s.url) + (rest.length ? " — " + rest.join(sep) : ""));
        }
    }
    if ((th.related ?? []).length) {
        out.push("", "## Related", "");
        for (const r of th.related) out.push("- " + r);
    }
    if ((th.further_reading ?? []).length) {
        out.push("", "## Further reading", "");
        for (const f of th.further_reading) out.push("- " + link(f.title, f.url) + (f.author ? " — " + f.author : ""));
    }
    const foot = [th.disclaimer || "AI-generated; verify sources before citing.", th.model,
                  th.generated_at ? "generated " + stamp(th.generated_at) : ""].filter(x => x);
    out.push("", "---", "", "*" + foot.join(sep) + "*", "");
    return out.join("\n");
}

// A list line: "- [title](<url>) — rest", "- title — rest" or "- title".
function item(line) {
    const m = line.match(/^- +(?:\[((?:\\.|[^\]\\])*)\]\(<([^>]*)>\)|(.*?))(?: — (.*))?$/);
    if (!m) return null;
    return { title: (m[1] ?? m[3]).replace(/\\([\\\[\]])/g, "$1"), url: m[2] ?? "", rest: m[4] ?? "" };
}

// Back from a file this wrote (edits by hand are fine as long as the headings and list shapes stay): { theory, note },
// or null for a file that isn't a saved theory (no front matter with an id).
function fromMarkdown(text) {
    const m = String(text ?? "").replace(/\r\n/g, "\n").match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
    if (!m) return null;
    const fm = {};
    for (const line of m[1].split("\n")) {
        const kv = line.match(/^([A-Za-z_]+):\s*(.*)$/);
        if (!kv) continue;
        let v = kv[2].trim();
        if (/^["\[]|^(true|false)$/.test(v)) try { v = JSON.parse(v); } catch (e) {}
        fm[kv[1]] = v;
    }
    if (!fm.id) return null;

    // The footer (after the last ---) is rebuilt from the front matter, so it's dropped here.
    const body = m[2].replace(/\n---\n+[^\n]*\n*$/, "\n");
    const sections = { "": [] };
    let cur = "";
    for (const line of body.split("\n")) {
        const h = line.match(/^## +(.+?)\s*$/);
        if (h) { cur = h[1].toLowerCase(); sections[cur] = []; }
        else (sections[cur] = sections[cur] ?? []).push(line);
    }

    // The intro: title, the bold meta lines, the theory, then the key takeaway as a quote.
    const intro = sections[""].filter(l => !/^# /.test(l) && !/^\*\*(Originator|Topic):\*\*/.test(l));
    const qAt = intro.findIndex(l => /^> \*\*Key takeaway:\*\*/.test(l));
    const theoryText = (qAt < 0 ? intro : intro.slice(0, qAt)).join("\n").trim();
    const takeaway = qAt < 0 ? "" : intro.slice(qAt).filter(l => /^>/.test(l)).map(l => l.replace(/^> ?/, "")).join("\n")
                                         .replace(/^\*\*Key takeaway:\*\* */, "").trim();

    // Highlights: each is a run of quoted lines, its last line "— saved YYYY-MM-DD HH:MM".
    const highlights = [];
    let run = null;
    for (const line of (sections["highlights"] ?? []).concat([""])) {
        if (/^>/.test(line)) { (run = run ?? []).push(line.replace(/^> ?/, "")); continue; }
        if (!run) continue;
        let savedAt = "";
        const last = run.length - 1;
        const s = run[last].match(/^— saved (.+)$/);
        if (s) { savedAt = unstamp(s[1].trim()); run = run.slice(0, last); }
        const hlText = run.join("\n").trim();
        if (hlText) highlights.push({ text: hlText, saved_at: savedAt || fm.saved_at || "" });
        run = null;
    }

    const items = name => (sections[name] ?? []).map(item).filter(x => x);
    const theory = {
        id: fm.id, title: fm.title ?? "", originator: fm.originator ?? "", topic: fm.topic ?? "", subtopic: fm.subtopic ?? "",
        theory: theoryText, key_takeaway: takeaway,
        sources: items("sources").map(i => {
            const r = i.rest.split(sep);
            return { title: i.title, author: r[0] ?? "", year: r[1] ?? "", type: r[2] ?? "", url: i.url };
        }),
        related: (sections["related"] ?? []).filter(l => /^- /.test(l)).map(l => l.slice(2).trim()),
        further_reading: items("further reading").map(i => ({ title: i.title, author: i.rest, url: i.url })),
        disclaimer: fm.disclaimer ?? "", model: fm.model ?? "", generated_at: fm.generated_at ?? "",
    };
    return { theory: theory, note: { saved: fm.saved === true, saved_at: fm.saved_at ?? "", highlights: highlights } };
}
