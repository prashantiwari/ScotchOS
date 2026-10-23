// tools/dailyTheoryClient/notes.js: a theory with its highlights, to Markdown and back.
// Run: node --test tools/dailyTheoryClient/tests/   (or `scotchos test`)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
// notes.js is a QML JavaScript library: without its `.pragma library` line it's plain JS.
const src = readFileSync(join(repo, "tools/dailyTheoryClient/notes.js"), "utf8").replace(/^\.pragma library$/m, "");
const N = new Function(src + "\nreturn { slug, fileName, stamp, unstamp, toMarkdown, fromMarkdown };")();

// Shaped like API.md's example, with the awkward bits: parentheses in an author, ] in a title, a "Café".
const th = {
    id: "th_8c1e2a9f0b3d",
    title: "Dichotomy of Control",
    originator: "Epictetus",
    topic: "Philosophy",
    subtopic: "Stoicism",
    theory: "Epictetus, a former slave turned teacher, argued that some things are up to us.\n\nThe mechanism is simple: sort, then act.",
    key_takeaway: "Before reacting, ask: is this up to me?",
    sources: [
        { title: "Enchiridion", author: "Epictetus (recorded by Arrian)", year: "c. 125 CE", type: "primary",
          url: "https://scholar.google.com/scholar?q=Enchiridion+Epictetus+%28recorded+by+Arrian%29" },
        { title: "Notes [draft] on Café Stoa", author: "", year: "", type: "", url: "" },
    ],
    related: ["Amor fati", "Locus of control"],
    further_reading: [
        { title: "A Guide to the Good Life", author: "William B. Irvine", url: "https://openlibrary.org/search?q=A+Guide" },
        { title: "Dichotomy of Control", author: "Wikipedia", url: "https://en.wikipedia.org/wiki/Special:Search?search=Dichotomy+of+Control" },
    ],
    disclaimer: "AI-generated summary; verify sources before citing.",
    model: "gemini-3.5-flash-lite",
    generated_at: "2026-10-20T09:15:31Z",
};
const at = (h, m) => new Date(2026, 9, 23, h, m).toISOString();
const note = {
    saved: true,
    saved_at: at(8, 0),
    highlights: [
        { text: "sort, then act.", saved_at: at(8, 1) },
        { text: "some things are up to us.\n\nThe mechanism is simple", saved_at: at(8, 2) },
    ],
};

test("slug and fileName: lowercase ascii, accents dropped, the id only on a clash", () => {
    assert.equal(N.slug("Café: Existence Precedes Essence!"), "cafe-existence-precedes-essence");
    assert.equal(N.fileName(th, []), "dichotomy-of-control.md");
    assert.equal(N.fileName(th, ["dichotomy-of-control.md"]), "dichotomy-of-control-th_8c1e2a9f0b3d.md");
    assert.equal(N.fileName({ id: "th_x", title: "???" }, []), "th_x.md");
});

test("stamp and unstamp round-trip to the minute", () => {
    assert.equal(N.stamp(at(8, 1)), "2026-10-23 08:01");
    assert.equal(N.unstamp("2026-10-23 08:01"), at(8, 1));
    assert.equal(N.unstamp("yesterday"), "");
});

test("toMarkdown has the front matter, every section and the highlights in reading order", () => {
    const md = N.toMarkdown(th, note);
    assert.match(md, /^---\nid: "th_8c1e2a9f0b3d"\ntitle: "Dichotomy of Control"\n/);
    assert.match(md, /\ntags: \["dailytheory","philosophy","stoicism"\]\n/);
    assert.match(md, /\nsaved: true\n/);
    assert.match(md, /\n# Dichotomy of Control\n\n\*\*Originator:\*\* Epictetus  \n\*\*Topic:\*\* Philosophy › Stoicism\n/);
    assert.match(md, /\n> \*\*Key takeaway:\*\* Before reacting/);
    assert.match(md, /\n- \[Enchiridion\]\(<https:\/\/scholar[^>]*>\) — Epictetus \(recorded by Arrian\) · c\. 125 CE · primary\n/);
    assert.match(md, /\n- Notes \\\[draft\\\] on Café Stoa\n/);
    assert.match(md, /\n## Related\n\n- Amor fati\n- Locus of control\n/);
    assert.match(md, /\n- \[A Guide to the Good Life\]\(<https:\/\/openlibrary[^>]*>\) — William B\. Irvine\n/);
    // "some things…" comes first in the theory, though it was saved second.
    assert.ok(md.indexOf("> some things are up to us.") < md.indexOf("> sort, then act."));
    assert.match(md, /> some things are up to us\.\n>\n> The mechanism is simple\n>\n> — saved 2026-10-23 08:02\n/);
});

test("fromMarkdown gives back the same theory and note", () => {
    const back = N.fromMarkdown(N.toMarkdown(th, note));
    assert.deepEqual(back.theory, th);
    assert.equal(back.note.saved, true);
    assert.equal(back.note.saved_at, note.saved_at);
    assert.deepEqual(back.note.highlights.slice().sort((a, b) => a.saved_at < b.saved_at ? -1 : 1), note.highlights);
});

test("a theory that's only highlighted, with no optional sections, round-trips too", () => {
    const bare = { id: "th_b", title: "Bare", theory: "One paragraph.", sources: [], related: [], further_reading: [] };
    const back = N.fromMarkdown(N.toMarkdown(bare, { saved: false, highlights: [{ text: "One", saved_at: at(9, 0) }] }));
    assert.equal(back.note.saved, false);
    assert.equal(back.theory.theory, "One paragraph.");
    assert.equal(back.theory.disclaimer, "");
    assert.deepEqual(back.note.highlights, [{ text: "One", saved_at: at(9, 0) }]);
});

test("fromMarkdown skips files that aren't saved theories", () => {
    assert.equal(N.fromMarkdown("# My own notes\n\nNothing to see."), null);
    assert.equal(N.fromMarkdown("---\ntitle: \"x\"\n---\n# x\n"), null);
});
