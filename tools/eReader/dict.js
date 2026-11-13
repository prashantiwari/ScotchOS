// Dictionary lookups: which word a selection is, the forms of it to try in WordNet, and sdcv's answer made into
// senses. Pure functions (no Quickshell), so tools/eReader/tests/dict.test.mjs runs this same code under node;
// ReaderBook.qml runs sdcv and shows the card.
.pragma library

const POS = { n: "noun", v: "verb", adj: "adjective", adv: "adverb" };
// WordNet's own index has irregular forms (ran, men, better) but not regular ones (cats, hoped): these are
// WordNet's "morphy" endings, tried in this order, plus a doubled consonant (stopped, bigger).
const ENDINGS = [["ies", "y"], ["ied", "y"], ["s", ""], ["ses", "s"], ["xes", "x"], ["zes", "z"], ["ches", "ch"],
                 ["shes", "sh"], ["men", "man"], ["es", "e"], ["es", ""], ["ed", "e"], ["ed", ""], ["ing", "e"],
                 ["ing", ""], ["er", ""], ["est", ""], ["er", "e"], ["est", "e"]];
const LETTER = "A-Za-zÀ-ɏ";

// The selected text as one word (letters, with inner apostrophes or hyphens), or "" for more, or anything else.
function wordOf(text) {
    const t = String(text || "").replace(/[⁠￼]/g, "").replace(/[‘’]/g, "'").trim();
    const re = new RegExp(`^[${LETTER}]+(?:['-][${LETTER}]+)*'?$`);
    return t.length <= 40 && re.test(t) ? t : "";
}

// The forms to look up, best first: as written (o'clock, London), without a possessive, lower-cased, then each
// with an inflection taken off.
function forms(word) {
    const out = [];
    const add = w => { if (w.length > 1 && !out.includes(w)) out.push(w) };
    const bare = word.replace(/'s?$/i, "");
    for (const w of [word, bare, word.toLowerCase(), bare.toLowerCase()]) add(w);
    const low = bare.toLowerCase();
    for (const [end, put] of ENDINGS) {
        if (!low.endsWith(end) || low.length - end.length < 2) continue;
        const stem = low.slice(0, -end.length);
        add(stem + put);
        if (put === "" && /([b-df-hj-np-tv-z])\1$/.test(stem)) add(stem.slice(0, -1));
    }
    return out;
}

// {a} {b(p)} -> ["a", "b"]: the names in a [syn: …] list, without WordNet's (a) (p) (ip) position marks.
function braced(list) {
    return (list.match(/\{[^}]*\}/g) || []).map(s => s.slice(1, -1).replace(/\((?:a|p|ip)\)$/, ""));
}

// One sense: its gloss, then "quoted" examples after semicolons, then [syn: {…}] [ant: {…}] [also: {…}].
function sense(raw) {
    const syns = [];
    let t = raw.replace(/\s+/g, " ").replace(/\[(\w+): ([^\]]*)\]/g, (m, kind, list) => {
        if (kind === "syn") syns.push(...braced(list));
        return "";
    }).replace(/\{([^}]*)\}/g, "$1").trim();
    const at = t.indexOf('; "');
    const gloss = (at < 0 ? t : t.slice(0, at)).replace(/;\s*$/, "").trim();
    const examples = at < 0 ? [] : (t.slice(at).match(/"[^"]*"/g) || []).map(s => s.slice(1, -1));
    return { gloss: gloss, examples: examples, syns: syns };
}

// sdcv's text for one word: sections (blank-line separated) of a headword line, then senses that start 5 spaces
// in ("n 1: …", "2: …", "adv : …") and wrap onto deeper lines. A section saying only "See {be}" is left out
// (the entry it points to follows it). -> [{ head, pos, senses: [{ gloss, examples, syns }] }]
function parse(definition) {
    const entries = [];
    for (const block of String(definition).split(/\n[ \t]*\n/)) {
        const lines = block.split("\n").filter(l => l.trim());
        if (lines.length < 2) continue;
        const head = lines[0].trim();
        let entry = null, raw = null;
        const done = () => {
            if (raw === null || !entry) return;
            const s = sense(raw);
            s.syns = s.syns.filter(x => x.toLowerCase() !== head.toLowerCase());
            if (s.gloss) entry.senses.push(s);
            raw = null;
        };
        for (const line of lines.slice(1)) {
            const m = /^ {5}(?:(n|v|adj|adv) +(?=\d|:))?\d*: ?(.*)$/.exec(line);
            if (m) {
                done();
                if (m[1] || !entry) {
                    entry = { head: head, pos: POS[m[1]] ?? "", senses: [] };
                    entries.push(entry);
                }
                raw = m[2];
            } else if (/^ {6}/.test(line) && raw !== null) {
                raw += " " + line.trim();
            } else {
                done();                     // "See {be}", "[also: …]": not part of a sense
            }
        }
        done();
    }
    return entries.filter(e => e.senses.length);
}

// sdcv -j's output for forms(word): one JSON array per form, in that order. The first form with an entry wins;
// entries for that very form come before the ones it points to (running: the adjective, then the verb run).
// -> { word, head, entries } or null.
function lookup(word, output) {
    for (const line of String(output || "").split("\n")) {
        let found;
        try { found = JSON.parse(line); } catch (e) { continue; }
        if (!Array.isArray(found) || !found.length) continue;
        const entries = [];
        for (const f of found) entries.push(...parse(f.definition));
        if (!entries.length) continue;
        const form = String(found[0].word).toLowerCase();
        const own = entries.filter(e => e.head.toLowerCase() === form);
        const sorted = own.concat(entries.filter(e => e.head.toLowerCase() !== form));
        return { word: word, head: sorted[0].head, entries: sorted };
    }
    return null;
}
